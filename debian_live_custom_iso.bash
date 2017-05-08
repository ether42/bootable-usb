#!/usr/bin/env bash

set -eux

[ -n "${1:-}" ] # work directory
mkdir -p "$1" # optional, could be a mounted tmpfs, for example

# useful variables
declare -r script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -rx assets_directory="$script_directory"/debian_live_custom_iso
declare -rx root_password="${PASSWORD:-root}"
declare -r chroot_directory="$1"/chroot
declare -r iso_directory="$1"/iso

# necessary dependencies
hash debootstrap
hash mksquashfs
hash xorrisofs
hash sha256sum

# debootstrap the debian
# FIXME: should use live-build?
rm -rf "$chroot_directory"
debootstrap \
    --arch=amd64 \
    --merged-usr \
    --include="linux-image-amd64 live-boot $(cat "$assets_directory"/packages.txt)" \
    stretch "$chroot_directory"

# cleaning up our mess
cleanup() {
  umount "$chroot_directory"/proc || true
  umount "$chroot_directory"/sys || true
  umount "$chroot_directory"/dev/pts || true
}
declare -rf cleanup
trap cleanup INT

# customizing the chrooted debian
mount none -t proc "$chroot_directory"/proc
mount none -t sysfs "$chroot_directory"/sys
mount none -t devpts "$chroot_directory"/dev/pts
[ "$(type -t customize_chroot)" = 'function' ] || . "$assets_directory"/customize_chroot.bash
[ "$(type -t customize_chroot)" = 'function' ] # assert the function was defined in the sourced script
declare -rfx customize_chroot
sed -i 's/#CRYPTSETUP=/CRYPTSETUP=y/' "$chroot_directory"/etc/cryptsetup-initramfs/conf-hook # force cryptsetup in initramfs
chroot "$chroot_directory" bash -c customize_chroot
chroot "$chroot_directory" apt-get clean
chroot "$chroot_directory" rm -rf /var/lib/apt/lists/
chroot "$chroot_directory" update-initramfs -u

cleanup
trap - INT

# making the live iso (not bootable)
mkdir -p "$iso_directory"/live
mksquashfs "$chroot_directory" "$iso_directory"/live/filesystem.squashfs -noappend
(cd "$iso_directory" && sha256sum live/* > sha256sum.txt) # optional, for verify-checksums option
xorrisofs -o "$1"/debian_live_custom.iso -v -V 'Debian Live (custom)' -r "$iso_directory"
