Install both packages:

```bash
sudo apt update
sudo apt install ydotool ydotoold
```



Create a user systemd file:

```bash
mkdir -p ~/.config/systemd/user/
cat <<EOF > ~/.config/systemd/user/ydotoold.service
[Unit]
Description=ydotoold - Backend for ydotool

[Service]
Type=simple
ExecStart=/usr/bin/ydotoold
Restart=always

[Install]
WantedBy=default.target
EOF
```

Enable the service:

```bash
systemctl --user daemon-reload
systemctl --user enable ydotoold
systemctl --user start ydotoold
systemctl --user status ydotoold
```
