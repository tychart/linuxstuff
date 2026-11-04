# Bash login shells read this file instead of ~/.profile, so hand off to the
# one config every Bash shell reads. ~/.profile stays the POSIX entry point for
# sh/dash; exports belong in the shared environment file, not in ~/.profile.
if [ -r "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi
