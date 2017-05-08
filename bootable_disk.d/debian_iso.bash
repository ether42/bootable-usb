# --- installation ------------------------------------------------------------

if [ -n "${debian_iso:-}" ]; then
    local -r debian_iso_path=$images_prefix/$(basename "$debian_iso")
    cat "$(grub_config_debian_live "$debian_iso_path")" \
      >> "$efi_filesystem_mount/$grub_config"
    cp "$debian_iso" "$images_directory"
fi
