# --- dependencies ------------------------------------------------------------

hash mkfs.vfat
hash mount

# ---- functions --------------------------------------------------------------

fat_format() {
  local -r label=$1 && shift
  mkfs.vfat -n "$label" "$@" 1>&2;
}
declare -rf fat_format

efi_format() { fat_format EFI "$@"; }
declare -rf efi_format

mount() {
  command mount "$@"
  cleanup_register umount "$_"
}
declare -rf mount

temporary_file() {
  file=$(mktemp)
  cleanup_register rm "$file"
  printf -- '%s\n' "$_"
}
declare -rf temporary_file

temporary_directory() {
  directory=$(mktemp -d)
  cleanup_register rm -r "$directory"
  printf -- '%s\n' "$_"
}
declare -rf temporary_directory

mount_temporary() {
  directory=$(temporary_directory)
  mount "$@" "$directory"
  printf -- '%s\n' "$directory"
}
declare -rf mount_temporary
