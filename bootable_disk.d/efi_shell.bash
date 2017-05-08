# --- dependencies ------------------------------------------------------------

hash wget

# --- installation ------------------------------------------------------------

local -r tianocore_shell_url='https://github.com/tianocore/edk2/raw/master/ShellBinPkg/UefiShell'

wget -O "$images_directory"/shellx64.efi "$tianocore_shell_url"/X64/Shell.efi

cat >> "$efi_filesystem_mount/$grub_config" << EOF
menuentry 'EFI shell' {
  chainloader "$images_prefix/shellx64.efi"
}
EOF
