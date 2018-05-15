# error: unsupported gzip format
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=869771

# --- dependencies -------------------------------------------------------------

# grub-{pc,efi-amd64}-bin
readonly grub_i386_pc_lib=/usr/lib/grub/i386-pc/ &&
  [ -d "$grub_i386_pc_lib" ]
readonly grub_x86_64_efi_lib=/usr/lib/grub/x86_64-efi/ &&
  [ -d "$grub_x86_64_efi_lib" ]
readonly grub_share=/usr/share/grub &&
  [ -d "$grub_share" ]

# --- grub ---------------------------------------------------------------------

grub_configuration_header() {
  local file
  read -r file < <(temporary_file grub_config.XXXXXXXXXX)
  cat > "$file" << EOF
insmod all_video

insmod serial
serial --speed=115200 --unit=0 --word=8 --parity=no --stop=1
EOF
  printf -- '%s\n' "$file"
}
declare -rf grub_configuration_header

grub_configuration_debian_live() {
  local file
  read -r file < <(temporary_file grub_config.XXXXXXXXXX)
  cat > "$file" << EOF
submenu 'Debian Live' {
EOF

  # https://manpages.debian.org/jessie/live-boot-doc/live-boot.7.en.html
  local -a kernel_parameters=(
    # noprompt noeject
    boot=live
    console=ttyS0,115200n8 console=tty0
    persistence
    # allow both unencrypted and encrypted persistence
    persistence-encryption=none,luks
    # load the whole image to ram, allow to remove the usb once booted
    toram
    # don't overwrite the system's fstab
    nofstab
  )

  if [ -n "${1:-}" ]; then
    kernel_parameters+=(findiso="$1")
    cat >> "$file" << EOF
  # mount both the iso and the squashfs
  loopback debian_iso "$1"
  loopback debian_squashfs (debian_iso)/live/filesystem.squashfs
EOF
  else
    cat >> "$file" << EOF
  # mount the squashfs
  loopback debian_squashfs /live/filesystem.squashfs
EOF
  fi

  local -r kernel='(debian_squashfs)/vmlinuz'
  local -r initrd='(debian_squashfs)/initrd.img'
  cat >> "$file" << EOF
  menuentry 'Debian Live' {
    linux "$kernel" ${kernel_parameters[@]}
    initrd "$initrd"
  }
EOF
  for option in ip=frommedia nopersistence verify-checksums; do
    cat >> "$file" << EOF
  menuentry 'Debian Live ($option)' {
    linux "$kernel" ${kernel_parameters[@]} $option
    initrd "$initrd"
  }
EOF
  done
  echo '}' >> "$file"

  printf -- '%s\n' "$file"
}
declare -rf grub_configuration_debian_live
