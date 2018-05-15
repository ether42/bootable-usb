#!/usr/bin/env bash

set -eu

readonly script_directory=$(
  cd "$(dirname "${BASH_SOURCE[0]}")" > /dev/null && pwd)

exec sphinx-build -b singlehtml "$script_directory" "${1:-documentation}"
