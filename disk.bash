#!/usr/bin/env bash

readonly script_directory=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)
. "$script_directory"/library/source.bash

# --- dependencies -------------------------------------------------------------

hash cryptsetup
hash grub-install
hash lsblk
hash parted
hash parted partprobe
hash sha256sum
hash tar
hash truncate
hash udevadm
hash wget

# --- build --------------------------------------------------------------------

format() {
  # 1GiB required by default, output all partitions
  #  - bios_grub
  #  - efi
  local -r end=$((${SIZE:-1021} + 1 + 1)) # 1023MiB
  parted --script "$1" mklabel gpt
  # grub's partition for bios machines (1MiB start alignment, 1MiB size)
  parted --script --align optimal "$1" mkpart GRUB 1MiB 2MiB
  parted --script "$1" set 1 bios_grub on
  # efi & data partition
  parted --script --align optimal "$1" mkpart ESP fat32 2MiB "$end"MiB

  # wait for partitions
  partprobe || true # may fail with read-only mounted stuff
  udevadm settle

  # skip empty line
  lsblk --noheadings --raw --output PARTUUID "$1" |
    sed -n 's#^\(.\+\)$#/dev/disk/by-partuuid/\1#p'
}
declare -rf format

grub() {
  # install grub to a disk output its configuration path
  local -r boot_prefix=/boot/
  local -r grub_prefix=${boot_prefix}grub/
  local -r boot_directory=$2/$boot_prefix
  local -r grub_directory=$2/$grub_prefix

  local -ar grub_install=(
    grub-install
    --boot-directory "$boot_directory"
    --locales '' # won't match
  )
  # bios
  local -ar grub_install_bios=(
    "${grub_install[@]}"
    --target i386-pc
    "$1"
  ) && "${grub_install_bios[@]}"
  # efi
  local -ar grub_install_efi=(
    "${grub_install[@]}"
    --target x86_64-efi
    --efi-directory "$2"
    --bootloader-id boot
    --no-nvram
  ) && "${grub_install_efi[@]}"
  mv "$3"/{grubx64.efi,bootx64.efi} # default efi boot

  # cleanup grub's mess
  rmdir "$grub_directory"/locale || true
  rm "$grub_directory"/grubenv || true

  cat "$(grub_configuration_header)" > "$grub_directory"/grub.cfg
  printf -- '%s\n' "$grub_prefix"/grub.cfg
}
declare -rf grub

checksum() {
  # create an encrypted checksum file
  local -r checksum_file=$(dirname "$2")/checksum.bin
  cat >> "$1/$2" << EOF
function temporize {
  for i in 1 2 3; do
    echo -n .
    sleep 1
  done
}
menuentry 'Verify contents' {
  insmod luks
  loopback checksum "$checksum_file"
  cryptomount (checksum)
  if hashsum --hash sha256 --check (crypto0)/sha256sum.txt; then
    echo -n "Hashsum: OK"
  else
    echo -n "Hashsum: KO"
  fi
  temporize
}
EOF

  local tar_directory
  read -r tar_directory < <(temporary_directory)
  (cd "$1" && find . -type f -exec sha256sum {} \;) |
    sed 's#./#/#' > "$tar_directory"/sha256sum.txt

  local -r checksum_device_mapper=$(printf '%04x' "$RANDOM") # random name
  truncate -s 4MiB "$1/$checksum_file" # luks requires at least 1049600 bytes
  printf -- '%s\n' "${PASSWORD-root}" |
    cryptsetup --batch-mode luksFormat "$1/$checksum_file"
  printf -- '%s\n' "${PASSWORD-root}" |
    cryptsetup luksOpen "$1/$checksum_file" "$checksum_device_mapper"
  cleanup_register cryptsetup luksClose "$checksum_device_mapper"

  # directly use the tar file as the filesystem
  tar cf - -C "$tar_directory" . > /dev/mapper/"$checksum_device_mapper"
}
declare -rf checksum

disk() {
  # format the disk
  < <(format "$1") readarray -t outputs
  [ ${#outputs[@]} -eq 2 ]

  # format the efi/data partition
  format_efi "${outputs[1]}"
  local efi_filesystem_mount
  read -r efi_filesystem_mount < <(temporary_mount "${outputs[1]}")
  local -r efi_boot_directory=$efi_filesystem_mount/efi/boot
  mkdir -p "$efi_boot_directory"

  # install grub
  local grub_config
  read -r grub_config < \
    <(grub "$1" "$efi_filesystem_mount" "$efi_boot_directory")

  local -r images_prefix=/images
  local -r images_directory=$efi_filesystem_mount$images_prefix
  mkdir -p "$images_directory"

  # copy iso
  if [ -f "${2:-}" ]; then
    local -r debian_iso_path=$images_prefix/$(basename "$2")
    cat "$(grub_configuration_debian_live "$debian_iso_path")" \
      >> "$efi_filesystem_mount/$grub_config"
    cp "$2" "$images_directory"
  fi

  # efi shell
  local -r tianocore_shell_url='https://github.com/tianocore/edk2/raw/master/ShellBinPkg/UefiShell'
  wget -O "$images_directory"/shellx64.efi "$tianocore_shell_url"/X64/Shell.efi
  cat >> "$efi_filesystem_mount/$grub_config" << EOF
menuentry 'EFI shell' {
  chainloader "$images_prefix/shellx64.efi"
}
EOF

  # finally, checksum everything
  checksum "$efi_filesystem_mount" "$grub_config"
}
declare -rf disk

# --- execution ----------------------------------------------------------------

disk "${1:-}" "${2:-debian.iso}"
