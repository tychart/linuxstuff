# Editor defaults should exist before any early return so child CLI tools inherit them.
export EDITOR="${EDITOR:-__DEFAULT_EDITOR__}"
export VISUAL="${VISUAL:-$EDITOR}"

# Stop here for non-interactive shells.
[[ $- == *i* ]] || return

# ~/.profile sources this file back, both in its managed block and in
# preserved user content. If we are already inside such a source, stop:
# everything below was already defined by the outer pass. Without this the
# two files would source each other forever and every shell would hang.
if [ -n "${__SETUPCONFIG_SOURCING_PROFILE_FROM_BASHRC:-}" ]; then
  return
fi

__SYSTEM_BASHRC_BLOCK__
# Many terminals start Bash as a non-login shell, which skips ~/.profile.
# Source it here so PATH and editor defaults are consistent in every shell.
# The guard prevents recursion because ~/.profile sources this file back.
if [ -r "$HOME/.profile" ]; then
  __SETUPCONFIG_SOURCING_PROFILE_FROM_BASHRC=1
  . "$HOME/.profile"
  unset __SETUPCONFIG_SOURCING_PROFILE_FROM_BASHRC
fi

# Prefer Fish for interactive work when it is installed.
if [ -z "${FISH_VERSION:-}" ] && command -v fish >/dev/null 2>&1; then
  exec "$(command -v fish)"
fi

export INPUTRC="${INPUTRC:-$HOME/.inputrc}"

# History behavior.
HISTCONTROL=ignoredups:erasedups
HISTSIZE=50000
HISTFILESIZE=100000
HISTTIMEFORMAT="%d/%m/%y %T "
shopt -s histappend
shopt -s checkwinsize

__setupconfig_history_sync() {
  # Append this shell's new history lines, then pull in lines from other shells.
  history -a
  history -n
}

if expr "x;${PROMPT_COMMAND:-};" : 'x.*;__setupconfig_history_sync;.*' >/dev/null 2>&1; then
  :
elif [ -z "${PROMPT_COMMAND:-}" ]; then
  PROMPT_COMMAND="__setupconfig_history_sync"
else
  PROMPT_COMMAND="__setupconfig_history_sync;${PROMPT_COMMAND}"
fi
export PROMPT_COMMAND

# Bash completion.
if [ -r /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
elif [ -r /etc/bash_completion ]; then
  . /etc/bash_completion
fi

if [ -r /usr/share/bash-completion/completions/git ]; then
  . /usr/share/bash-completion/completions/git
elif [ -r /etc/bash_completion.d/git ]; then
  . /etc/bash_completion.d/git
fi

# fzf integration (Ctrl-T/Ctrl-R/Alt-C keybindings and completion).
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --bash)"
fi

# Tool integrations. Each optional integration is guarded so a missing
# user-local binary never creates a broken alias or pager configuration.
if command -v eza >/dev/null 2>&1; then
  alias ll='eza -lag --git --icons --group-directories-first'
else
  # Portable fallback for systems whose ls does not support GNU color/grouping flags
  # (macOS, Termux, BusyBox, etc.).
  alias ll='ls -lah'
fi

if command -v bat >/dev/null 2>&1; then
  alias b='bat'

  # bat's direct man-page mode preserves groff formatting and adds readable
  # syntax colors. Avoid pre-processing through col: it can corrupt ANSI
  # sequences on modern man implementations.
  if command -v man >/dev/null 2>&1; then
    export MANPAGER='bat --plain --language=man'
  fi
fi

# Aliases.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias c='clear'
alias k='kubectl'
alias myip='hostname -I 2>/dev/null | awk "{print \$1}"'
alias src='source "$HOME/.profile"'
alias venv='source .venv/bin/activate'
alias ver='cat /etc/*-release'
alias vim='vim -u "$HOME/.vimrc"'
alias whoson='last -w | tac'
alias details='get_machine_info'

setupconfig() {
  curl -fsSL https://raw.githubusercontent.com/tychart/linuxstuff/main/setupconfig/setupconfig.sh | bash -s -- "$@"
}

if command -v zellij >/dev/null 2>&1; then
  alias z='zellij attach -c main'
fi

# Functions.
mmkdir() {
  if [ $# -ne 1 ]; then
    printf 'usage: mmkdir <dir>\n' >&2
    return 1
  fi

  command mkdir -p "$1" && cd -- "$1"
}

get_machine_info() {
  local distro version_id os ver name ip

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    distro="$ID"
    version_id="$VERSION_ID"
  else
    distro="unknown"
    version_id="unknown"
  fi

  if [ "$distro" = "ubuntu" ]; then
    os="ubu"
  else
    os="$distro"
  fi

  ver="${os}${version_id}"
  name="$(hostname)"
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [ -z "$ip" ]; then
    ip="$(hostname -i 2>/dev/null || true)"
  fi

  printf '******************************\n'
  printf 'Hostname: %s\n' "$name"
  printf 'IP address: %s\n' "$ip"
  printf 'Operating system: %s\n' "$ver"
  printf '******************************\n'
}

get_os_short() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    printf '%s%s' "$ID" "$VERSION_ID"
  else
    printf 'unknown'
  fi
}

ssu() {
  # Preserve your HOME and rc setup when opening a root shell.
  sudo --preserve-env=HOME env HOME="$HOME" bash --rcfile "$HOME/.bashrc" -i
}

y() {
  # Open yazi and change to the directory it left us in on exit.
  if ! command -v yazi >/dev/null 2>&1; then
    printf 'y: yazi is not installed; install it with your system package manager or this setup script on Linux x64.\n' >&2
    return 127
  fi

  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
  command rm -f "$tmp"
}


if ! command -v osc52 >/dev/null 2>&1; then
  osc52() {
      local data

      if [ $# -gt 0 ]; then
          data="$*"
      else
          data="$(cat)"
      fi

      local encoded

      if base64 --wrap=0 </dev/null >/dev/null 2>&1; then
          encoded="$(printf '%s' "$data" | base64 --wrap=0)"
      else
          encoded="$(printf '%s' "$data" | base64 | tr -d '\n')"
      fi

      printf '\033]52;c;%s\a' "$encoded"
  }
fi

# Prompt.
# NOTE: You mentioned you may replace this later with Starship.
# This section is intentionally isolated so it is easy to remove/swap.
__setupconfig_set_prompt() {
  if [ "$TERM" = "xterm-color" ]; then
    PS1='\u@\h \w $ '
    return
  fi

  if [ "$EUID" -ne 0 ]; then
    PS1='\[\e[1;32m\]\u\[\e[0m\]@\[\e[0;31m\]\h\[\e[1;36m\]($(get_os_short)) \[\e[1;34m\]\w \[\e[0m\]$ '
  else
    PS1='\[\e[1;35m\]\u\[\e[0m\]@\[\e[0;31m\]\h\[\e[1;36m\]($(get_os_short)) \[\e[1;34m\]\w\[\e[0m\] # '
  fi
}
__setupconfig_set_prompt
export PS1

# Readline quality-of-life.
bind 'set bell-style none'

# Delete backward until punctuation/whitespace instead of treating punctuation as part of a word.
my_custom_backwards_kill_word() {
  local line="$READLINE_LINE"
  local pos="$READLINE_POINT"
  local boundary_chars='[^[:alnum:]]'
  local char

  if [ "$READLINE_POINT" -eq 0 ]; then
    return
  fi

  (( pos-- ))
  while (( pos > 0 )); do
    char=${line:pos-1:1}
    if [[ $char =~ $boundary_chars ]]; then
      break
    fi
    (( pos-- ))
  done

  READLINE_LINE="${line:0:pos}${line:READLINE_POINT}"
  READLINE_POINT=$pos
}

# Ctrl+Backspace often arrives as Ctrl+H in terminals.
bind -x '"\C-h": my_custom_backwards_kill_word'

# Ctrl+W is rebound to match the custom Ctrl+Backspace behavior above.
bind -x '"\C-w": my_custom_backwards_kill_word'
