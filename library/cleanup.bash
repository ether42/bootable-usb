# --- dependencies -------------------------------------------------------------

hash mktemp
hash rm
hash tac

# --- cleanup ------------------------------------------------------------------

declare -r cleanup_script=$(mktemp cleanup.XXXXXXXXXX)

cleanup_register() {
  # register a simple cleanup command
  { printf -- '%q ' "$@"
    printf -- '>& /dev/null \n'
  } >> "$cleanup_script"
}
declare -rf cleanup_register

cleanup() {
  # cleanup hook
  local -r code=$?
  tac "$cleanup_script" | "$SHELL" -x || true
  rm "$cleanup_script"
  exit $code
}
declare -rf cleanup
trap cleanup EXIT
