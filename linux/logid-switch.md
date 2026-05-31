
1. Install the Gnome extension `Window Calls` from Extension Manager

2. Copy files to `programs/logid-switch` folder:

logid-switch.sh:
```bash
tychart@fdesk(fedora44) ~/programs/logid-switch $ cat logid-switch.sh
#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------------------------------------------------------
# logid-switch.sh
#
# Watches the currently focused GNOME window and switches /etc/logid.cfg
# based on matching window title or wm_class.
#
# Requirements:
#   - GNOME Shell
#   - gdbus
#   - python3
#   - sudo permission for:
#       cp <profile> /etc/logid.cfg
#       systemctl restart logid
# `sudo visudo` entry example:
#       # Allow tychart to control logid and copy the two known cfg files without password
#        tychart ALL=(root) NOPASSWD: \
#            /usr/bin/systemctl restart logid, \
#            /usr/bin/systemctl start logid, \
#            /usr/bin/systemctl stop logid, \
#            /usr/bin/cp /home/tychart/programs/logid-switch/hwlegacy-logid.cfg /etc/logid.cfg, \
#            /usr/bin/cp /home/tychart/programs/logid-switch/default-logid.cfg /etc/logid.cfg
# -------------------------------------------------------------------

# How often to check the active window, in seconds.
POLL_INTERVAL=5

# Destination config used by logid.
LOGID_CONFIG="/etc/logid.cfg"

# Service to restart after switching configs.
LOGID_SERVICE="logid"

# Default profile used when no configured app matches.
DEFAULT_PROFILE_NAME="default"
DEFAULT_PROFILE_CONFIG="/home/tychart/programs/logid-switch/default-logid.cfg"

# -------------------------------------------------------------------
# Profiles
#
# Add more entries here later.
#
# Format:
#   profile name
#   config path
#   title match string
#   wm_class match string
#
# Matching is case-insensitive and substring-based.
#
# You can leave title or class empty if you only want to match one field.
# -------------------------------------------------------------------

PROFILE_NAMES=(
  "hogwartslegacy"
)

PROFILE_CONFIGS=(
  "/home/tychart/programs/logid-switch/hwlegacy-logid.cfg"
)

PROFILE_TITLE_MATCHES=(
  "Hogwarts Legacy"
)

PROFILE_CLASS_MATCHES=(
  "HogwartsLegacy"
)

# -------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------

log() {
  printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

contains_case_insensitive() {
  local haystack="$1"
  local needle="$2"

  [[ -n "$haystack" && -n "$needle" ]] || return 1

  case "${haystack,,}" in
    *"${needle,,}"*) return 0 ;;
    *) return 1 ;;
  esac
}

validate_setup() {
  require_command gdbus
  require_command python3
  require_command sudo
  require_command systemctl

  [[ -f "$DEFAULT_PROFILE_CONFIG" ]] ||
    die "Default profile config does not exist: $DEFAULT_PROFILE_CONFIG"

  local count_names="${#PROFILE_NAMES[@]}"
  local count_configs="${#PROFILE_CONFIGS[@]}"
  local count_titles="${#PROFILE_TITLE_MATCHES[@]}"
  local count_classes="${#PROFILE_CLASS_MATCHES[@]}"

  [[ "$count_names" -eq "$count_configs" &&
     "$count_names" -eq "$count_titles" &&
     "$count_names" -eq "$count_classes" ]] ||
    die "Profile arrays must all have the same length."

  local i
  for i in "${!PROFILE_NAMES[@]}"; do
    [[ -n "${PROFILE_NAMES[$i]}" ]] ||
      die "Profile name at index $i is empty."

    [[ -f "${PROFILE_CONFIGS[$i]}" ]] ||
      die "Profile config does not exist for '${PROFILE_NAMES[$i]}': ${PROFILE_CONFIGS[$i]}"

    [[ -n "${PROFILE_TITLE_MATCHES[$i]}" || -n "${PROFILE_CLASS_MATCHES[$i]}" ]] ||
      die "Profile '${PROFILE_NAMES[$i]}' must have at least one title or class match."
  done
}

get_active_window_json() {
  gdbus call --session \
    --dest org.gnome.Shell \
    --object-path /org/gnome/Shell/Extensions/Windows \
    --method org.gnome.Shell.Extensions.Windows.List |
  python3 -c '
import ast
import json
import sys

raw = sys.stdin.read().strip()

try:
    # gdbus returns a GVariant-like tuple:
    #   ("[JSON string]",)
    payload = ast.literal_eval(raw)[0]
    windows = json.loads(payload)

    for window in windows:
        if window.get("focus") is True:
            print(json.dumps(window, ensure_ascii=False))
            break
except Exception:
    # Keep stdout empty on failure so the shell script can handle it cleanly.
    pass
'
}

json_get_field() {
  local json="$1"
  local field="$2"

  python3 -c '
import json
import sys

raw = sys.stdin.read()
field = sys.argv[1]

try:
    obj = json.loads(raw)
    value = obj.get(field, "")
    if value is None:
        value = ""
    print(value)
except Exception:
    print("")
' "$field" <<< "$json"
}

find_matching_profile_index() {
  local active_title="$1"
  local active_class="$2"

  local i
  for i in "${!PROFILE_NAMES[@]}"; do
    local title_match="${PROFILE_TITLE_MATCHES[$i]}"
    local class_match="${PROFILE_CLASS_MATCHES[$i]}"

    if contains_case_insensitive "$active_title" "$title_match" ||
       contains_case_insensitive "$active_class" "$class_match"; then
      printf '%s\n' "$i"
      return 0
    fi
  done

  return 1
}

switch_profile() {
  local new_profile_name="$1"
  local new_profile_config="$2"

  log "Switching to profile: $new_profile_name"
  log "Applying config: $new_profile_config"

  sudo cp "$new_profile_config" "$LOGID_CONFIG"
  sudo systemctl restart "$LOGID_SERVICE"
}

# -------------------------------------------------------------------
# Main
# -------------------------------------------------------------------

validate_setup

current_profile="$DEFAULT_PROFILE_NAME"

log "Starting logid profile watcher."
log "Default profile: $DEFAULT_PROFILE_NAME"
log "Polling every ${POLL_INTERVAL}s."

# Ensure we start from the default config.
switch_profile "$DEFAULT_PROFILE_NAME" "$DEFAULT_PROFILE_CONFIG"

while true; do
  active_window_json="$(get_active_window_json)"

  active_title=""
  active_class=""
  target_profile_name="$DEFAULT_PROFILE_NAME"
  target_profile_config="$DEFAULT_PROFILE_CONFIG"

  if [[ -n "$active_window_json" ]]; then
    active_title="$(json_get_field "$active_window_json" "title")"
    active_class="$(json_get_field "$active_window_json" "wm_class")"

    if matching_index="$(find_matching_profile_index "$active_title" "$active_class")"; then
      target_profile_name="${PROFILE_NAMES[$matching_index]}"
      target_profile_config="${PROFILE_CONFIGS[$matching_index]}"
    fi
  fi

  if [[ "$target_profile_name" != "$current_profile" ]]; then
    log "Active title: ${active_title:-<none>}"
    log "Active class: ${active_class:-<none>}"

    switch_profile "$target_profile_name" "$target_profile_config"
    current_profile="$target_profile_name"
  fi

  sleep "$POLL_INTERVAL"
done
```

logid-switch.service:
```bash
[Unit]
Description=Logid profile switcher (user)

[Service]
Type=simple
ExecStart=/home/tychart/programs/logid-switch/logid-switch.sh
Restart=always
RestartSec=5
# Keep environment minimal; the service inherits the user's environment and bus

[Install]
WantedBy=default.target
```

In the folder, make sure there is a default cfg and a custom cfg:

default-logid.cfg example:
```
tychart@ubudesk(ubu25.10) ~/programs/games $ cat default-logid.cfg 
//  Logitech MX Master 4 Button Mapping                             
//  0x0c4  → Top button behind scroll wheel (MagSpeed toggle)      
//  0x052  → Middle click (wheel press)  (Standard middle click)
//  0x053  → Back button (side) (Browser Back)  
//  0x056  → Forward button (side) (Browser Forward)   
//  0x0c3  → Gesture button (Gesture button) (Media gesture hub)   
//  0x1a0  → Thumb button (bottom-left corner) (Super/Meta key)     

//  Configuration for Logitech MX Master 4      
//  Full gesture implementation on the gesture button for media control 

devices: (
  {
    name: "MX Master 4";

    // Set the DPI.
    dpi: 2000;

    // Enable smartshift to automatically switch between ratchet and free-spin.
    smartshift: {
      on: true;
      threshold: 15;
    };

    // Enable high-resolution scrolling for a smoother feel.
    hiresscroll: {
      //hires: true;
    };

    buttons: (
      // ── Top button (behind scroll wheel) ── Toggles SmartShift
      {
        cid: 0xc4;
        action: {
          type: "ToggleSmartshift";
        };
      },

      // ── Back button (side) ──────────────── Browser Back
      {
        cid: 0x53;
        action: {
          type: "Keypress";
          keys: [ "KEY_BACK" ];
        };
      },

      // ── Forward button (side) ───────────── Browser Forward
      {
        cid: 0x56;
        action: {
          type: "Keypress";
          keys: [ "KEY_FORWARD" ];
        };
      },

      // ── Thumb rest click ────────────────── Super/Windows key
      {
        cid: 0x1a0;
        action: {
          type: "Keypress";
          keys: [ "KEY_RIGHTMETA" ];
          //keys: [ "KEY_TAB" ];
        };
      },

      // ── Gesture button ──────────────────── Media Gestures
      {
        cid: 0xc3;
        action: {
          type: "Gestures";
          gestures: (
            // Hold + Move Up ──────────────── Volume Up
            {
              direction: "Up";
              mode: "OnInterval";
              interval: 100;            // pixels moved per emitted keypress (lower = more frequent)
              action: {
                type: "Keypress";
                keys: [ "KEY_VOLUMEUP" ];
              };
            },
            {
              direction: "Down";
              mode: "OnInterval";
              interval: 100;
              action: {
                type: "Keypress";
                keys: [ "KEY_VOLUMEDOWN" ];
              };
            },

            // Hold + Move Left ────────────── Previous Track
            {
              direction: "Left";
              mode: "OnRelease";
              action: {
                type: "Keypress";
                keys: [ "KEY_PREVIOUSSONG" ];
              };
            },

            // Hold + Move Right ───────────── Next Track
            {
              direction: "Right";
              mode: "OnRelease";
              action: {
                type: "Keypress";
                keys: [ "KEY_NEXTSONG" ];
              };
            },

            // Simple click (no movement) ──── Play/Pause
            {
              direction: "None";
              mode: "OnRelease";
              action: {
                type: "Keypress";
                keys: [ "KEY_PLAYPAUSE" ];
              };
            }
          );
        };
      }
    );
  }
);
```


This allows sudo access to restart logid and copy the specific files to `/etc` without the password prompt:

`sudo visudo` entry example:
```text
tychart ALL=(root) NOPASSWD: \
	/usr/bin/systemctl restart logid, \
	/usr/bin/systemctl start logid, \
	/usr/bin/systemctl stop logid, \
	/usr/bin/cp /home/tychart/programs/logid-switch/hwlegacy-logid.cfg /etc/logid.cfg, \
	/usr/bin/cp /home/tychart/programs/logid-switch/default-logid.cfg /etc/logid.cfg
```
