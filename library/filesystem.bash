# --- dependencies -------------------------------------------------------------

hash mkfs.vfat
hash mktemp
hash mount umount

# --- filesystem ---------------------------------------------------------------

format_efi() {
  # format a partition suitable for efi

  format_fat() {
    # format a partition as fat
    local -r label=$1 && shift
    mkfs.vfat -n "$label" "$@" 1>&2
  }
  declare -rf format_efi

  format_fat EFI "$@"
}
declare -rf format_efi

mount() {
  # mount something
  # take care of unmounting
  command mount "$@"
  cleanup_register umount "$_"
}
declare -rf mount

temporary_file() {
  # create a temporary file
  # take care of removal
  local file
  file=$(mktemp "${1:-file.XXXXXXXXXX}")
  cleanup_register rm "$file"
  printf -- '%s\n' "$_"
}
declare -rf temporary_file

temporary_directory() {
  # create a temporary directory
  # take care of removal
  local directory
  directory=$(mktemp -d "${1:-directory.XXXXXXXXXX}")
  cleanup_register rm -r "$directory"
  printf -- '%s\n' "$_"
}
declare -rf temporary_directory

temporary_mount() {
  # mount something on a temporary directory
  # take care of unmounting and removal
  local directory
  directory=$(temporary_directory mount.XXXXXXXXXX)
  mount "$@" "$directory"
  printf -- '%s\n' "$directory"
}
declare -rf temporary_mount
