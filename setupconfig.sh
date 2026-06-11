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
#   - Creates timestamped backups before changing files
#   - Installs the OSC 52 Vim plugin as ~/.vim/plugin/oscyank.vim
#
# Usage:
#   chmod +x setupconfig.sh
#   ./setupconfig.sh
#   ./setupconfig.sh --cleanup-backups
#
#   or
#   curl -fsSL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash

set -euo pipefail

SCRIPT_TAG="tychart-setup"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

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
EOF
}

cleanup_backups() {
  local count=0
  local file

  shopt -s nullglob

  for file in \
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
    log "No ${SCRIPT_TAG} backup files found."
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

  [ -e "$file" ] || return 0

  backup="${file}.bak.${SCRIPT_TAG}.${TIMESTAMP}"
  if [ ! -e "$backup" ]; then
    cp -a -- "$file" "$backup"
    log "Backed up $file -> $backup"
  fi
}

upsert_managed_block() {
  local file="$1"
  local name="$2"
  local content="$3"
  local marker_prefix="${4:-#}"
  local start_marker="${marker_prefix} >>> ${SCRIPT_TAG}:${name} >>>"
  local end_marker="${marker_prefix} <<< ${SCRIPT_TAG}:${name} <<<"
  local legacy_hash_start="# >>> ${SCRIPT_TAG}:${name} >>>"
  local legacy_hash_end="# <<< ${SCRIPT_TAG}:${name} <<<"
  local legacy_vim_start="\" >>> ${SCRIPT_TAG}:${name} >>>"
  local legacy_vim_end="\" <<< ${SCRIPT_TAG}:${name} <<<"
  local tmp

  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"

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
      ' "$file" > "$tmp"
  else
    : > "$tmp"
  fi

  if [ -s "$tmp" ]; then
    awk '
      { lines[NR] = $0 }
      END {
        last = NR
        while (last > 0 && lines[last] == "") {
          last--
        }
        for (i = 1; i <= last; i++) {
          print lines[i]
        }
      }
    ' "$tmp" > "${tmp}.trim"
    mv "${tmp}.trim" "$tmp"
    printf '\n' >> "$tmp"
  fi

  printf '%s\n%s\n%s\n' "$start_marker" "$content" "$end_marker" >> "$tmp"

  if [ -f "$file" ] && cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    log "Managed block '$name' unchanged in $file"
    return 0
  fi

  backup_file "$file"
  mv "$tmp" "$file"
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

  backup_file "$file"
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

ensure_dependencies

PROFILE_CONTENT=$(cat <<'EOF'
# Load interactive Bash settings for login shells.
if [ -n "${BASH_VERSION:-}" ] && [ -r "$HOME/.bashrc" ]; then
  case $- in
    *i*) . "$HOME/.bashrc" ;;
  esac
fi

# Prefer user-local bin directories when they exist.
for dir in "$HOME/.local/bin" "$HOME/bin"; do
  if [ -d "$dir" ]; then
    case ":$PATH:" in
      *":$dir:"*) ;;
      *) PATH="$dir:$PATH" ;;
    esac
  fi
done
export PATH

# Editor defaults.
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-vim}"
export SYSTEMD_EDITOR="${SYSTEMD_EDITOR:-vim}"
export INPUTRC="${INPUTRC:-$HOME/.inputrc}"
EOF
)

BASH_PROFILE_CONTENT=$(cat <<'EOF'
# Ensure Bash login shells also load ~/.profile.
if [ -r "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
EOF
)

BASHRC_CONTENT=$(cat <<'EOF'
# Stop here for non-interactive shells.
case $- in
  *i*) ;;
  *) return ;;
esac

# Editor defaults for interactive shells as well.
export EDITOR="${EDITOR:-vim}"
export VISUAL="${VISUAL:-vim}"
export SYSTEMD_EDITOR="${SYSTEMD_EDITOR:-vim}"
export INPUTRC="${INPUTRC:-$HOME/.inputrc}"

# History behavior.
HISTCONTROL=ignoredups:erasedups
HISTSIZE=50000
HISTFILESIZE=100000
HISTTIMEFORMAT="%d/%m/%y %T "
shopt -s histappend
shopt -s checkwinsize

__tychart_history_sync() {
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

# Aliases.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias c='clear'
alias k='kubectl'
alias la='LC_COLLATE=C ls -alF --group-directories-first'
alias ll='ls -lah --color=auto --group-directories-first'
alias lt='ls -ltr --color=auto --group-directories-first'
alias lwd='ls -ld1 --color=auto --group-directories-first "$PWD"/*'
alias myip='hostname -I 2>/dev/null | awk "{print \$1}"'
alias src='source "$HOME/.profile"'
alias venv='source .venv/bin/activate'
alias ver='cat /etc/*-release'
alias vim='vim -u "$HOME/.vimrc"'
alias whoson='last -w | tac'
alias details='get_machine_info'

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

bind -x '"\C-h": my_custom_backwards_kill_word'
EOF
)

VIMRC_CONTENT=$(cat <<'EOF'
set nocompatible

syntax on
if has('autocmd')
  filetype plugin indent on
endif

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

if has('persistent_undo')
  set undodir=~/.vim/undodir
  set undofile
  set undolevels=1000
  set undoreload=10000
endif

nnoremap <silent> <F6> :set cursorline!<CR>
inoremap <silent> <F6> <C-o>:set cursorline!<CR>
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

if !exists('mapleader')
  let mapleader = ' '
endif

" Explicit OSC 52 copy to system clipboard.
nmap <leader>c <Plug>OSCYankOperator
nmap <leader>cc <leader>c_
vmap <leader>c <Plug>OSCYankVisual

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
  git config --global core.editor vim
  git config --global init.defaultBranch main
  git config --global alias.lg "log --graph --all --decorate --pretty=format:'%C(blue)%h%Creset%C(yellow)%d%Creset %s %C(blue)%an%Creset %C(green)(%ar)%Creset'"
fi

log "Done. Open a new shell or run: source ~/.profile"
log "If Vim is already open, restart it to load updated config/plugin."
