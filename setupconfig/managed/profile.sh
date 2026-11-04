# POSIX entry point for sh and dash login shells. Bash and Fish never read
# this file (Bash enters through ~/.bash_profile), so setupconfig only adds this
# block when ~/.profile already exists.
if [ -z "${SETUPCONFIG_ENV_LOADED:-}" ] && [ -r "$HOME/.config/setupconfig/env.sh" ]; then
  . "$HOME/.config/setupconfig/env.sh"
fi
