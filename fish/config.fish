# >>> tychart-setup:fish >>>

# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

# Preserve inherited values when they already exist.
if not set -q EDITOR
    set -gx EDITOR vim
end

if not set -q VISUAL
    set -gx VISUAL $EDITOR
end

# Your locally deployed binaries.
# --path means modify PATH itself instead of Fish's persistent universal
# fish_user_paths variable. This makes the config reproducible from files
# rather than relying on hidden per-machine Fish state.
fish_add_path --path --append --move "$HOME/.local/bin"
fish_add_path --path --append --move "$HOME/programs/bin"

# ---------------------------------------------------------------------------
# Interactive configuration
# ---------------------------------------------------------------------------

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
    abbr --add ll 'ls -lah --color=auto --group-directories-first'
end

if command -q bat
    abbr --add b 'bat'
    set -gx MANPAGER 'bat -plman'
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
abbr --add z 'zellij attach -c main'

# Reload Fish configuration.
# Honor XDG_CONFIG_HOME rather than hardcoding ~/.config.
abbr --add src 'source "$__fish_config_dir/config.fish"'

# Python venvs provide a Fish-specific activation script.
abbr --add venv 'source .venv/bin/activate.fish'

# Keep forcing your explicit vimrc if desired. Removed for testing to see if vim still works with ssu
# alias vim='vim -u "$HOME/.vimrc"'

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

    command mkdir -p -- "$argv[1]"
    and builtin cd -- "$argv[1]"
end

function get_os_short --description 'Print short OS identifier'
    set -l os_id unknown
    set -l os_version

    if test -r /etc/os-release
        set -l id_line (
            string match -r '^ID=.*' </etc/os-release
        )

        set -l version_line (
            string match -r '^VERSION_ID=.*' </etc/os-release
        )

        if test -n "$id_line"
            set os_id (
                string replace 'ID=' '' "$id_line" |
                string trim -c '"'
            )
        end

        if test -n "$version_line"
            set os_version (
                string replace 'VERSION_ID=' '' "$version_line" |
                string trim -c '"'
            )
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

    # Preserve custom XDG locations when configured.
    set -q XDG_CONFIG_HOME; and set -a root_env "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
    set -q XDG_DATA_HOME; and set -a root_env "XDG_DATA_HOME=$XDG_DATA_HOME"

    command sudo env $root_env "$fish_path" -i
end

function y
    set tmp (mktemp -t "yazi-cwd.XXXXXX")
    command yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and [ "$cwd" != "$PWD" ]; and test -d "$cwd"
        builtin cd -- "$cwd"
    end
    command rm -f -- "$tmp"
end

# ---------------------------------------------------------------------------
# Key bindings
# ---------------------------------------------------------------------------

function fish_user_key_bindings
    # Ctrl + Backspace mapping to backward-kill-word
    bind \cw backward-kill-word

    # Ctrl+Backspace is terminal-dependent. Your current terminal apparently
    # reports it as Ctrl+H, so preserve that binding.
    bind \ch backward-kill-word
end

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

# <<< tychart-setup:fish <<<
