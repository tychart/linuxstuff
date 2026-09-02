# How to setup typepass on Gnome system


This is a script to auto type in a password based on Gnome Keyrings

```
#!/usr/bin/env bash
set -euo pipefail

password="$(secret-tool lookup purpose sudo-password)"

if [[ -z "${password}" ]]; then
    notify-send "sudo hotkey" "No sudo password found or keyring is locked"
    exit 1
fi

sleep 0.25
printf '%s' "$password" | ydotool type --key-delay 0 --file -
```
