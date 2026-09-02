

Install ydotool

```
sudo dnf install ydotool
```

Add the user to the input group, then restart (or logout) afterwards

```
sudo usermod -aG input $USER
```


Setup `/dev/uinput` permissions

```
sudo tee /etc/udev/rules.d/80-uinput.rules >/dev/null <<'EOF'
KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"
EOF

sudo modprobe uinput
sudo udevadm control --reload-rules
sudo udevadm trigger
```


Setup `/home/tychart/.config/systemd/user/ydotoold.service`

```
[Unit]
Description=Starts ydotoold service

[Service]
Type=simple
Restart=always
ExecStart=/usr/bin/ydotoold
ExecReload=/usr/bin/kill -HUP $MAINPID
KillMode=process
TimeoutSec=180

[Install]
WantedBy=default.target
```
