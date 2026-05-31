1. Install the Gnome extension `Window Calls` from Extension Manager

2. Copy files to games folder:
logid-switch.sh
```bash
tychart@ubudesk(ubu25.10) ~/programs/games $ cat logid-switch.sh
#!/usr/bin/env bash

GAME_NAME="Hogwarts Legacy"
CONFIG_DEFAULT="/home/tychart/programs/games/default-logid.cfg"
CONFIG_GAME="/home/tychart/programs/games/hwlegacy-logid.cfg"
CURRENT_MODE="default"

get_active_title() {
  gdbus call --session --dest org.gnome.Shell \
    --object-path /org/gnome/Shell/Extensions/Windows \
    --method org.gnome.Shell.Extensions.Windows.List \
  | awk -F"'" '{print $2}' \
  | jq -r '.[] | select(.focus == true).title' 2>/dev/null
}

while true; do
  active_title="$(get_active_title)"
  if [[ -n "$active_title" ]] && printf '%s\n' "$active_title" | grep -qiF "$GAME_NAME"; then
    if [[ "$CURRENT_MODE" != "game" ]]; then
      echo "Game detected (title: $active_title). Switching to game profile..."
      sudo cp "$CONFIG_GAME" /etc/logid.cfg
      sudo systemctl restart logid
      CURRENT_MODE="game"
    fi
  else
    if [[ "$CURRENT_MODE" != "default" ]]; then
      echo "Game not detected (title: ${active_title:-'<none>'}). Switching to default profile..."
      sudo cp "$CONFIG_DEFAULT" /etc/logid.cfg
      sudo systemctl restart logid
      CURRENT_MODE="default"
    fi
  fi
  sleep 5
done
```

logid-switch.service:
```bash
tychart@ubudesk(ubu25.10) ~/programs/games $ cat logid-switch.service 
[Unit]
Description=Logid profile switcher (user)

[Service]
Type=simple
ExecStart=/home/tychart/programs/games/logid-switch.sh
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
    dpi: 4000;

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
```text
root@ubudesk(ubu25.10) ~/programs/games # cat /etc/sudoers.d/logid-switch 
# Allow tychart to copy the two known cfg files (explicit paths) and restart logid without password:
tychart ALL=(root) NOPASSWD: /usr/bin/systemctl restart logid, /usr/bin/systemctl start logid, /usr/bin/systemctl stop logid, /usr/bin/cp /home/tychart/programs/games/hwlegacy-logid.cfg /etc/logid.cfg, /usr/bin/cp /home/tychart/programs/games/default-logid.cfg /etc/logid.cfg
```
