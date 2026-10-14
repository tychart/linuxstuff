# Prefer Fish for interactive Zsh work when it is installed.
# This stays tiny on purpose: the full shell setup lives in Fish/Bash config,
# and missing Fish should never break Zsh startup. `command -v` is evaluated
# by Zsh after its normal startup files have populated PATH.
if [[ -o interactive ]] && [[ -z "${FISH_VERSION:-}" ]]; then
  __setupconfig_fish="$(command -v fish 2>/dev/null || true)"
  if [[ -n "$__setupconfig_fish" ]]; then
    exec "$__setupconfig_fish"
  fi
  unset __setupconfig_fish
fi
