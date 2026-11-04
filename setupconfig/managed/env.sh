# The one place environment variables are defined. Bash, POSIX sh, Zsh, and
# Fish all source this file, so every user-provided variable belongs here (in
# this block, or just below it in ~/.config/setupconfig/env.sh) and not in
# ~/.profile, ~/.bashrc, or the Fish config: those files are not read by every
# shell, so a value added there silently reaches only one of them.
# Keep it to plain `export NAME=value` lines, because Fish parses this file too
# and cannot parse `if`, `[[ ]]`, `${NAME:-default}`, or functions.
export EDITOR="__DEFAULT_EDITOR__"
export VISUAL="$EDITOR"
export SYSTEMD_EDITOR="$EDITOR"
export INPUTRC="$HOME/.inputrc"

# User-local binaries go in front of the inherited PATH. Each export pushes onto
# the front, so the LAST line wins: ~/.local/bin first, then ~/.bun/bin, then
# ~/bin. Add a directory by adding a line above the one that should stay ahead
# of it.
export PATH="$HOME/bin:$PATH"
export PATH="$HOME/.bun/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"

# Bun installs here when it is present; other tools read this variable.
export BUN_INSTALL="$HOME/.bun"

# Startup files re-source each other in many existing setups, so mark the load.
# Every shell block skips this file when the marker is already present, which
# keeps PATH free of repeats without per-shell dedupe code. Exported, so child
# shells inherit the marker together with the values it stands for.
# Sourcing this file by hand still prepends PATH again: that is the deliberate
# reload path (`src`).
export SETUPCONFIG_ENV_LOADED=1
