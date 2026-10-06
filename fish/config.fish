# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

# Preserve inherited values when they already exist.
if not set -q EDITOR
    set -gx EDITOR __DEFAULT_EDITOR__
end

if not set -q VISUAL
    set -gx VISUAL $EDITOR
end

if not set -q SYSTEMD_EDITOR
    set -gx SYSTEMD_EDITOR $EDITOR
end

# Prefer user-local executable directories. Use fish_add_path when available,
# but keep a portable fallback for older Fish builds.
if functions -q fish_add_path
    fish_add_path --path --move "$HOME/bin"
    fish_add_path --path --move "$HOME/.local/bin"
else
    for dir in "$HOME/bin" "$HOME/.local/bin"
        if test -d "$dir"
            if not contains -- "$dir" $PATH
                set -gx PATH "$dir" $PATH
            end
        end
    end
end

# Bun: only configure it when installed, so shells that do not use Bun pay
# almost no startup cost.
if test -d "$HOME/.bun"
    set -gx BUN_INSTALL "$HOME/.bun"

    if test -d "$BUN_INSTALL/bin"
        if functions -q fish_add_path
            fish_add_path --path --move "$BUN_INSTALL/bin"
        else if not contains -- "$BUN_INSTALL/bin" $PATH
            set -gx PATH "$BUN_INSTALL/bin" $PATH
        end
    end
end

# Everything below is only needed in an interactive shell.
status is-interactive; or return

# ---------------------------------------------------------------------------
# fzf
# ---------------------------------------------------------------------------

if command -q fzf
    fzf --fish | source
end

# ---------------------------------------------------------------------------
# Tool integrations / aliases
# ---------------------------------------------------------------------------

if command -q eza
    abbr --add ll 'eza -lag --git --icons --group-directories-first'
else
    # Portable fallback for systems whose ls does not support GNU color/grouping flags.
    abbr --add ll 'ls -lah'
end

if command -q bat
    abbr --add b 'bat'
    if command -q man
        set -gx MANPAGER 'bat -plman'
    end
end

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------

abbr --add .. 'cd ..'
abbr --add ... 'cd ../..'
abbr --add .... 'cd ../../..'
abbr --add ..... 'cd ../../../..'

abbr --add c clear
abbr --add k kubectl
abbr --add ver 'cat /etc/*-release'
abbr --add whoson 'last -w | tac'
abbr --add details get_machine_info

function setupconfig --description 'Run the remote setupconfig bootstrap'
    command curl -fsSL https://raw.githubusercontent.com/tychart/linuxstuff/main/setupconfig/setupconfig.sh | command bash -s -- $argv
end

# Launch a throwaway, ephemeral Zellij instance"
if command -q zellij
    abbr --add z "zellij options --session-serialization false"
end


# Reload Fish configuration.
abbr --add src 'source "$__fish_config_dir/config.fish"'

# Python venvs provide a Fish-specific activation script.
abbr --add venv 'source .venv/bin/activate.fish'

# ---------------------------------------------------------------------------
# Small helper functions
# ---------------------------------------------------------------------------

function myip --description 'Print primary IP address'
    hostname -I 2>/dev/null | awk '{print $1}'
end

function mmkdir --description 'Create a directory and enter it'
    if test (count $argv) -ne 1
        printf 'usage: mmkdir <dir>\n' >&2
        return 1
    end

    command mkdir -p "$argv[1]"
    and builtin cd -- "$argv[1]"
end

function get_machine_info --description 'Print host, IP, and OS summary'
    set -l distro unknown
    set -l version_id unknown
    set -l os
    set -l ver
    set -l name (hostname)
    set -l ip

    if test -r /etc/os-release
        set -l id_line (string match -r '^ID=.*' </etc/os-release)
        set -l version_line (string match -r '^VERSION_ID=.*' </etc/os-release)

        if test -n "$id_line"
            set distro (string replace 'ID=' '' "$id_line" | string trim -c '"')
        end

        if test -n "$version_line"
            set version_id (string replace 'VERSION_ID=' '' "$version_line" | string trim -c '"')
        end
    end

    if test "$distro" = ubuntu
        set os ubu
    else
        set os "$distro"
    end

    set ver "$os$version_id"
    set ip (hostname -I 2>/dev/null | awk '{print $1}')
    if test -z "$ip"
        set ip (hostname -i 2>/dev/null)
    end

    printf '******************************\n'
    printf 'Hostname: %s\n' "$name"
    printf 'IP address: %s\n' "$ip"
    printf 'Operating system: %s\n' "$ver"
    printf '******************************\n'
end

function get_os_short --description 'Print short OS identifier'
    set -l os_id unknown
    set -l os_version

    if test -r /etc/os-release
        set -l id_line (string match -r '^ID=.*' </etc/os-release)
        set -l version_line (string match -r '^VERSION_ID=.*' </etc/os-release)

        if test -n "$id_line"
            set os_id (string replace 'ID=' '' "$id_line" | string trim -c '"')
        end

        if test -n "$version_line"
            set os_version (string replace 'VERSION_ID=' '' "$version_line" | string trim -c '"')
        end
    end

    if test "$os_id" = ubuntu
        set os_id ubu
    end

    printf '%s%s' "$os_id" "$os_version"
end

function ssu --description 'Open root Fish shell using current user config and history'
    set -l fish_path (command -s fish)

    if test -z "$fish_path"
        printf 'ssu: fish not found in PATH\n' >&2
        return 127
    end

    set -l root_env "HOME=$HOME"
    set -q XDG_CONFIG_HOME; and set -a root_env "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
    set -q XDG_DATA_HOME; and set -a root_env "XDG_DATA_HOME=$XDG_DATA_HOME"

    command sudo env $root_env "$fish_path" -i
end

function y --description 'Open yazi and cd to the directory it leaves behind'
    if not command -q yazi
        printf 'y: yazi is not installed; install it with your system package manager or this setup script on Linux x64.\n' >&2
        return 127
    end

    set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
    command yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and test "$cwd" != "$PWD"; and test -d "$cwd"
        builtin cd -- "$cwd"
    end
    command rm -f "$tmp"
end

# ---------------------------------------------------------------------------
# Key bindings
# ---------------------------------------------------------------------------
# Delete backward to the nearest non-alphanumeric character. This makes
# Ctrl+Backspace safer for paths by stopping at punctuation such as /, ., -,
# and _ instead of deleting an entire path component chain at once.

function __safe_backward_kill_word --description 'Safely delete backward to punctuation/whitespace boundary'
    set -l line (commandline -b)
    set -l point (commandline -C)

    if test "$point" -le 0
        return
    end

    # commandline -C is zero-based. Start by including the character directly
    # before the cursor, then walk left while the preceding chars are alnum.
    set -l pos (math $point - 1)

    while test "$pos" -gt 0
        # Fish string indexes are one-based. This is the char before $pos.
        set -l char (string sub -s $pos -l 1 -- "$line")

        if not string match -rq '^[[:alnum:]]$' -- "$char"
            break
        end

        set pos (math $pos - 1)
    end

    set -l before ''
    set -l after ''

    if test "$pos" -gt 0
        set before (string sub -s 1 -l $pos -- "$line")
    end

    if test "$point" -lt (string length -- "$line")
        set after (string sub -s (math $point + 1) -- "$line")
    end

    commandline -r -- "$before$after"
    commandline -C $pos
    commandline -f repaint
end

# Ctrl+Backspace is terminal-dependent:
# - Windows Terminal sends ctrl-w
# - some terminals send ctrl-h
# - Ghostty sends ctrl-backspace
bind ctrl-w __safe_backward_kill_word
bind ctrl-h __safe_backward_kill_word
bind ctrl-backspace __safe_backward_kill_word

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------

function fish_prompt
    set -l user_color green
    set -l prompt_symbol '>'

    if fish_is_root_user
        set user_color magenta
        set prompt_symbol '#'
    end

    set_color --bold $user_color
    printf '%s' "$USER"

    set_color normal
    printf '@'

    set_color red
    printf '%s' (prompt_hostname)

    set_color --bold cyan
    printf '(%s) ' (get_os_short)

    set_color --bold blue
    printf '%s' (prompt_pwd)

    set_color normal
    printf ' %s ' "$prompt_symbol"
end
