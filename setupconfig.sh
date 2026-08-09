#!/usr/bin/env bash

# tychart setup bootstrap
#
# Purpose:
#   Apply a portable personal shell/Vim setup across Fedora, Ubuntu, and RHEL
#   without destructively replacing whole dotfiles.
#
# Behavior:
#   - Updates clearly marked managed blocks inside standard dotfiles
#   - Preserves user content outside those managed blocks
#   - Avoids backups when only script-owned managed content is being refreshed
#   - Installs the OSC 52 Vim plugin as ~/.vim/plugin/oscyank.vim
#   - Optionally installs fzf, ya, yazi, and zellij into ~/programs/bin from
#     the latest tychart/linuxstuff release: missing tools are downloaded via
#     curl, the folder is created if needed, and it is added to PATH in
#     ~/.profile (custom-patched builds like zellij then win over distros)
#   - Adds shell integration for them to the managed ~/.bashrc block: the y()
#     yazi wrapper, the zellij `z` alias, and fzf keybindings/completion
#   - Nice-to-have installs prompt interactively; with no TTY they are skipped
#     unless --install-optional is passed (auto-installs without prompting,
#     which is also what you want for piped installs on a fresh machine)
#
# Usage:
#   chmod +x setupconfig.sh
#   ./setupconfig.sh
#   ./setupconfig.sh --cleanup-backups
#   ./setupconfig.sh --install-optional
#   ./setupconfig.sh --cleanup-backups --install-optional
#
#   or
#   curl -fsSL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash -s -- --cleanup-backups
#   curl -fsSL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash -s -- --install-optional

set -euo pipefail

SCRIPT_TAG="tychart-setup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# Single source of truth for the preferred editor written into ~/.profile.
DEFAULT_EDITOR="vim"

# When set (--install-optional), missing nice-to-have tools are installed
# without prompting, even when the script runs without a TTY (e.g. piped).
INSTALL_NICE_TO_HAVES=0

PROFILE_FILE="$HOME/.profile"
BASH_PROFILE_FILE="$HOME/.bash_profile"
BASHRC_FILE="$HOME/.bashrc"
VIMRC_FILE="$HOME/.vimrc"
INPUTRC_FILE="$HOME/.inputrc"
VIM_DIR="$HOME/.vim"
VIM_PLUGIN_DIR="$VIM_DIR/plugin"
VIM_UNDO_DIR="$VIM_DIR/undodir"
OSCYANK_FILE="$VIM_PLUGIN_DIR/oscyank.vim"

log() {
  printf '[setup] %s\n' "$*"
}

show_usage() {
  cat <<EOF
Usage:
  ./setupconfig.sh
  ./setupconfig.sh --cleanup-backups
  ./setupconfig.sh --install-optional

  --cleanup-backups    remove backups created by previous runs
  --install-optional   install missing nice-to-have tools (fzf, ya, yazi,
                       zellij) into ~/programs/bin without prompting; also
                       auto-installs when the script is piped (no TTY)
EOF
}

cleanup_backups() {
  local count=0
  local file

  shopt -s nullglob

  for file in \
    "$HOME"/setupconfig_backup_.profile.* \
    "$HOME"/setupconfig_backup_.bash_profile.* \
    "$HOME"/setupconfig_backup_.bashrc.* \
    "$HOME"/setupconfig_backup_.vimrc.* \
    "$HOME"/setupconfig_backup_.inputrc.* \
    "$VIM_PLUGIN_DIR"/setupconfig_backup_oscyank.vim.* \
    "$HOME"/.profile.bak."$SCRIPT_TAG".* \
    "$HOME"/.bash_profile.bak."$SCRIPT_TAG".* \
    "$HOME"/.bashrc.bak."$SCRIPT_TAG".* \
    "$HOME"/.vimrc.bak."$SCRIPT_TAG".* \
    "$HOME"/.inputrc.bak."$SCRIPT_TAG".* \
    "$OSCYANK_FILE".bak."$SCRIPT_TAG".*
  do
    rm -f -- "$file"
    log "Removed backup $file"
    count=$((count + 1))
  done

  shopt -u nullglob

  if [ "$count" -eq 0 ]; then
    log "No setupconfig backup files found."
  else
    log "Removed $count backup file(s)."
  fi
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --cleanup-backups)
        cleanup_backups
        exit 0
        ;;
      --install-optional)
        INSTALL_NICE_TO_HAVES=1
        shift
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        show_usage >&2
        exit 1
        ;;
    esac
  done
}

parse_args "$@"

backup_file() {
  local file="$1"
  local backup
  local dir
  local base

  [ -e "$file" ] || return 0

  dir="$(dirname "$file")"
  base="$(basename "$file")"
  backup="${dir}/setupconfig_backup_${base}.${TIMESTAMP}"
  if [ ! -e "$backup" ]; then
    cp -a -- "$file" "$backup"
    log "Backed up $file -> $backup"
  fi
}

# Replace one managed block inside a file while leaving everything else alone.
upsert_managed_block() {
  local file="$1"
  local name="$2"
  local content="$3"
  local marker_prefix="${4:-#}"
  local start_marker="${marker_prefix} >>> ${SCRIPT_TAG}:${name} >>>"
  local end_marker="${marker_prefix} <<< ${SCRIPT_TAG}:${name} <<<"
  # Also recognize older marker styles so reruns can cleanly replace them.
  local legacy_hash_start="# >>> ${SCRIPT_TAG}:${name} >>>"
  local legacy_hash_end="# <<< ${SCRIPT_TAG}:${name} <<<"
  local legacy_vim_start="\" >>> ${SCRIPT_TAG}:${name} >>>"
  local legacy_vim_end="\" <<< ${SCRIPT_TAG}:${name} <<<"
  local tmp
  local preserved_tmp
  local first_preserved_line=''

  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  preserved_tmp="$(mktemp)"

  if [ -f "$file" ]; then
    awk \
      -v start="$start_marker" \
      -v end="$end_marker" \
      -v old_hash_start="$legacy_hash_start" \
      -v old_hash_end="$legacy_hash_end" \
      -v old_vim_start="$legacy_vim_start" \
      -v old_vim_end="$legacy_vim_end" '
        $0 == start || $0 == old_hash_start || $0 == old_vim_start { skip = 1; next }
        $0 == end   || $0 == old_hash_end   || $0 == old_vim_end   { skip = 0; next }
        !skip { print }
      ' "$file" > "$preserved_tmp"
  else
    : > "$preserved_tmp"
  fi

  {
    printf '%s\n%s\n%s\n' "$start_marker" "$content" "$end_marker"

    if [ -s "$preserved_tmp" ]; then
      IFS= read -r first_preserved_line < "$preserved_tmp" || true
      if [ -n "$first_preserved_line" ]; then
        printf '\n'
      fi
      cat "$preserved_tmp"
    fi
  } > "$tmp"

  if [ -f "$file" ] && cmp -s "$file" "$tmp"; then
    rm -f "$tmp" "$preserved_tmp"
    log "Managed block '$name' unchanged in $file"
    return 0
  fi

  mv "$tmp" "$file"
  rm -f "$preserved_tmp"
  log "Updated managed block '$name' in $file"
}

write_managed_file() {
  local file="$1"
  local content="$2"
  local tmp

  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  printf '%s\n' "$content" > "$tmp"

  if [ -f "$file" ] && cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    log "$file unchanged"
    return 0
  fi

  mv "$tmp" "$file"
  log "Wrote $file"
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf'
  elif command -v yum >/dev/null 2>&1; then
    printf 'yum'
  else
    return 1
  fi
}

detect_system_bashrc_path() {
  local id=''
  local id_like=''

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  case " ${id} ${id_like} " in
    *' ubuntu '*|*' debian '*)
      printf '/etc/bash.bashrc'
      ;;
    *' rhel '*|*' fedora '*|*' centos '*|*' rocky '*|*' almalinux '*)
      printf '/etc/bashrc'
      ;;
    *)
      return 1
      ;;
  esac
}

confirm_prompt() {
  local prompt="$1"
  local reply

  if [ ! -t 0 ]; then
    return 1
  fi

  printf '%s [y/N]: ' "$prompt"
  read -r reply
  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

ensure_dependencies() {
  local missing=()
  local pm
  local install_cmd=()
  local packages=()

  command -v git >/dev/null 2>&1 || missing+=(git)
  command -v vim >/dev/null 2>&1 || missing+=(vim)

  if ! { [ -r /usr/share/bash-completion/bash_completion ] || [ -r /etc/bash_completion ]; }; then
    missing+=(bash-completion)
  fi

  if [ "${#missing[@]}" -eq 0 ]; then
    return 0
  fi

  if ! pm="$(detect_package_manager)"; then
    log "Missing dependencies: ${missing[*]}"
    log "No supported package manager found (expected apt-get, dnf, or yum)."
    return 0
  fi

  case "$pm" in
    apt)
      for dep in "${missing[@]}"; do
        case "$dep" in
          git) packages+=(git) ;;
          vim) packages+=(vim) ;;
          bash-completion) packages+=(bash-completion) ;;
        esac
      done
      install_cmd=(sudo apt-get update '&&' sudo apt-get install -y "${packages[@]}")
      ;;
    dnf)
      for dep in "${missing[@]}"; do
        case "$dep" in
          git) packages+=(git) ;;
          vim) packages+=(vim-enhanced) ;;
          bash-completion) packages+=(bash-completion) ;;
        esac
      done
      install_cmd=(sudo dnf install -y "${packages[@]}")
      ;;
    yum)
      for dep in "${missing[@]}"; do
        case "$dep" in
          git) packages+=(git) ;;
          vim) packages+=(vim-enhanced) ;;
          bash-completion) packages+=(bash-completion) ;;
        esac
      done
      install_cmd=(sudo yum install -y "${packages[@]}")
      ;;
  esac

  log "Missing dependencies detected: ${missing[*]}"
  printf '\n[setup] The script can install them for you using:\n'
  printf '  %s\n\n' "${install_cmd[*]}"

  if confirm_prompt "Do you want to run that install command?"; then
    case "$pm" in
      apt)
        sudo apt-get update
        sudo apt-get install -y "${packages[@]}"
        ;;
      dnf)
        sudo dnf install -y "${packages[@]}"
        ;;
      yum)
        sudo yum install -y "${packages[@]}"
        ;;
    esac
  else
    log "Skipping dependency installation at user request."
  fi
}

# ---------------------------------------------------------------------------
# Optional ("nice to have") tools: fzf, ya, yazi, zellij
#
# These ship as release assets of the tychart/linuxstuff GitHub repo and are
# installed to ~/programs/bin so custom-patched builds (e.g. the patched
# zellij) take precedence over distro packages. Only tools missing from that
# folder are downloaded; the folder is created up front and always added to
# PATH via the managed ~/.profile block.
# ---------------------------------------------------------------------------

NICE_TO_HAVE_REPO="tychart/linuxstuff"
# Used only when the GitHub API cannot be reached to resolve the latest tag.
NICE_TO_HAVE_FALLBACK_TAG="v1.0.0"
NICE_TO_HAVE_BIN_DIR="$HOME/programs/bin"
# Names here are both the release asset names and the installed binary names.
NICE_TO_HAVE_TOOLS=(fzf ya yazi zellij)

# Cheap ELF check that needs no extra tools: real binaries start with the 4
# magic bytes 0x7f 'E' 'L' 'F'. Catches HTML error pages and truncated or
# corrupt downloads without requiring the `file` command.
is_elf_binary() {
  [ "$(head -c 4 -- "$1" 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')" = "7f454c46" ]
}

# Resolve the newest release tag via the GitHub API, with a local fallback
# tag when the API is unreachable or rate-limited.
fetch_latest_release_tag() {
  local api_url="https://api.github.com/repos/${NICE_TO_HAVE_REPO}/releases/latest"
  local tag

  if tag="$(curl -fsSL --max-time 20 "$api_url" 2>/dev/null | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)" && [ -n "$tag" ]; then
    printf '%s' "$tag"
    return 0
  fi

  # Warn on stderr so the message is not captured by callers using
  # command substitution (e.g. tag="$(fetch_latest_release_tag)").
  printf '[setup] Could not query GitHub API for the latest %s release; falling back to %s\n' "$NICE_TO_HAVE_REPO" "$NICE_TO_HAVE_FALLBACK_TAG" >&2
  printf '%s' "$NICE_TO_HAVE_FALLBACK_TAG"
}

ensure_nice_to_haves() {
  local dir="$NICE_TO_HAVE_BIN_DIR"
  local missing=()
  local tool
  local tag
  local url
  local dest
  local tmp
  local version
  local present=()

  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    log "Created $dir (nice-to-have binaries will be installed here)"
  fi

  # Remove stale partial downloads from any previously interrupted run.
  shopt -s nullglob
  rm -f -- "$dir"/.*.part.*
  shopt -u nullglob

  for tool in "${NICE_TO_HAVE_TOOLS[@]}"; do
    dest="$dir/$tool"
    if [ -s "$dest" ] && is_elf_binary "$dest"; then
      chmod +x -- "$dest" 2>/dev/null || true
      log "Nice-to-have '$tool' already installed ($dest)"
    else
      if [ -e "$dest" ]; then
        log "Nice-to-have '$tool' exists at $dest but is empty or not a valid ELF binary; re-downloading"
      fi
      missing+=("$tool")
    fi
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    log "All nice-to-have tools present in $dir"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log "curl is required to install missing nice-to-have tools (${missing[*]}); skipping"
    return 0
  fi

  log "Nice-to-have tools missing from $dir: ${missing[*]}"

  if [ "$INSTALL_NICE_TO_HAVES" != 1 ] && ! confirm_prompt "Download and install the missing nice-to-have tools?"; then
    log "Skipping nice-to-have tool installation at user request."
    log "Re-run with --install-optional to install them without prompting (also works when piped)."
    return 0
  fi

  tag="$(fetch_latest_release_tag)"
  log "Installing from release ${tag}"

  for tool in "${missing[@]}"; do
    dest="$dir/$tool"
    tmp="$(mktemp "${dir}/.${tool}.part.XXXXXX")"
    url="https://github.com/${NICE_TO_HAVE_REPO}/releases/download/${tag}/${tool}"

    if ! curl -fL --retry 3 --progress-bar -o "$tmp" "$url"; then
      rm -f -- "$tmp"
      log "Failed to download ${tool} from ${url}"
      continue
    fi

    if ! is_elf_binary "$tmp"; then
      rm -f -- "$tmp"
      log "Downloaded ${tool} is not a valid ELF binary (from ${url}); not installing"
      continue
    fi

    chmod 755 -- "$tmp"
    mv -f -- "$tmp" "$dest"
    log "Installed ${tool} -> ${dest} (release ${tag})"

    if version="$("$dest" --version 2>/dev/null | head -n 1)" && [ -n "$version" ]; then
      log "  ${tool} version: ${version}"
    else
      log "  Warning: ${tool} installed but its --version smoke test failed"
    fi
  done

  for tool in "${NICE_TO_HAVE_TOOLS[@]}"; do
    [ -x "$dir/$tool" ] && present+=("$tool")
  done
  log "Nice-to-have tools present in ${dir}: ${present[*]:-none}"
}

ensure_dependencies

ensure_nice_to_haves

SYSTEM_BASHRC_PATH=''
SYSTEM_BASHRC_BLOCK=''
if SYSTEM_BASHRC_PATH="$(detect_system_bashrc_path)"; then
  log "Will source system Bash defaults from ${SYSTEM_BASHRC_PATH} before user customizations in ~/.bashrc"
  SYSTEM_BASHRC_BLOCK=$(cat <<EOF
# Source distro-provided Bash defaults before user customizations.
if [ -r "${SYSTEM_BASHRC_PATH}" ]; then
  . "${SYSTEM_BASHRC_PATH}"
fi
EOF
)
else
  log "No known system Bash rc for this OS; leaving ~/.bashrc fully self-managed"
fi

PROFILE_CONTENT=$(cat <<'EOF'
# Login shells read ~/.profile first, then pull in ~/.bashrc for interactive extras.
# The guard avoids an infinite loop when ~/.bashrc later sources ~/.profile.
if [ -n "${BASH_VERSION:-}" ] && [ -r "$HOME/.bashrc" ] && [ -z "${__TYCHART_SOURCING_PROFILE_FROM_BASHRC:-}" ]; then
  case $- in
    *i*) . "$HOME/.bashrc" ;;
  esac
fi

# Prefer user-local bin directories when they exist. Directories are
# prepended in reverse list order, so the last entry (~/programs/bin) ends
# up first: custom-patched builds (patched zellij, etc.) win over distro
# packages. Missing directories are skipped so broken entries stay off PATH.
for dir in "$HOME/.local/bin" "$HOME/bin" "$HOME/programs/bin"; do
  if [ -d "$dir" ]; then
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) PATH="$dir:$PATH" ;;
    esac
  fi
done

# Collapse duplicate entries left over from older profiles while keeping the
# first occurrence, so the precedence above is preserved.
__tychart_dedupe_path() {
  local result='' entry
  local IFS=':'
  for entry in $PATH; do
    [ -z "$entry" ] && continue
    case ":$result:" in
      *":$entry:"*) ;;
      *) result="${result:+$result:}$entry" ;;
    esac
  done
  printf '%s' "$result"
}
PATH="$(__tychart_dedupe_path)"
unset -f __tychart_dedupe_path
export PATH

# Editor defaults live here so other tools can simply inherit them.
export EDITOR="__DEFAULT_EDITOR__"
export VISUAL="__DEFAULT_EDITOR__"
export SYSTEMD_EDITOR="__DEFAULT_EDITOR__"
export INPUTRC="${INPUTRC:-$HOME/.inputrc}"
EOF
)
PROFILE_CONTENT="${PROFILE_CONTENT//__DEFAULT_EDITOR__/$DEFAULT_EDITOR}"

BASH_PROFILE_CONTENT=$(cat <<'EOF'
# Ensure Bash login shells also load ~/.profile.
if [ -r "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
EOF
)

BASHRC_CONTENT=$(cat <<'EOF'
# Editor defaults should exist before any early return so child CLI tools inherit them.
export EDITOR="${EDITOR:-__DEFAULT_EDITOR__}"
export VISUAL="${VISUAL:-$EDITOR}"

# Stop here for non-interactive shells.
case $- in
  *i*) ;;
  *) return ;;
esac

# ~/.profile sources this file back, both in its managed block and in
# preserved user content. If we are already inside such a source, stop:
# everything below was already defined by the outer pass. Without this the
# two files would source each other forever and every shell would hang.
if [ -n "${__TYCHART_SOURCING_PROFILE_FROM_BASHRC:-}" ]; then
  return
fi

__SYSTEM_BASHRC_BLOCK__
# Many terminals start Bash as a non-login shell, which skips ~/.profile.
# Source it here so PATH and editor defaults are consistent in every shell.
# The guard prevents recursion because ~/.profile sources this file back.
if [ -r "$HOME/.profile" ]; then
  __TYCHART_SOURCING_PROFILE_FROM_BASHRC=1
  . "$HOME/.profile"
  unset __TYCHART_SOURCING_PROFILE_FROM_BASHRC
fi

export INPUTRC="${INPUTRC:-$HOME/.inputrc}"

# History behavior.
HISTCONTROL=ignoredups:erasedups
HISTSIZE=50000
HISTFILESIZE=100000
HISTTIMEFORMAT="%d/%m/%y %T "
shopt -s histappend
shopt -s checkwinsize

__tychart_history_sync() {
  # Append this shell's new history lines, then pull in lines from other shells.
  history -a
  history -n
}

case ";${PROMPT_COMMAND:-};" in
  *";__tychart_history_sync;"*) ;;
  '') PROMPT_COMMAND="__tychart_history_sync" ;;
  *)  PROMPT_COMMAND="__tychart_history_sync;${PROMPT_COMMAND}" ;;
esac
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

# fzf integration (Ctrl-T/Ctrl-R/Alt-C keybindings and completion). Guarded so
# shells stay quiet when fzf is not installed yet (it is a nice-to-have).
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --bash)"
fi

# Aliases.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias c='clear'
alias k='kubectl'
alias ll='ls -lah --color=auto --group-directories-first'
alias myip='hostname -I 2>/dev/null | awk "{print \$1}"'
alias src='source "$HOME/.profile"'
alias venv='source .venv/bin/activate'
alias ver='cat /etc/*-release'
alias vim='vim -u "$HOME/.vimrc"'
alias whoson='last -w | tac'
alias details='get_machine_info'
alias z='zellij attach -c main'

# Functions.
mmkdir() {
  if [ $# -ne 1 ]; then
    printf 'usage: mmkdir <dir>\n' >&2
    return 1
  fi

  command mkdir -p -- "$1" && cd -- "$1"
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
  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
  command rm -f -- "$tmp"
}

# Prompt.
# NOTE: You mentioned you may replace this later with Starship.
# This section is intentionally isolated so it is easy to remove/swap.
__tychart_set_prompt() {
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
__tychart_set_prompt
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
EOF
)
BASHRC_CONTENT="${BASHRC_CONTENT//__DEFAULT_EDITOR__/$DEFAULT_EDITOR}"
BASHRC_CONTENT="${BASHRC_CONTENT/__SYSTEM_BASHRC_BLOCK__/$SYSTEM_BASHRC_BLOCK}"

VIMRC_CONTENT=$(cat <<'EOF'
set nocompatible

syntax on
if has('autocmd')
  filetype plugin indent on
endif

" Basic editing and search defaults.
set number
set showcmd
set ruler
set wildmenu

if exists('&wildmode')
  set wildmode=longest:full,full
endif

set lazyredraw
set showmatch
set incsearch
set hlsearch
set ignorecase
set smartcase
set backspace=indent,eol,start
set autoindent
set expandtab
set tabstop=2
set shiftwidth=2

if exists('&softtabstop')
  set softtabstop=2
endif

set mouse=a
set hidden
set splitbelow
set splitright
set scrolloff=3
set history=1000
set noerrorbells
set visualbell
set laststatus=2
set cursorline

" Terminal cursor shapes: blinking block in Normal, blinking bar in Insert,
" blinking underline in Replace. Terminal support may vary.
let &t_SI = "\<Esc>[5 q"
let &t_SR = "\<Esc>[3 q"
let &t_EI = "\<Esc>[1 q"

" Save undo history on disk so undo still works after reopening a file.
if has('persistent_undo')
  set undodir=~/.vim/undodir
  set undofile
  set undolevels=1000
  set undoreload=10000
endif

" F6 toggles the highlighted current line. Double-Esc clears search highlighting.
nnoremap <silent> <F6> :set cursorline!<CR>
inoremap <silent> <F6> <C-o>:set cursorline!<CR>
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

" Use space as the leader key for custom shortcuts.
if !exists('mapleader')
  let mapleader = ' '
endif

" OSC 52 lets Vim copy over SSH/remote terminals without needing a local clipboard provider.
" <leader>c copies the current motion or visual selection.
nmap <leader>c <Plug>OSCYankOperator
nmap <leader>cc <leader>c_
vmap <leader>c <Plug>OSCYankVisual

" Reopen files at the last cursor position from the previous edit session.
augroup tychart_vim_startup
  autocmd!
  autocmd BufReadPost *
    \ if line("'\"") > 0 && line("'\"") <= line('$') && &filetype !~# 'commit' |
    \   execute 'normal! g`"' |
    \ endif
augroup END
EOF
)

INPUTRC_CONTENT=$(cat <<'EOF'
set input-meta on
set output-meta on
set bell-style none

# Let custom Readline bindings win instead of auto-reserving tty keys like Ctrl+W.
set bind-tty-special-chars off

set completion-ignore-case on
set show-all-if-ambiguous on
set mark-symlinked-directories on

$if mode=emacs
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[3~": delete-char
"\e[2~": quoted-insert

"\e[1;5C": forward-word
"\e[1;5D": backward-word
"\e[5C": forward-word
"\e[5D": backward-word
"\e\e[C": forward-word
"\e\e[D": backward-word

$if term=rxvt
"\e[7~": beginning-of-line
"\e[8~": end-of-line
"\eOc": forward-word
"\eOd": backward-word
$endif
$endif
EOF
)

# Install a small custom Vim plugin so copy works reliably in SSH, tmux, and other remote terminals.
# It uses OSC 52 escape sequences instead of depending on xclip/pbcopy or a local GUI clipboard.
OSCYANK_PLUGIN_CONTENT=$(cat <<'EOF'
" -------------------- INIT --------------------------------
if exists('g:loaded_oscyank')
  finish
endif
let g:loaded_oscyank = 1

" -------------------- VARIABLES ---------------------------
let s:commands = {
  \ 'operator': {'block': '`[\<C-v>`]y', 'char': '`[v`]y', 'line': "'[V']y"},
  \ 'visual': {'': 'gvy', 'V': 'gvy', 'v': 'gvy', '\x16': 'gvy'}}
let s:b64_table = [
  \ 'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
  \ 'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
  \ 'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
  \ 'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/']

" -------------------- OPTIONS ---------------------------
function s:options_max_length()
  return get(g:, 'oscyank_max_length', 0)
endfunction

function s:options_silent()
  return get(g:, 'oscyank_silent', 0)
endfunction

function s:options_trim()
  return get(g:, 'oscyank_trim', 0)
endfunction

function s:options_osc52()
  return get(g:, 'oscyank_osc52', "\x1b]52;c;%s\x07")
endfunction

" -------------------- UTILS -------------------------------
function s:echo(text, hl)
  echohl a:hl
  echo printf('[oscyank] %s', a:text)
  echohl None
endfunction

function s:encode_b64(str, size)
  let bytes = map(range(len(a:str)), 'char2nr(a:str[v:val])')
  let b64 = []

  for i in range(0, len(bytes) - 1, 3)
    let n = bytes[i] * 0x10000
          \ + get(bytes, i + 1, 0) * 0x100
          \ + get(bytes, i + 2, 0)
    call add(b64, s:b64_table[n / 0x40000])
    call add(b64, s:b64_table[n / 0x1000 % 0x40])
    call add(b64, s:b64_table[n / 0x40 % 0x40])
    call add(b64, s:b64_table[n % 0x40])
  endfor

  if len(bytes) % 3 == 1
    let b64[-1] = '='
    let b64[-2] = '='
  endif

  if len(bytes) % 3 == 2
    let b64[-1] = '='
  endif

  let b64 = join(b64, '')
  if a:size <= 0
    return b64
  endif

  let chunked = ''
  while strlen(b64) > 0
    let chunked .= strpart(b64, 0, a:size) . "\n"
    let b64 = strpart(b64, a:size)
  endwhile

  return chunked
endfunction

function s:get_text(mode, type)
  let l:clipboard = &clipboard
  let l:selection = &selection
  let l:register = getreg('"')
  let l:visual_marks = [getpos("'<"), getpos("'>")]

  set clipboard=
  set selection=inclusive
  silent execute printf('keepjumps normal! %s', s:commands[a:mode][a:type])
  let l:text = getreg('"')

  let &clipboard = l:clipboard
  let &selection = l:selection
  call setreg('"', l:register)
  call setpos("'<", l:visual_marks[0])
  call setpos("'>", l:visual_marks[1])

  return l:text
endfunction

function s:trim_text(text)
  let l:text = a:text
  let l:indent = matchstrpos(l:text, '^\s\+')

  if l:indent[1] >= 0
    let l:pattern = printf('\n%s', repeat('\s', l:indent[2] - l:indent[1]))
    let l:text = substitute(l:text, l:pattern, '\n', 'g')
  endif

  return trim(l:text)
endfunction

function s:write(osc52)
  if filewritable('/dev/fd/2') == 1
    let l:success = writefile([a:osc52], '/dev/fd/2', 'b') == 0
  elseif has('nvim')
    let l:success = chansend(v:stderr, a:osc52) > 0
  else
    exec('silent! !echo ' . shellescape(a:osc52))
    redraw!
    let l:success = 1
  endif
  return l:success
endfunction

" -------------------- PUBLIC ------------------------------
function! OSCYank(text) abort
  let l:text = s:options_trim() ? s:trim_text(a:text) : a:text

  if s:options_max_length() > 0 && strlen(l:text) > s:options_max_length()
    call s:echo(printf('Selection is too big: length is %d, limit is %d', strlen(l:text), s:options_max_length()), 'WarningMsg')
    return
  endif

  let l:text_b64 = s:encode_b64(l:text, 0)
  let l:osc52 = printf(s:options_osc52(), l:text_b64)
  let l:success = s:write(l:osc52)

  if !l:success
    call s:echo('Failed to copy selection', 'ErrorMsg')
  elseif !s:options_silent()
    call s:echo(printf('%d characters copied', strlen(l:text)), 'Normal')
  endif

  return l:success
endfunction

function! OSCYankOperatorCallback(type) abort
  let l:text = s:get_text('operator', a:type)
  return OSCYank(l:text)
endfunction

function! OSCYankOperator() abort
  set operatorfunc=OSCYankOperatorCallback
  return 'g@'
endfunction

function! OSCYankVisual() abort
  let l:text = s:get_text('visual', visualmode())
  return OSCYank(l:text)
endfunction

function! OSCYankRegister(register) abort
  let l:text = getreg(a:register)
  return OSCYank(l:text)
endfunction

" -------------------- COMMANDS ----------------------------
command! -nargs=1 OSCYank call OSCYank('<args>')
command! -range OSCYankVisual call OSCYankVisual()
command! -register OSCYankRegister call OSCYankRegister('<reg>')

nnoremap <expr> <Plug>OSCYankOperator OSCYankOperator()
vnoremap <Plug>OSCYankVisual :OSCYankVisual<CR>
EOF
)

log "Applying managed configuration blocks"
mkdir -p "$VIM_PLUGIN_DIR" "$VIM_UNDO_DIR"

upsert_managed_block "$PROFILE_FILE" "profile" "$PROFILE_CONTENT"
upsert_managed_block "$BASH_PROFILE_FILE" "bash_profile" "$BASH_PROFILE_CONTENT"
upsert_managed_block "$BASHRC_FILE" "bashrc" "$BASHRC_CONTENT"
upsert_managed_block "$VIMRC_FILE" "vimrc" "$VIMRC_CONTENT" '"'
upsert_managed_block "$INPUTRC_FILE" "inputrc" "$INPUTRC_CONTENT"
write_managed_file "$OSCYANK_FILE" "$OSCYANK_PLUGIN_CONTENT"

if command -v git >/dev/null 2>&1; then
  log "Updating Git defaults"
  # Remove a hardcoded Git editor so Git inherits $EDITOR from ~/.profile.
  git config --global --unset-all core.editor >/dev/null 2>&1 || true
  git config --global init.defaultBranch main
  git config --global alias.lg "log --graph --all --decorate --pretty=format:'%C(blue)%h%Creset%C(yellow)%d%Creset %s %C(blue)%an%Creset %C(green)(%ar)%Creset'"
fi

log "Done. Open a new shell (or run: source ~/.profile) to pick up PATH changes."
log "If Vim is already open, restart it to load updated config/plugin."
