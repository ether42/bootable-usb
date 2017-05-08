# useful variables
declare -r bios_script_directory="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
declare -r bios_directory="$esp_mount"/bios

# install some bios-flashing utilities
mkdir "$bios_directory"
cp -r "$bios_script_directory"/bios/GB-BXi3-5010 "$bios_directory"
