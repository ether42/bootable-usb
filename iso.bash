#!/usr/bin/env bash

readonly script_directory=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)
. "$script_directory"/library/source.bash

# --- dependencies -------------------------------------------------------------

hash grub-mkimage
hash sha256sum
hash xorriso

# --- build --------------------------------------------------------------------

grub() {
  # build all grub images, output their paths
  #  - bios cdrom image
  #  - bios disk image
  #  - efi 64 image
  local -r grub_prefix=/boot/grub/
  local -r grub_directory=$1/$grub_prefix

  grub_image() {
    local -r format=$1 && shift
    local ouptut header
    read -r output < <(temporary_file grub_"$format".XXXXXXXXXX)
    read -r header < <(grub_configuration_header)
    local -ar grub_mkimage=(
      grub-mkimage
      --format "$format"
      --prefix "${grub_prefix%/}"
      --config "$header"
      --output "$output"
    ) && "${grub_mkimage[@]}" "$@"
    printf -- '%s\n' "$output"
  }
  declare -rf grub_image

  # based on grub-install...
  local data='(*.mod|*.o|*.lst|boot.img|grub.efi|core.img|core.efi|modinfo.sh)'
  mkdir -p "$grub_directory"/fonts && cp "$grub_share"/unicode.pf2 "$_"

  local -ar i386_pc_modules=(iso9660 biosdisk)
  local -ar x86_64_efi_modules=(iso9660)
  for format in i386-pc x86_64-efi; do
    # copy grub's modules
    mkdir -p "$grub_directory/$format"
    cp /usr/lib/grub/"$format"/*$data "$grub_directory$format"

    # generate grub images for each format and medium
    local -n modules=${format/-/_}_modules
    local output
    read -r output < <(grub_image "$format" "${modules[@]}")
    if [ "$format" = i386-pc ]; then
      # cdrom image
      cat "$grub_i386_pc_lib"cdboot.img "$output" \
        > "$grub_directory$format".cdboot.img
      printf -- '%s\n' "$grub_prefix$format".cdboot.img
      # disk image
      cat "$grub_i386_pc_lib"boot.img "$output" > "$output.$format".boot.img
      cleanup_register rm "$output.$format".boot.img
      printf -- '%s\n' "$output.$format".boot.img
    elif [ "$format" = x86_64-efi ]; then
      # efi image
      local -r efi_filesystem=$grub_directory$format.img
      truncate --size 512K "$efi_filesystem"
      format_efi "$efi_filesystem"
      local efi_filesystem_mount
      read -r efi_filesystem_mount < <(temporary_mount "$efi_filesystem")
      mkdir -p "$efi_filesystem_mount"/efi/boot
      mv "$output" "$_"/bootx64.efi
      # umount "$efi_filesystem_mount"
      printf -- '%s\n' "$grub_prefix$format".img
    else
      !
    fi
  done

  cat "$(grub_configuration_header)" "$(grub_configuration_debian_live)" \
    > "$grub_directory"/grub.cfg
}
declare -rf grub

iso() {
  local iso_directory
  read -r iso_directory < <(temporary_directory)

  mkdir -p "$iso_directory"/live
  cp "$1" "$_"/filesystem.squashfs

  < <(grub "$iso_directory") readarray -t outputs
  [ ${#outputs[@]} -eq 3 ]

  (cd "$iso_directory" &&
   find . -type f -not -name sha256sum.txt -not -name i386-pc.cdboot.img |
     xargs sha256sum > sha256sum.txt)

  declare -ar xorriso=(
    command xorriso -as mkisofs
    "$iso_directory"
    -verbose
    # iso generation
    -full-iso9660-filenames
    -joliet
    -rational-rock
    -graft-points
    # -volid 'Debian' # more exist
    -output "$2"
    --boot-catalog-hide
    # bios
    -eltorito-boot "${outputs[0]}"
    -no-emul-boot
    -boot-load-size 4 # ?
    -boot-info-table
    --embedded-boot "${outputs[1]}"
    --protective-msdos-label
    # efi
    -eltorito-alt-boot
    --efi-boot "${outputs[2]}"
    -no-emul-boot
    -isohybrid-gpt-basdat # ?
  ) && "${xorriso[@]}"
}
declare -rf iso

# --- execution ----------------------------------------------------------------

iso "${1:-debian.squashfs}" "${2:-debian.iso}"
