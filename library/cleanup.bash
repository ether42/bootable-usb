# --- dependencies ------------------------------------------------------------

hash tac

# --- functions ---------------------------------------------------------------

declare -r cleanup_script=$(mktemp)

cleanup_register() {
  { printf -- '%q ' "$@"
    printf -- '>& /dev/null \n'
  } >> "$cleanup_script"
}
declare -rf cleanup_register

cleanup() {
  local -r code=$?
  tac "$cleanup_script" | "$SHELL" || true
  rm "$cleanup_script"
  exit $code
}
declare -rf cleanup
trap cleanup EXIT
trap cleanup INT
