#!/bin/bash

# What does this do?
#    The main purpose of this script is to make the bash terminal and
#    vim look better and have custom common aliases.
#    This script will copy its contents into 4 files: .profile, .bashrc, .vimrc, and .inputrc

# How to use this script:
#
#    Manual:
#        Copy the contents into a new file -> vim setupconfig.sh
#        Allow execution                   -> chmod +x setupconfig.sh
#        Run Script                        -> ./setupconfig.sh
#
#    Automatic:
#        curl -sL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash

# Detect distro for compatibility
DISTRO_ID=""
if [ -f /etc/os-release ]; then
    DISTRO_ID=$(. /etc/os-release && echo "$ID")
fi

# Determine the correct alternatives command for this distro
# Debian/Ubuntu: update-alternatives
# RHEL/Fedora/CentOS: /usr/sbin/alternatives or alternatives
ALTERNATIVES_CMD=""
if command -v update-alternatives &>/dev/null; then
    ALTERNATIVES_CMD="update-alternatives"
elif [ -x /usr/sbin/alternatives ]; then
    ALTERNATIVES_CMD="/usr/sbin/alternatives"
elif command -v alternatives &>/dev/null; then
    ALTERNATIVES_CMD="alternatives"
fi

# Define the contents of each file
read -r -d '' PROFILE_CONTENT <<'EOF'
# ~/.profile: executed by the command interpreter for login shells.
# This file is not read by bash(1), if ~/.bash_profile or ~/.bash_login
# exists.

# if running bash
if [ -n "$BASH_VERSION" ]; then
    if [ -f "$HOME/.bashrc" ]; then
        . "$HOME/.bashrc"
    fi
fi

# set PATH so it includes user's private bin if it exists
if [ -d "$HOME/.local/bin" ] ; then
    PATH="$HOME/.local/bin:$PATH"
fi

##### Load in /etc/profile.d configurations for root
if (( $UID == 0 )); then
  for i in /etc/profile.d/*.sh /etc/profile.d/sh.local ; do
    if [ -r "$i" ] && ! [[ $i == *"pwage.sh" ]]; then
      if [ "${-#*i}" != "$-" ]; then
        . "$i"
      else
        . "$i" > /dev/null
      fi
    fi
  done
fi
EOF



read -r -d '' BASHRC_CONTENT <<'EOF'
# ~/.bashrc: executed by bash(1) for non-login shells.

# If not running interactively, don't do anything
case $- in
    *i*) ;;
      *) return;;
esac

##### User specific aliases

alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias lt='ls -ltr --color=auto --group-directories-first'
alias la='LC_COLLATE=C ls -alF --group-directories-first'
alias ll='ls -lah --color=auto --group-directories-first'
alias lwd='ls -ld1 --color=auto --group-directories-first "$PWD"/*'
alias ver='cat /etc/*-release'
alias whoson='last -w|tac'
alias myip='hostname -i'
alias details=get_machine_info
alias c='clear'
alias src='source $HOME/.profile'
alias vim='vim -u $HOME/.vimrc'
alias k='kubectl'
alias venv='source .venv/bin/activate'

##### Set correct TERM variable. Allows vim to use alternate screen and correct color scheme
export TERM=xterm-256color

export SYSTEMD_EDITOR=vim

export INPUTRC="$HOME/.inputrc"

# Make bash append every command immediately to the history file
PROMPT_COMMAND="history -a; history -n; $PROMPT_COMMAND"

HISTTIMEFORMAT="%d/%m/%y %T "
bind 'set bell-style none'

# Enable bash completion framework
if [ -f /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
  . /etc/bash_completion
fi

# Load git completion
if [ -f /usr/share/bash-completion/completions/git ]; then
  . /usr/share/bash-completion/completions/git
elif [ -f /etc/bash_completion.d/git ]; then
  . /etc/bash_completion.d/git
fi

##### Modified mkdir command that cds into the new directory
function mmkdir() {
  command mkdir -p $1; cd $1
}

##### Function to get the info for the machine currently being used
function get_machine_info() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    distro="$ID"
    version_id="$VERSION_ID"
  else
    distro="unknown"
    version_id="unknown"
  fi

  # Build short OS identifier
  if [[ "$distro" == "ubuntu" ]]; then
    os="ubu"
  else
    os="${distro}"
  fi

  ver="$os${version_id}"
  name=`hostname`
  ip=`hostname -i`

  printf "******************************\n"
  echo Hostname: $name
  echo IP address: $ip
  echo Operating system: $ver
  printf "******************************\n"
}

get_os_short() {
  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    printf "%s%s" "$ID" "$VERSION_ID"
  else
    printf "unknown"
  fi
}

function ssu() {
  # Preserve HOME in sudo, export HOME so bash picks up YOUR rcfile,
  # launch bash as an interactive shell reading only your ~/.bashrc
  sudo --preserve-env=HOME \
       env HOME="$HOME" \
       bash --rcfile "$HOME/.bashrc" -i
}

shopt -s checkwinsize

##### Sets specific command prompts for user vs root
if [ "$TERM" == "xterm-color" ]; then
  export PS1="\u@\h \w $"
else
  if (( $EUID != 0 )); then
    export PS1="\[\e[1;32m\]\u\[\e[0m\]@\[\e[0;31m\]\h\[\e[1;36m\]($(get_os_short)) \[\e[1;34m\]\w \[\e[0m\]$ \[\e[0m\]"
  else
    export PS1="\[\e[1;35m\]\u\[\e[0m\]@\[\e[0:31m\]\h\[\e[1;36m\]($(get_os_short)) \[\e[01;34m\]\w\[\e[0m\] # "
  fi
fi

##### Custom ctrl+backspace kill word behavior
my_custom_backwards_kill_word() {
    local line=$READLINE_LINE
    local pos=$READLINE_POINT

    local boundary_chars="[^[:alnum:]]"

    if [[ $READLINE_POINT != 0 ]]; then
      (( pos-- ))

      while (( pos > 0 )); do
          local char=${line:pos-1:1}
          if [[ $char =~ $boundary_chars ]]; then
              break
          fi
          (( pos-- ))
      done

      READLINE_LINE="${line:0:pos}${line:READLINE_POINT}"
      READLINE_POINT=$pos
    fi
}

bind -x '"\C-h": my_custom_backwards_kill_word'
EOF



read -r -d '' VIMRC_CONTENT <<'EOF'
syntax on

set tabstop=2
set shiftwidth=2
set autoindent
set nocp
set number
set expandtab
set showcmd
set wildmenu
set lazyredraw
set showmatch
set incsearch
set hlsearch
set backspace=indent,eol,start
set ruler
set undodir=~/.vim/undodir
set undofile
set undolevels=1000
set undoreload=10000
set noerrorbells
set vb t_vb=
set cursorline
map <F6> :call ToggleCurline()<CR>
imap <F6> :call ToggleCurline()<CR>

set mouse=a

map <ScrollWheelUp> <Up>
map <ScrollWheelDown> <Down>

fu! ToggleCurline ()
  if &cursorline
    set nocursorline
  else
    set cursorline
  endif
endfunction

augroup vimStartup
  au!
  autocmd BufReadPost *
    \ if line("'\"") >= 1 && line("'\"") <= line("$") && &ft !~# 'commit'
    \ |   exe "normal! g`\""
    \ | endif
augroup END
EOF



read -r -d '' INPUTRC_CONTENT <<'EOF'
# /etc/inputrc - global inputrc for libreadline

# Be 8 bit clean.
set input-meta on
set output-meta on

# do not bell on tab-completion
set bell-style none

# some defaults / modifications for the emacs mode
$if mode=emacs

# allow the use of the Home/End keys
"\e[1~": beginning-of-line
"\e[4~": end-of-line

# allow the use of the Delete/Insert keys
"\e[3~": delete-char
"\e[2~": quoted-insert

# mappings for Ctrl-left-arrow and Ctrl-right-arrow for word moving
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


# Update the alternatives to set vim as the default editor (distro-safe)
if [[ -n "$ALTERNATIVES_CMD" ]]; then
    echo "Setting vim as default editor via $ALTERNATIVES_CMD..."
    $ALTERNATIVES_CMD --set editor /usr/bin/vim.basic 2>/dev/null || \
    $ALTERNATIVES_CMD --set editor /usr/bin/vim 2>/dev/null || \
    echo "Warning: Could not set default editor via alternatives (this is OK on some distros)"
else
    echo "Note: No alternatives command found; EDITOR/VISUAL set in bashrc only."
fi



# Define the paths for each file
profile_file="$HOME/.profile"
bashrc_file="$HOME/.bashrc"
vimrc_file="$HOME/.vimrc"
inputrc_file="$HOME/.inputrc"

# Copy the contents to the respective files and capture errors
echo "$PROFILE_CONTENT" > "$profile_file" 2> /tmp/profile_error
echo "$BASHRC_CONTENT" > "$bashrc_file" 2> /tmp/bashrc_error
echo "$VIMRC_CONTENT" > "$vimrc_file" 2> /tmp/vimrc_error
echo "$INPUTRC_CONTENT" > "$inputrc_file" 2> /tmp/inputrc_error

# Check if any error file is not empty
if [[ -s /tmp/profile_error || -s /tmp/bashrc_error || -s /tmp/vimrc_error || -s /tmp/inputrc_error ]]; then
    echo "Error: Files not copied successfully!"
    echo "Profile error:"; cat /tmp/profile_error
    echo "Bashrc error:"; cat /tmp/bashrc_error
    echo "Vimrc error:"; cat /tmp/vimrc_error
    echo "Inputrc error:"; cat /tmp/inputrc_error
    rm -f /tmp/profile_error /tmp/bashrc_error /tmp/vimrc_error /tmp/inputrc_error
else
    echo "Files copied successfully!"

    # Add custom git log alias
    git config --global alias.lg "log --graph --all --decorate --pretty=format:'%C(blue)%h%Creset%C(yellow)%d%Creset %s %C(blue)%an%Creset %C(green)(%ar)%Creset'"

    # Set git default primary branch to main
    git config --global init.defaultBranch main

    echo "Reloading .profile"
    source ~/.profile

    echo "Removing this setup script"
    rm "$0"
fi
