# Prefer Fish for interactive Zsh work when it is installed.
# This stays tiny on purpose: the full shell setup lives in Fish/Bash config,
# and missing Fish should never break Zsh startup.
if [[ -o interactive ]] && [[ -z "${FISH_VERSION:-}" ]] && command -v fish >/dev/null 2>&1; then
  exec "$(command -v fish)"
fi
