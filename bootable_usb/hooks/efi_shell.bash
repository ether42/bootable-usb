# necessary dependencies
hash curl

# useful variables
declare -r efi_shell_directory="$images_directory"/efi_shell
declare -r efi_shellia32="$efi_shell_directory"/shellia32.efi
declare -r efi_shellx64="$efi_shell_directory"/shellx64.efi
declare -r tianocore_shell_url='https://github.com/tianocore/edk2/raw/master/ShellBinPkg/UefiShell'

# install the efi shell
mkdir -p "$esp_mount"/"$efi_shell_directory"
curl -L -o "$esp_mount"/"$efi_shellia32" "$tianocore_shell_url"/Ia32/Shell.efi
curl -L -o "$esp_mount"/"$efi_shellx64" "$tianocore_shell_url"/X64/Shell.efi

# grub configuration
cat >> "$grub_config" << EOF
submenu 'EFI shell' {
  menuentry 'EFI shell - IA32' {
    chainloader "$efi_shellia32"
  }
  menuentry 'EFI shell - X64' {
    chainloader "$efi_shellx64"
  }
}
EOF
