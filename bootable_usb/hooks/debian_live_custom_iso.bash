if [ "${2:-}" ]; then # we expect another parameter (pah to the iso) for the main script
    # useful variables
    declare -r iso="$(basename "$2")"
    declare -r iso_path="$images_directory"/"$iso"
    # linux
    declare -r live_kernel='(debian_live_custom_squashfs)/vmlinuz'
    declare -r live_initrd='(debian_live_custom_squashfs)/initrd.img'
    declare -ar live_kernel_parameters=(
        # https://manpages.debian.org/jessie/live-boot-doc/live-boot.7.en.html
        # ip=frommedia
        # encryption (doesn't work anymore with recent losetup, requires to copy the kernel outside of the iso)...
        noprompt noeject
        boot=live
        findiso="$iso_path"
        console=ttyS0,115200n8 console=tty0
        persistence
        persistence-encryption=none,luks # allow both unencrypted and encrypted persistence
        toram # load the whole image to ram, allow to remove the usb once booted
    )
    # xen
    declare -r xen_kernel='(debian_live_custom_squashfs)/boot/xen-4.8-amd64.gz' # FIXME: remove the hardcoded version?
    declare -ar xen_kernel_parameters=(
        dom0_max_vcpus=1
        dom0_vcpus_pin
        dom0_mem=1024M
    )

    # copy the iso
    cp "$2" "$esp_mount"/"$images_directory"

    # grub configuration
    cat >> "$grub_config" << EOF
submenu 'Debian Live (custom)' {
  # mount the iso & squashfs
  loopback debian_live_custom_iso "$iso_path"
  loopback debian_live_custom_squashfs (debian_live_custom_iso)/live/filesystem.squashfs

  menuentry 'Debian Live (custom)' {
    linux "$live_kernel" ${live_kernel_parameters[@]}
    initrd "$live_initrd"
  }
  menuentry 'Xen - Debian Live (custom)' {
    # multiboot2/module2 for efi & xen 4.9?
    multiboot "$xen_kernel" ${xen_kernel_parameters[@]}
    module "$live_kernel" ${live_kernel_parameters[@]}
    module "$live_initrd"
  }
  menuentry 'Debian Live (custom) - no persistence' {
    linux "$live_kernel" ${live_kernel_parameters[@]} nopersistence
    initrd "$live_initrd"
  }
}
EOF
fi
