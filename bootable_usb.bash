#!/usr/bin/env bash

set -eux

[ -n "${1:-}" ] # device to format

# useful variables
declare -r script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -rx assets_directory="$script_directory"/bootable_usb
declare -rx checksum_password="${PASSWORD:-root}"
# mount points stuff
declare -r device="$1"
declare -r checksum_partition="$device"2
declare -r grub_checksum_partition='(hd0,gpt2)' # FIXME: unsure if hd0 should always be he disk containing grub's configuration
declare -r esp_partition="$device"3
declare -r esp_size="${SIZE:-1024}" # MiB
declare -r esp_mount="$(mktemp -ud)"
declare -r grub_boot_directory="$esp_mount"/boot
declare -r grub_config="$grub_boot_directory"/grub/grub.cfg
declare -r efi_boot_directory="$esp_mount"/efi/boot
declare -r checksum_device_mapper=checksum-usb
# images stuff
declare -r images_directory=/images # not prefixed by $esp_mount, you should do it yourself

# necessary dependencies
hash parted
hash partprobe
hash udevadm
hash mkfs.vfat
hash grub-install
[ -d "/usr/lib/grub/i386-efi" ] # provided by grub-efi-ia32-bin
[ -d "/usr/lib/grub/x86_64-efi" ] # provided by grub-efi-amd64-bin
hash cryptsetup
hash tar
hash sha256sum

# format the device
parted --script "$device" mklabel gpt
parted --script --align=optimal "$device" mkpart GRUB 1MiB 2MiB # 1MiB
parted --script "$device" set 1 bios_grub on
parted --script --align=optimal "$device" mkpart CHECKSUM 2MiB 6MiB # 4 MiB (luks requires 1049600 bytes)
parted --script --align=optimal "$device" mkpart ESP fat32 6MiB "$((esp_size + 6))"MiB
partprobe
udevadm settle

# cleaning up our mess
cleanup() {
    umount "$esp_mount" || true
    rmdir "$esp_mount" || true
    cryptsetup luksClose "$checksum_device_mapper" || true
}
declare -rf cleanup
trap cleanup EXIT
trap cleanup INT

# format the efi partition
mkfs.vfat -n EFI "$esp_partition"
mkdir -p "$esp_mount"
mount "$esp_partition" "$esp_mount"
mkdir -p "$esp_mount"/"$images_directory"
mkdir -p "$efi_boot_directory" # force lowercase of EFI :)

# install grub for multiple architectures
declare -ar grub_install=(grub-install --recheck --boot-directory="$grub_boot_directory")
declare -ar grub_install_efi=("${grub_install[@]}" --efi-directory="$esp_mount" --bootloader-id=boot --no-nvram)
"${grub_install[@]}" --target=i386-pc "$device"
"${grub_install_efi[@]}" --target=i386-efi
mv "$efi_boot_directory"/{grubia32.efi,bootia32.efi}
rm "$efi_boot_directory"/grub.efi # artefact...
"${grub_install_efi[@]}" --target=x86_64-efi
mv "$efi_boot_directory"/{grubx64.efi,bootx64.efi}

# grub configuration
cat > "$grub_config" << EOF
# required for non-blind efi boot
insmod all_video

# serial console setup (may warn if you have none)
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1

function temporize {
  for i in 1 2 3; do
    echo -n .
    sleep 1
  done
}

menuentry 'Verify USB contents' {
  # guarantee integrity and that the device hasn't been tampered with
  insmod luks
  cryptomount $grub_checksum_partition
  if hashsum --hash sha256 --check (crypto0)/sha256sum.txt; then
    echo -n "Hashsum: OK"
  else
    echo -n "Hashsum: KO"
  fi
  temporize
}
EOF

# hooks that may install more choices
shopt -s nullglob
declare -ar hooks=("$assets_directory"/hooks/*.bash)
shopt -u nullglob
for hook in "${hooks[@]}"; do
    . "$hook"
done

# finally, setup the encrypted checksum partition
echo "$checksum_password" | cryptsetup --batch-mode luksFormat "$checksum_partition"
echo "$checksum_password" | cryptsetup luksOpen "$checksum_partition" "$checksum_device_mapper"
declare -r tar_directory=$(mktemp -d)
(cd "$esp_mount" && find . -type f -exec sha256sum {} \;) | sed 's#./#/#' > "$tar_directory"/sha256sum.txt
tar cf - -C "$tar_directory" . > /dev/mapper/"$checksum_device_mapper" # yes, the tar is the partition's filesystem
rm "$tar_directory"/sha256sum.txt
rmdir "$tar_directory"
