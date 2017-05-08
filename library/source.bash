set -eu -o pipefail
shopt -s extglob

for file in "$(cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null &&
  pwd)"/!(source).bash; do
  . "$file"
done
