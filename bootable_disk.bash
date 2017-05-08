#!/usr/bin/env bash

declare -r script_directory=$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null \
  && pwd)
. "$script_directory"/library/source.bash

# --- dependencies ------------------------------------------------------------

hash cryptsetup
hash grub-install
hash lsblk
hash parted
hash partprobe
hash sha256sum
hash tar
hash truncate

# --- steps -------------------------------------------------------------------

format_disk() { # 1GiB required by default, output each partition's path
  local -r efi_end=$((${SIZE:-1021} + 1+1)) # 1023MiB
  # gpt disk
  parted --script "$1" mklabel gpt
  # grub's partition for bios machines (1MiB start alignment, 1MiB size)
  parted --script --align optimal "$1" mkpart GRUB 1MiB 2MiB
  parted --script "$1" set 1 bios_grub on
  # efi/data partition
  parted --script --align optimal "$1" mkpart ESP fat32 2MiB "$efi_end"MiB

  # wait for partitions to appear
  partprobe
  if hash udevadm >& /dev/null; then
    udevadm settle
  fi

  lsblk -n -r -o PARTUUID "$1" |
    sed -n 's#^\(.\+\)$#/dev/disk/by-partuuid/\1#p'
}
declare -rf format_disk

install_grub() {
  local -r boot_prefix=/boot/
  local -r grub_prefix=${boot_prefix}grub/
  local -r boot_directory=$2/$boot_prefix
  local -r grub_directory=$2/$grub_prefix
  local -ar grub_install_command=(
    grub-install
    --boot-directory "$boot_directory"
    --locales '' # won't match
  )
  # bios
  local -ar grub_install_bios_command=(
    "${grub_install_command[@]}"
    --target i386-pc
    "$1"
  ) && "${grub_install_bios_command[@]}"
  # efi
  local -ar grub_install_efi_command=(
    "${grub_install_command[@]}"
    --target x86_64-efi
    --efi-directory "$2"
    --bootloader-id boot
    --no-nvram
  ) && "${grub_install_efi_command[@]}"
  mv "$3"/{grubx64.efi,bootx64.efi} # default efi boot

  # cleanup grub's mess
  rmdir "$grub_directory"/locale || true
  rm "$grub_directory"/grubenv || true

  cat "$(grub_config_base)" > "$grub_directory"/grub.cfg
  printf -- '%s\n' "$grub_prefix"/grub.cfg
}
declare -rf install_grub

build_checksum() { # create the checksum partition
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
declare -rf build_checksum

build_disk() {
  # format the disk
  < <(format_disk "$1") readarray -t outputs
  [ ${#outputs[@]} -eq 2 ]

  # format the efi/data partition
  efi_format "${outputs[1]}"
  local efi_filesystem_mount
  read -r efi_filesystem_mount < <(mount_temporary "${outputs[1]}")
  local -r efi_boot_directory=$efi_filesystem_mount/efi/boot
  mkdir -p "$efi_boot_directory"

  # install grub
  local grub_config
  read -r grub_config < \
    <(install_grub "$1" "$efi_filesystem_mount" "$efi_boot_directory")

  # hooks that may install stuff
  shopt -s nullglob
  local -ar hooks=("$script_directory/${BASH_SOURCE[0]/.bash/.d}"/*.bash)
  shopt -u nullglob
  local -r images_prefix=/images
  local -r images_directory=$efi_filesystem_mount$images_prefix
  local -r debian_iso=${2:-}
  mkdir -p "$images_directory"
  for hook in "${hooks[@]}"; do
    . "$hook"
  done

  # finally, store all the checksums in an encrypted blob
  build_checksum "$efi_filesystem_mount" "$grub_config"
}
declare -rf build_disk

# --- execution ---------------------------------------------------------------

build_disk "$1" "${2:-}"
