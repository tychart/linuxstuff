# ClipCascade Installation — Fedora + uv + GNOME Wayland

These instructions are for running ClipCascade on Fedora using `uv`.

This setup intentionally uses ClipCascade's **XWayland clipboard mode** with `--xmode true` and does **not** use `wl-copy`.

## 1. Download ClipCascade

Follow the main installation/download instructions from the [ClipCascade GitHub README](https://github.com/Sathvik-Rao/ClipCascade).

Extract or clone ClipCascade into:

```bash
~/programs/ClipCascade
```

Then enter the directory:

```bash
cd ~/programs/ClipCascade
```

## 2. Install Fedora dependencies

Install the native packages needed to build and use PyGObject/GTK:

```bash
sudo dnf install -y \
    gcc \
    pkg-config \
    python3-devel \
    gobject-introspection-devel \
    cairo-gobject-devel \
    gtk3-devel
```

Also make sure other dependencies are installed:

```bash
sudo dnf install -y python3 python3-pip python3-gobject xclip dunst libappindicator-gtk3
```

`wl-clipboard` is **not required** for this configuration.

## 3. Create the virtual environment with uv

Create a local `.venv`:

```bash
uv venv
```

This creates:

```text
~/programs/ClipCascade/.venv
```

You do not need to activate the virtual environment when using `uv pip` or when invoking `.venv/bin/python` directly.

## 4. Install ClipCascade's Python dependencies

Install the requirements:

```bash
uv pip install -r requirements.txt
```

## 5. Install PyGObject inside the virtual environment

ClipCascade's XWayland clipboard monitor requires the Python `gi` module.

Fedora's system `python3-gobject` package is not automatically visible inside an isolated `uv` virtual environment, so install PyGObject directly into `.venv`:

```bash
uv pip install pycairo PyGObject
```

Run this command to verify that `gi` can be imported:

```bash
.venv/bin/python -c 'import gi; print(gi.__file__)'
```

A successful result should look similar to:

```text
/home/tychart/programs/ClipCascade/.venv/lib/python3.11/site-packages/gi/__init__.py
```

## 6. Start ClipCascade manually

Because the project's `pyproject.toml` currently advertises Python `>=3.8` while one of its pinned dependencies requires Python `>=3.9`, running:

```bash
uv run main.py
```

may cause `uv` to re-resolve the project and fail.

Instead, run the Python executable from the already-created virtual environment directly:

```bash
.venv/bin/python main.py --xmode true --gui true
```

The important option is:

```text
--xmode true
```

This forces ClipCascade to use the X11/XWayland clipboard path rather than the native Wayland `wl-copy` path.

On GNOME Wayland, the desktop session itself remains Wayland; only ClipCascade's clipboard integration uses XWayland.

## 7. Verify clipboard monitoring

When ClipCascade starts successfully, its logs should contain something similar to:

```text
XMODE: True
```

There should no longer be an error such as:

```text
Failed to start clipboard monitor: Error No module named 'gi'
```

You can also verify that the XWayland clipboard works independently:

```bash
printf 'ClipCascade test' | xclip -selection clipboard
```

Paste into another application with `Ctrl+V`.

You can confirm that no `wl-copy` or `wl-paste` process is running with:

```bash
pgrep -af 'wl-copy|wl-paste'
```

No output is expected.

---

# Running ClipCascade with systemd

## 8. Create `clipcascade.service`

Place `clipcascade.service` inside:

```text
~/programs/ClipCascade/
```

The service should launch the Python executable from the virtual environment and enable XWayland mode.

For example, its `ExecStart` should use:

```text
/home/tychart/programs/ClipCascade/.venv/bin/python /home/tychart/programs/ClipCascade/main.py --xmode true --gui true
```

## 9. Link the service into the user systemd directory

Make sure the user systemd directory exists:

```bash
mkdir -p ~/.config/systemd/user
```

Create the symlink:

```bash
ln -s ~/programs/ClipCascade/clipcascade.service ~/.config/systemd/user/clipcascade.service
```

Confirm it:

```bash
ls -l ~/.config/systemd/user/
```

## 10. Reload systemd

```bash
systemctl --user daemon-reload
```

## 11. Start ClipCascade

```bash
systemctl --user start clipcascade
```

## 12. Check its status

```bash
systemctl --user status clipcascade
```

If anything goes wrong, inspect the logs:

```bash
journalctl --user -r -u clipcascade
```

For live logs:

```bash
journalctl --user -f -u clipcascade
```

## 13. Enable ClipCascade at login

Once everything works:

```bash
systemctl --user enable clipcascade
```

Or start and enable it simultaneously:

```bash
systemctl --user enable --now clipcascade
```

## 14. Reboot and verify

Reboot:

```bash
systemctl reboot
```

After logging back into GNOME, check:

```bash
systemctl --user status clipcascade
```

and verify that clipboard synchronization works.

---

## Reinstall / rebuild the virtual environment

If the environment ever needs to be recreated:

```bash
cd ~/programs/ClipCascade

rm -rf .venv

uv venv

uv pip install -r requirements.txt

uv pip install pycairo PyGObject
```

Verify PyGObject:

```bash
.venv/bin/python -c 'import gi; print(gi.__file__)'
```

Then test ClipCascade:

```bash
.venv/bin/python main.py --xmode true --gui true
```

## Important notes

* Use `dnf`, not `apt`, on Fedora.
* Use `uv venv` instead of `python3 -m venv`.
* Use `uv pip install` instead of regular `pip install`.
* Do not use `wl-copy` or `wl-paste` with this configuration.
* Run ClipCascade with `--xmode true`.
* `PyGObject` must be installed inside `.venv`; installing only Fedora's system `python3-gobject` package may not make `gi` available to the virtual environment.
* Prefer `.venv/bin/python main.py ...` over `uv run main.py` for this project unless its `requires-python` metadata is corrected.
