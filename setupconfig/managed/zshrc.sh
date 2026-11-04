# Environment variables come from the one shared file that Bash, POSIX sh,
# and Fish also read. Zsh's own interactive setup stays untouched.
if [ -z "${SETUPCONFIG_ENV_LOADED:-}" ] && [ -r "$HOME/.config/setupconfig/env.sh" ]; then
  . "$HOME/.config/setupconfig/env.sh"
fi

# Prefer Fish for interactive work when it is installed, exactly like ~/.bashrc.
# ~/.zshrc is only read by interactive shells, so no interactivity test is
# needed here. SETUPCONFIG_NO_FISH keeps the current shell, as it does for Bash.
if [ -z "${FISH_VERSION:-}" ] && [ -z "${SETUPCONFIG_NO_FISH:-}" ] && command -v fish >/dev/null 2>&1; then
  exec "$(command -v fish)"
fi
