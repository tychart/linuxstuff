#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

app_name="AppImage"
dir=""
pattern="*.AppImage"
make_executable=true
app_args=()

# Below is a general-purpose AppImage runner.
# It lets each .desktop file specify the folder, glob pattern, display name, and optional app arguments.

# Example .desktop file:
#   [Desktop Entry]
#   Type=Application
#   Name=GDLauncher
#   Comment=Open-source Minecraft launcher
#   Exec=/home/tychart/programs/appimages/run-latest-appimage.sh --dir /home/tychart/programs/appimages/gdlauncher --glob 'GDLauncher__*__linux__x64.AppImage' --name 'GDLauncher' -- --no-sandbox
#   Icon=/home/tychart/programs/appimages/gdlauncher/icon.png
#   Terminal=false
#   Categories=Game;Utility;


# One important note: this chooses the “latest” AppImage by file modification time,
# not by semantic version in the filename. 
# That is usually the best behavior for an auto-updated AppImage folder, but it means 
# copying an older AppImage into 
# the folder later could make it the selected one.

# To use, create a .desktop file like the example above, adjust the Exec line as needed
# Then use the below command to symlink it to ~/.local/share/applications/
#   ln -s "$PWD/gdlauncher.desktop" ~/.local/share/applications/

usage() {
    cat <<'EOF'
Usage:
  run-latest-appimage.sh --dir DIR [--glob GLOB] [--name NAME] [--no-chmod] [-- APP_ARGS...]

Examples:
  ./run-latest-appimage.sh \
    --dir "$HOME/programs/appimages/gdlauncher" \
    --glob 'GDLauncher__*__linux__x64.AppImage' \
    --name 'GDLauncher' \
    -- --no-sandbox

  ./run-latest-appimage.sh \
    --dir "$HOME/programs/appimages/prismlauncher" \
    --glob '*.AppImage' \
    --name 'Prism Launcher'
EOF
}

show_error() {
    local message="$1"

    if command -v zenity >/dev/null 2>&1 && { [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; }; then
        zenity --error \
            --title="$app_name" \
            --width=520 \
            --text="$message"
    else
        printf '%s: %s\n' "$app_name" "$message" >&2
    fi
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --dir)
            dir="${2:-}"
            shift 2
            ;;
        --dir=*)
            dir="${1#*=}"
            shift
            ;;
        --glob|--pattern)
            pattern="${2:-}"
            shift 2
            ;;
        --glob=*|--pattern=*)
            pattern="${1#*=}"
            shift
            ;;
        --name)
            app_name="${2:-}"
            shift 2
            ;;
        --name=*)
            app_name="${1#*=}"
            shift
            ;;
        --no-chmod)
            make_executable=false
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            app_args=("$@")
            break
            ;;
        *)
            show_error "Unknown option:

$1"
            usage >&2
            exit 2
            ;;
    esac
done

if [ -z "$dir" ]; then
    show_error "Missing required option:

--dir DIR"
    exit 2
fi

if [ ! -d "$dir" ]; then
    show_error "Directory does not exist:

$dir"
    exit 1
fi

latest="$(
    find "$dir" -maxdepth 1 -type f -name "$pattern" -printf '%T@\t%p\0' 2>/dev/null \
        | sort -z -nr \
        | sed -z 's/^[^\t]*\t//' \
        | tr '\0' '\n' \
        | head -n 1
)"

if [ -z "$latest" ]; then
    show_error "No AppImage matching this pattern was found.

Directory:
$dir

Pattern:
$pattern"
    exit 1
fi

if [ ! -x "$latest" ]; then
    if [ "$make_executable" = true ]; then
        if ! chmod +x "$latest" 2>/dev/null; then
            show_error "Could not make this AppImage executable:

$latest"
            exit 1
        fi
    else
        show_error "AppImage is not executable:

$latest"
        exit 1
    fi
fi

"$latest" "${app_args[@]}"
status=$?

if [ "$status" -ne 0 ]; then
    show_error "$app_name failed to start or exited with an error.

File:
$latest

Exit code:
$status"
    exit "$status"
fi