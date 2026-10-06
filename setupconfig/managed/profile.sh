# Login shells read ~/.profile first, then pull in ~/.bashrc for interactive extras.
# The guard avoids an infinite loop when ~/.bashrc later sources ~/.profile.
# Use expr instead of a case statement here to keep this block friendly to
# older/vendor shells that may read ~/.profile.
if [ -n "${BASH_VERSION:-}" ] && [ -r "$HOME/.bashrc" ] && [ -z "${__SETUPCONFIG_SOURCING_PROFILE_FROM_BASHRC:-}" ] && expr "x$-" : 'x.*i' >/dev/null 2>&1; then
  . "$HOME/.bashrc"
fi

# Prefer user-local bin directories when they exist. Add them first, then
# dedupe once below so rerunning/sourceing this block does not grow PATH.
[ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"

# Bun: configure it only when installed so shells that do not use Bun pay
# almost no startup cost.
if [ -d "$HOME/.bun" ]; then
  export BUN_INSTALL="$HOME/.bun"
  [ -d "$BUN_INSTALL/bin" ] && PATH="$BUN_INSTALL/bin:$PATH"
fi

# Collapse duplicate entries while keeping the first occurrence, so the
# precedence above is preserved. Written without Bash-only locals so this
# block stays safe in ~/.profile on macOS/vendor shells.
__setupconfig_dedupe_path() {
  result=''
  old_ifs=$IFS
  IFS=':'
  for entry in $PATH; do
    [ -z "$entry" ] && continue
    duplicate=0
    for existing in $result; do
      if [ "$existing" = "$entry" ]; then
        duplicate=1
        break
      fi
    done
    [ "$duplicate" -eq 0 ] && result="${result:+$result:}$entry"
  done
  IFS=$old_ifs
  printf '%s' "$result"
}
PATH="$(__setupconfig_dedupe_path)"
unset -f __setupconfig_dedupe_path
unset result entry existing duplicate old_ifs
export PATH

# Extra path aditions go here
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$PATH"

# Editor defaults live here so other tools can simply inherit them.
export EDITOR="__DEFAULT_EDITOR__"
export VISUAL="__DEFAULT_EDITOR__"
export SYSTEMD_EDITOR="__DEFAULT_EDITOR__"
export INPUTRC="${INPUTRC:-$HOME/.inputrc}"
