# Ensure Bash login shells also load ~/.profile.
if [ -r "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
