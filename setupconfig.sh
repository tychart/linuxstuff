#!/usr/bin/env bash

# Portable setup bootstrap
#
# Purpose:
#   Apply a portable shell/Vim/Fish setup across Fedora, Ubuntu, and RHEL
#   without destructively replacing whole dotfiles.
#
# Behavior:
#   - Updates clearly marked managed blocks inside standard dotfiles
#   - Preserves user content outside those managed blocks
#   - Installs the OSC 52 Vim plugin as ~/.vim/plugin/oscyank.vim
#   - Optionally installs universal helper scripts (currently osc52) on any
#     supported shell platform, and Linux x64-only binaries (currently fzf, bat,
#     eza, rg, ya, yazi, zellij, and fish) only on Linux x86_64/amd64 by
#     default. The two lists live below so future assets can be classified in
#     one obvious place. Missing tools are downloaded into ~/.local/bin from
#     this repo's latest release assets when compatible or explicitly forced;
#     the folder is created if needed, and it is added to PATH in ~/.profile
#     when that file already exists (custom-patched builds like zellij then win
#     over distros).
#   - Adds shell integration for them to the managed ~/.bashrc block when
#     ~/.bashrc already exists: the y()
#     yazi wrapper, the zellij `z` alias, fzf keybindings/completion, and
#     optional handoff into Fish for interactive shells when Fish is installed
#   - Adds a tiny Fish handoff to ~/.zshrc when ~/.zshrc already exists
#   - Keeps the yazi (yazi.toml, theme.toml) and zellij (config.kdl) configs
#     under ${XDG_CONFIG_HOME:-~/.config} in sync with the repo whenever the
#     matching tool is installed (no prompt): a changed file rotates the
#     previous copy to <name>.bak, then <name>.bak2, ... and an unchanged
#     file is left alone, so reruns are quiet and idempotent
#   - Installs the tokyo-night yazi flavor once via 'ya pkg add' (yazi's own
#     package manager) when the flavor files are missing, so the theme
#     referenced by the managed theme.toml actually loads
#   - Nice-to-have installs prompt on the terminal, even when piped via
#     `curl ... | bash` (the prompt opens /dev/tty). Fully non-interactive
#     runs (cron, CI, ssh without a tty) skip instead, unless
#     --install-optional is passed, which auto-installs without prompting
#
# Usage:
#   chmod +x setupconfig.sh
#   ./setupconfig.sh
#   ./setupconfig.sh --install-optional
#   ./setupconfig.sh --install-fish
#   ./setupconfig.sh --install-x64-binaries --install-optional
#
#   or
#   curl -fsSL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash -s -- --install-optional
#   curl -fsSL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash -s -- --install-fish
#   curl -fsSL https://raw.githubusercontent.com/tychart/LinuxStuff/main/setupconfig.sh | bash -s -- --install-x64-binaries --install-optional

set -euo pipefail

SCRIPT_TAG="setupconfig"
readonly SCRIPT_TAG
# Single source of truth for the preferred editor written into ~/.profile.
DEFAULT_EDITOR="vim"
readonly DEFAULT_EDITOR

require_supported_bash() {
  # macOS still ships Bash 3.2.x by default. Keep this script compatible with
  # 3.2 and newer, and fail clearly if someone runs it with an older Bash.
  if (( BASH_VERSINFO[0] < 3 || (BASH_VERSINFO[0] == 3 && BASH_VERSINFO[1] < 2) )); then
    printf '[setup] Bash 3.2 or newer is required; found %s\n' "${BASH_VERSION:-unknown}" >&2
    exit 2
  fi
}

require_supported_bash

PROFILE_FILE="$HOME/.profile"
BASH_PROFILE_FILE="$HOME/.bash_profile"
BASHRC_FILE="$HOME/.bashrc"
ZSHRC_FILE="$HOME/.zshrc"
VIMRC_FILE="$HOME/.vimrc"
INPUTRC_FILE="$HOME/.inputrc"
FISH_CONFIG_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
VIM_DIR="$HOME/.vim"
VIM_PLUGIN_DIR="$VIM_DIR/plugin"
VIM_UNDO_DIR="$VIM_DIR/undodir"
OSCYANK_FILE="$VIM_PLUGIN_DIR/oscyank.vim"
readonly PROFILE_FILE BASH_PROFILE_FILE BASHRC_FILE ZSHRC_FILE VIMRC_FILE INPUTRC_FILE FISH_CONFIG_FILE
readonly VIM_DIR VIM_PLUGIN_DIR VIM_UNDO_DIR OSCYANK_FILE

# When set (--install-optional / --install-fish), compatible missing optional
# assets are installed without prompting, even when the script runs without a
# TTY. Linux x64-only assets still stay gated unless the platform matches or
# --install-x64-binaries is passed.
INSTALL_NICE_TO_HAVES=0
INSTALL_FISH=0
# Safety valve for unsupported systems: by default repo-provided compiled
# binaries are offered only on Linux x86_64/amd64. Set by
# --install-x64-binaries when the user intentionally wants to force them.
INSTALL_X64_REPO_BINARIES=0

# Remove temporary files on exit, including when set -e aborts mid-run.
TEMP_FILES=()
cleanup_temp_files() {
  # Bash 3.2 (the default /bin/bash on older macOS installs) can treat an
  # empty array expansion as unbound under set -u, so check the count first.
  if [[ ${#TEMP_FILES[@]} -gt 0 ]]; then
    rm -f "${TEMP_FILES[@]}" 2>/dev/null || true
  fi
}
trap cleanup_temp_files EXIT
register_temp_file() {
  TEMP_FILES[${#TEMP_FILES[@]}]="$1"
}

log() {
  printf '[setup] %s\n' "$*"
}

show_usage() {
  cat <<EOF
Usage:
  ./setupconfig.sh
  ./setupconfig.sh --install-optional
  ./setupconfig.sh --install-fish
  ./setupconfig.sh --install-x64-binaries --install-optional

  --install-optional   install compatible missing optional assets without
                       prompting: universal helper scripts everywhere, plus
                       Linux x64 binaries on Linux x86_64/amd64 only
  --install-fish       install fish from this repo's Linux x64 release asset
                       into ~/.local/bin without prompting when compatible
  --install-x64-binaries
                       force offering/installing this repo's Linux x64 binary
                       assets on the current machine; use only when you know
                       they are compatible
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --install-optional)
        INSTALL_NICE_TO_HAVES=1
        shift
        ;;
      --install-fish)
        INSTALL_FISH=1
        shift
        ;;
      --install-x64-binaries)
        INSTALL_X64_REPO_BINARIES=1
        shift
        ;;
      -h|--help)
        show_usage
        exit 0
        ;;
      *)
        printf 'Unknown option: %s\n\n' "$1" >&2
        show_usage >&2
        exit 1
        ;;
    esac
  done
}

parse_args "$@"

# Replace one managed block inside a file while leaving everything else alone.
upsert_managed_block() {
  local file="$1"
  local name="$2"
  local content="$3"
  local marker_prefix="${4:-#}"
  local start_marker="${marker_prefix} >>> ${SCRIPT_TAG}:${name} >>>"
  local end_marker="${marker_prefix} <<< ${SCRIPT_TAG}:${name} <<<"
  # Also recognize the alternate comment prefix used by other managed files.
  local legacy_hash_start="# >>> ${SCRIPT_TAG}:${name} >>>"
  local legacy_hash_end="# <<< ${SCRIPT_TAG}:${name} <<<"
  local legacy_vim_start="\" >>> ${SCRIPT_TAG}:${name} >>>"
  local legacy_vim_end="\" <<< ${SCRIPT_TAG}:${name} <<<"
  local tmp
  local preserved_tmp
  local first_preserved_line=''

  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  register_temp_file "$tmp"
  preserved_tmp="$(mktemp)"
  register_temp_file "$preserved_tmp"

  if [[ -f $file ]]; then
    awk \
      -v start="$start_marker" \
      -v end="$end_marker" \
      -v old_hash_start="$legacy_hash_start" \
      -v old_hash_end="$legacy_hash_end" \
      -v old_vim_start="$legacy_vim_start" \
      -v old_vim_end="$legacy_vim_end" '
        $0 == start || $0 == old_hash_start || $0 == old_vim_start { skip = 1; next }
        $0 == end   || $0 == old_hash_end   || $0 == old_vim_end   { skip = 0; next }
        !skip { print }
      ' "$file" > "$preserved_tmp"
  else
    : > "$preserved_tmp"
  fi

  {
    printf '%s\n%s\n%s\n' "$start_marker" "$content" "$end_marker"

    if [[ -s $preserved_tmp ]]; then
      IFS= read -r first_preserved_line < "$preserved_tmp" || true
      if [[ -n $first_preserved_line ]]; then
        printf '\n'
      fi
      cat "$preserved_tmp"
    fi
  } > "$tmp"

  if [[ -f $file ]] && cmp -s "$file" "$tmp"; then
    rm -f "$tmp" "$preserved_tmp"
    log "Managed block '$name' unchanged in $file"
    return 0
  fi

  mv "$tmp" "$file"
  rm -f "$preserved_tmp"
  log "Updated managed block '$name' in $file"
}

upsert_existing_managed_block() {
  local file="$1"
  local name="$2"

  if [[ ! -e $file ]]; then
    log "Skipping managed block '$name': $file does not exist"
    return 0
  fi

  upsert_managed_block "$@"
}

write_managed_file() {
  local file="$1"
  local content="$2"
  local tmp

  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp)"
  register_temp_file "$tmp"
  printf '%s\n' "$content" > "$tmp"

  if [[ -f $file ]] && cmp -s "$file" "$tmp"; then
    rm -f "$tmp"
    log "$file unchanged"
    return 0
  fi

  mv "$tmp" "$file"
  log "Wrote $file"
}

detect_package_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    printf 'apt'
  elif command -v dnf >/dev/null 2>&1; then
    printf 'dnf'
  elif command -v yum >/dev/null 2>&1; then
    printf 'yum'
  else
    return 1
  fi
}

detect_system_bashrc_path() {
  local id=''
  local id_like=''

  if [[ -r /etc/os-release ]]; then
    . /etc/os-release
    id="${ID:-}"
    id_like="${ID_LIKE:-}"
  fi

  case " ${id} ${id_like} " in
    *' ubuntu '*|*' debian '*)
      printf '/etc/bash.bashrc'
      ;;
    *' rhel '*|*' fedora '*|*' centos '*|*' rocky '*|*' almalinux '*)
      printf '/etc/bashrc'
      ;;
    *)
      return 1
      ;;
  esac
}

confirm_prompt() {
  local prompt="$1"
  local reply=''
  local use_tty=false

  if [[ ! -t 0 ]]; then
    # stdin is not a terminal (e.g. `curl ... | bash` feeds the script
    # through a pipe): prompt on the controlling terminal instead. If there
    # is no controlling terminal (cron, CI, ssh without a tty), this run is
    # truly non-interactive and cannot prompt. Never redirect fd 0 itself:
    # a piped script is still being read from stdin.
    if ( exec 0< /dev/tty ) 2>/dev/null; then
      use_tty=true
    else
      return 1
    fi
  fi

  printf '%s [y/N]: ' "$prompt" >&2
  if [[ $use_tty == true ]]; then
    read -r reply < /dev/tty || reply=''
  else
    read -r reply || reply=''
  fi

  case "$reply" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

# Map a generic dependency name to the actual package name for a package
# manager. Keeps the per-package-manager mapping in one place.
package_name_for() {
  local pm="$1" dep="$2"

  case "$pm:$dep" in
    *:git)             printf 'git' ;;
    apt:vim)           printf 'vim' ;;
    dnf:vim|yum:vim)   printf 'vim-enhanced' ;;
    *) return 1 ;;
  esac
}

# Run the actual install for the detected package manager.
install_packages() {
  local pm="$1"
  shift

  case "$pm" in
    apt) sudo apt-get update && sudo apt-get install -y "$@" ;;
    dnf) sudo dnf install -y "$@" ;;
    yum) sudo yum install -y "$@" ;;
  esac
}

ensure_dependencies() {
  local missing=()
  local pm
  local packages=()
  local dep
  local pkg
  local display_cmd=''

  command -v git >/dev/null 2>&1 || missing[${#missing[@]}]=git
  command -v vim >/dev/null 2>&1 || missing[${#missing[@]}]=vim

  if [[ ${#missing[@]} -eq 0 ]]; then
    return 0
  fi

  if ! pm="$(detect_package_manager)"; then
    log "Missing dependencies: ${missing[*]}"
    log "No supported package manager found (expected apt-get, dnf, or yum)."
    return 0
  fi

  for dep in "${missing[@]}"; do
    if pkg="$(package_name_for "$pm" "$dep")"; then
      packages[${#packages[@]}]="$pkg"
    fi
  done

  case "$pm" in
    apt) display_cmd="sudo apt-get update && sudo apt-get install -y ${packages[*]}" ;;
    dnf) display_cmd="sudo dnf install -y ${packages[*]}" ;;
    yum) display_cmd="sudo yum install -y ${packages[*]}" ;;
  esac

  log "Missing dependencies detected: ${missing[*]}"
  printf '\n[setup] The script can install them for you using:\n'
  printf '  %s\n\n' "$display_cmd"

  if confirm_prompt "Do you want to run that install command?"; then
    install_packages "$pm" "${packages[@]}"
  else
    log "Skipping dependency installation at user request."
  fi
}

# ---------------------------------------------------------------------------
# Optional assets
#
# These ship as release assets of this GitHub repo and are installed to
# ~/.local/bin, the conventional user-local executable location on modern
# Linux systems. Keep architecture-specific and architecture-agnostic assets
# separate so macOS, Raspberry Pi OS, Termux, and other ARM/non-Linux users can
# safely take the portable shell/Vim/Fish config without receiving incompatible
# Linux x64 binaries.
# ---------------------------------------------------------------------------

NICE_TO_HAVE_REPO="tychart/linuxstuff"
# Used only when the GitHub API cannot be reached to resolve the latest tag.
NICE_TO_HAVE_FALLBACK_TAG="v1.0.0"
NICE_TO_HAVE_BIN_DIR="$HOME/.local/bin"
# Names here are both the release asset names and the installed executable
# names. Add future repo assets to exactly one list:
#   - UNIVERSAL: scripts or other architecture-agnostic executables
#   - X64: Linux x86_64/amd64 compiled binaries
NICE_TO_HAVE_UNIVERSAL_TOOLS=(osc52)
NICE_TO_HAVE_X64_TOOLS=(fzf bat eza rg ya yazi zellij)
FISH_X64_TOOLS=(fish)
readonly NICE_TO_HAVE_REPO NICE_TO_HAVE_FALLBACK_TAG NICE_TO_HAVE_BIN_DIR
readonly NICE_TO_HAVE_UNIVERSAL_TOOLS NICE_TO_HAVE_X64_TOOLS FISH_X64_TOOLS

# Cheap release-asset checks that need no extra tools: compiled binaries start
# with the 4 magic bytes 0x7f 'E' 'L' 'F', while shell-script executables like
# osc52 start with a shebang. Catches HTML error pages and truncated or corrupt
# downloads without requiring the `file` command.
is_elf_binary() {
  local magic
  magic="$(head -c 4 "$1" 2>/dev/null)"
  [[ "$magic" == $'\x7fELF' ]]
}

is_shebang_script() {
  local magic
  magic="$(head -c 2 "$1" 2>/dev/null)"
  [[ "$magic" == '#!' ]]
}

is_valid_release_executable() {
  is_elf_binary "$1" || is_shebang_script "$1"
}

# Resolve the newest release tag via the GitHub API.  Callers that only need
# a best-effort install can use the fallback wrapper below; callers deciding
# whether to replace an existing installation must not guess a release tag.
fetch_current_release_tag() {
  local api_url="https://api.github.com/repos/${NICE_TO_HAVE_REPO}/releases/latest"
  local tag

  tag="$(curl -fsSL --max-time 20 "$api_url" 2>/dev/null | LC_ALL=C sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n 1)" || return 1
  [[ -n $tag ]] || return 1
  printf '%s' "$tag"
}

# The standalone binary installer can safely try its known initial release
# when GitHub's API is temporarily unavailable.
fetch_latest_release_tag() {
  if fetch_current_release_tag; then
    return 0
  fi

  # Warn on stderr so the message is not captured by callers using command
  # substitution (e.g. tag="$(fetch_latest_release_tag)").
  printf '[setup] Could not query GitHub API for the latest %s release; falling back to %s\n' "$NICE_TO_HAVE_REPO" "$NICE_TO_HAVE_FALLBACK_TAG" >&2
  printf '%s' "$NICE_TO_HAVE_FALLBACK_TAG"
}

lowercase() {
  # Avoid Bash 4's ${var,,} so the installer can still run under macOS's
  # older system Bash.
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

detected_platform() {
  printf '%s/%s' "$(uname -s 2>/dev/null || printf unknown)" "$(uname -m 2>/dev/null || printf unknown)"
}

is_linux_x64() {
  local os arch

  os="$(uname -s 2>/dev/null || printf unknown)"
  arch="$(uname -m 2>/dev/null || printf unknown)"

  case "$os:$arch" in
    Linux:x86_64|Linux:amd64) return 0 ;;
    *) return 1 ;;
  esac
}

can_offer_linux_x64_assets() {
  is_linux_x64 || [[ $INSTALL_X64_REPO_BINARIES == 1 ]]
}

log_skipped_linux_x64_assets() {
  local label="$1"
  shift

  log "Skipping ${label}: repo assets are Linux x64-only; detected $(detected_platform)."
  log "Install these tools with your platform package manager instead when available: $*"
  log "If you intentionally want to force this repo's Linux x64 assets, re-run with --install-x64-binaries."
}

ensure_repo_binaries() {
  local prompt="$1"
  local auto_install="$2"
  local auto_flag_name="$3"
  local label="$4"
  shift 4
  local tools_ref=("$@")
  local dir="$NICE_TO_HAVE_BIN_DIR"
  local label_lower
  local missing=()
  local present=()
  local tool
  local tag
  local url
  local dest
  local tmp
  local version

  label_lower="$(lowercase "$label")"

  if [[ ${#tools_ref[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ ! -d $dir ]]; then
    mkdir -p "$dir"
    log "Created $dir (optional binaries will be installed here)"
  fi

  shopt -s nullglob
  rm -f "$dir"/.*.part.*
  shopt -u nullglob

  for tool in "${tools_ref[@]}"; do
    dest="$dir/$tool"
    if [[ -s $dest ]] && is_valid_release_executable "$dest"; then
      chmod +x "$dest" 2>/dev/null || true
      log "${label} '$tool' already installed ($dest)"
    else
      if [[ -e $dest ]]; then
        log "${label} '$tool' exists at $dest but is empty or not a valid release executable; re-downloading"
      fi
      missing[${#missing[@]}]="$tool"
    fi
  done

  if [[ ${#missing[@]} -eq 0 ]]; then
    log "All ${label_lower} present in $dir"
    return 0
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log "curl is required to install missing ${label_lower} (${missing[*]}); skipping"
    return 0
  fi

  log "Missing ${label_lower} from $dir: ${missing[*]}"

  if [[ $auto_install != 1 ]] && ! confirm_prompt "$prompt"; then
    log "Skipping ${label_lower} installation."
    log "Re-run with ${auto_flag_name} to install without prompting (also works in cron/CI)."
    return 0
  fi

  tag="$(fetch_latest_release_tag)"
  log "Installing ${label_lower} from release ${tag}"

  for tool in "${missing[@]}"; do
    dest="$dir/$tool"
    tmp="$(mktemp "${dir}/.${tool}.part.XXXXXX")"
    register_temp_file "$tmp"
    url="https://github.com/${NICE_TO_HAVE_REPO}/releases/download/${tag}/${tool}"

    if ! curl -fL --retry 3 --progress-bar -o "$tmp" "$url"; then
      rm -f "$tmp"
      log "Failed to download ${tool} from ${url}"
      continue
    fi

    if ! is_valid_release_executable "$tmp"; then
      rm -f "$tmp"
      log "Downloaded ${tool} is not a valid release executable (from ${url}); not installing"
      continue
    fi

    chmod 755 "$tmp"
    mv -f "$tmp" "$dest"
    log "Installed ${tool} -> ${dest} (release ${tag})"

    if version="$("$dest" --version 2>/dev/null | head -n 1)" && [[ -n $version ]]; then
      log "  ${tool} version: ${version}"
    else
      log "  Warning: ${tool} installed but its --version smoke test failed"
    fi
  done

  for tool in "${tools_ref[@]}"; do
    [[ -x $dir/$tool ]] && present[${#present[@]}]="$tool"
  done
  log "${label} present in ${dir}: ${present[*]:-none}"
}

ensure_nice_to_haves() {
  ensure_repo_binaries \
    "Download and install missing universal helper scripts (${NICE_TO_HAVE_UNIVERSAL_TOOLS[*]})?" \
    "$INSTALL_NICE_TO_HAVES" \
    "--install-optional" \
    "Universal helper scripts" \
    "${NICE_TO_HAVE_UNIVERSAL_TOOLS[@]}"

  if can_offer_linux_x64_assets; then
    ensure_repo_binaries \
      "Download and install missing Linux x64 nice-to-have binaries (${NICE_TO_HAVE_X64_TOOLS[*]})?" \
      "$INSTALL_NICE_TO_HAVES" \
      "--install-optional" \
      "Linux x64 nice-to-have binaries" \
      "${NICE_TO_HAVE_X64_TOOLS[@]}"
  else
    log_skipped_linux_x64_assets "Linux x64 nice-to-have binaries" "${NICE_TO_HAVE_X64_TOOLS[@]}"
  fi
}

ensure_fish() {
  if can_offer_linux_x64_assets; then
    ensure_repo_binaries \
      "Download and install fish from this repo's Linux x64 release asset?" \
      "$INSTALL_FISH" \
      "--install-fish" \
      "Fish Linux x64 binary" \
      "${FISH_X64_TOOLS[@]}"
  else
    log_skipped_linux_x64_assets "fish binary" "${FISH_X64_TOOLS[@]}"
  fi
}

# ---------------------------------------------------------------------------
# Tool config files: yazi and zellij
#
# When a tool is installed (by this script into $NICE_TO_HAVE_BIN_DIR, or
# already on PATH), keep its config under ${XDG_CONFIG_HOME:-~/.config} in
# sync with the source repo. Downloads go to a temp file first,
# are verified, and are moved into place only after any previous file is
# rotated to <name>.bak, then <name>.bak2, etc. Nothing happens when the
# content is unchanged, so reruns are quiet and idempotent. The .bak files
# are intentionally left in place so the previous whole-file config can be
# restored manually if needed.
# ---------------------------------------------------------------------------

# Raw-file base for configs on the default branch. Uses the canonical
# raw.githubusercontent.com endpoint (one hop instead of github.com's
# redirect to raw). The repo path is case-insensitive on GitHub.
CONFIG_SOURCE_URL_BASE="https://raw.githubusercontent.com/tychart/linuxstuff/main"
readonly CONFIG_SOURCE_URL_BASE

# Yazi flavor referenced by the managed theme.toml ([flavor] dark =
# "tokyo-night"). The flavor is a ya package, not part of this repo, so it is
# installed with yazi's own package manager.
YAZI_TOKYO_NIGHT_PKG="BennyOe/tokyo-night"
readonly YAZI_TOKYO_NIGHT_PKG

tool_is_present() {
  local tool="$1"

  # Covers tools just installed by this script into ~/.local/bin (which may
  # not be on PATH until a new shell sources ~/.profile) and tools found on
  # PATH.
  [[ -x "$NICE_TO_HAVE_BIN_DIR/$tool" ]] || command -v "$tool" >/dev/null 2>&1
}

# Rotate an existing file out of the way: <file>.bak, then <file>.bak2,
# <file>.bak3, ... taking the first free name.
rotate_config_backup() {
  local file="$1"
  local backup="${file}.bak"
  local n=1

  while [[ -e $backup || -L $backup ]]; do
    n=$((n + 1))
    backup="${file}.bak${n}"
  done

  mv -f "$file" "$backup"
  log "Rotated existing $file -> $backup"
}

# Fetch one config file and install it atomically. Ordering matters: the new
# content is fully downloaded and validated before the existing file is
# touched, so a failed download never costs the user their current config.
install_one_config() {
  local tool="$1"
  local remote_path="$2"
  local dest="$3"
  local dir
  local tmp
  local url

  if ! tool_is_present "$tool"; then
    log "Skipping ${tool} config (${dest}): ${tool} binary not installed"
    return 0
  fi

  url="${CONFIG_SOURCE_URL_BASE}/${remote_path}"
  dir="$(dirname "$dest")"
  mkdir -p "$dir"

  # Remove stale partial downloads from any previously interrupted run.
  shopt -s nullglob
  rm -f "$dir"/.*.config.part.*
  shopt -u nullglob

  tmp="$(mktemp "$dir/.${tool}.config.part.XXXXXX")"
  register_temp_file "$tmp"

  if ! curl -fL --retry 3 -sS -o "$tmp" "$url"; then
    rm -f "$tmp"
    log "Failed to download ${url}; leaving any existing config untouched"
    return 0
  fi

  if [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    log "Downloaded ${url} is empty; not installing"
    return 0
  fi

  # Cheap guard against HTML error pages served with a 200 status; none of
  # these config formats starts with '<'.
  if [[ $(head -c 1 "$tmp") == '<' ]]; then
    rm -f "$tmp"
    log "Downloaded ${url} looks like an HTML error page; not installing"
    return 0
  fi

  # mktemp creates 0600 files; configs should be the usual 0644 before they
  # are moved into place.
  chmod 644 "$tmp"

  if [[ -e $dest && ! -d $dest ]]; then
    if cmp -s "$dest" "$tmp"; then
      rm -f "$tmp"
      log "${tool} config unchanged (${dest})"
      return 0
    fi
    rotate_config_backup "$dest"
  fi

  mv -f "$tmp" "$dest"
  log "Installed ${tool} config -> ${dest}"
}

# Install the tokyo-night flavor with ya, but only when it is missing: ya
# pkg add on an already-installed package is a no-op, so the flavor.toml
# existence check (the exact file yazi reads at startup) keeps reruns free of
# network traffic. Failures are warnings: the script should still succeed
# even if the theme cannot be fetched right now.
ensure_tokyo_night_flavor() {
  local config_root="$1"
  local flavor_toml="$config_root/yazi/flavors/tokyo-night.yazi/flavor.toml"
  local ya_bin=''

  if ! tool_is_present yazi; then
    log "Skipping tokyo-night flavor: yazi binary not installed"
    return 0
  fi

  if ! tool_is_present ya; then
    log "Skipping tokyo-night flavor: ya (yazi package manager) not installed"
    return 0
  fi

  if [[ -e $flavor_toml ]]; then
    log "yazi tokyo-night flavor already installed (${flavor_toml})"
    return 0
  fi

  # Prefer the ya this script installs into ~/.local/bin (which may not be on
  # PATH until a new shell sources ~/.profile); fall back to any ya on PATH.
  if [[ -x "$NICE_TO_HAVE_BIN_DIR/ya" ]]; then
    ya_bin="$NICE_TO_HAVE_BIN_DIR/ya"
  else
    ya_bin="$(command -v ya)"
  fi

  log "Installing yazi tokyo-night flavor via 'ya pkg add ${YAZI_TOKYO_NIGHT_PKG}'"
  if ! "$ya_bin" pkg add "$YAZI_TOKYO_NIGHT_PKG"; then
    log "Warning: 'ya pkg add ${YAZI_TOKYO_NIGHT_PKG}' failed; yazi theme may not load until it succeeds"
    return 0
  fi

  if [[ -e $flavor_toml ]]; then
    log "yazi tokyo-night flavor installed (${flavor_toml})"
  else
    log "Warning: 'ya pkg add ${YAZI_TOKYO_NIGHT_PKG}' reported success but ${flavor_toml} is still missing"
  fi
}

install_tool_configs() {
  local config_root="${XDG_CONFIG_HOME:-$HOME/.config}"

  if ! command -v curl >/dev/null 2>&1; then
    log "curl not found; skipping yazi/zellij config installation"
    return 0
  fi

  install_one_config yazi yazi/yazi.toml "$config_root/yazi/yazi.toml"
  install_one_config yazi yazi/theme.toml "$config_root/yazi/theme.toml"
  install_one_config zellij zellij/config.kdl "$config_root/zellij/config.kdl"

  ensure_tokyo_night_flavor "$config_root"
}

ensure_bun_node_shim() {
  local bun_bin="$HOME/.bun/bin/bun"
  local node_shim="$HOME/.local/bin/node"

  if [[ ! -x $bun_bin ]]; then
    log "Bun not installed under ~/.bun; skipping node compatibility shim"
    return 0
  fi

  if command -v node >/dev/null 2>&1; then
    log "node already available on PATH; skipping Bun compatibility shim"
    return 0
  fi

  mkdir -p "$HOME/.local/bin"

  if [[ -L $node_shim ]]; then
    if [[ $(readlink "$node_shim") == "$bun_bin" ]]; then
      log "Bun node compatibility shim already present (${node_shim})"
      return 0
    fi
    log "Existing ${node_shim} points elsewhere; leaving it unchanged"
    return 0
  fi

  if [[ -e $node_shim ]]; then
    log "Existing ${node_shim} is not a symlink; leaving it unchanged"
    return 0
  fi

  ln -s "$bun_bin" "$node_shim"
  log "Installed Bun node compatibility shim -> ${node_shim}"
}

ensure_dependencies

ensure_nice_to_haves
ensure_fish
ensure_bun_node_shim

install_tool_configs

SYSTEM_BASHRC_PATH=''
SYSTEM_BASHRC_BLOCK=''
if SYSTEM_BASHRC_PATH="$(detect_system_bashrc_path)"; then
  log "Will source system Bash defaults from ${SYSTEM_BASHRC_PATH} before user customizations in ~/.bashrc"
  SYSTEM_BASHRC_BLOCK=$(cat <<EOF
# Source distro-provided Bash defaults before user customizations.
if [ -r "${SYSTEM_BASHRC_PATH}" ]; then
  . "${SYSTEM_BASHRC_PATH}"
fi
EOF
)
else
  log "No known system Bash rc for this OS; leaving any existing ~/.bashrc fully self-managed"
fi

PROFILE_CONTENT=$(cat <<'EOF'
# Login shells read ~/.profile first, then pull in ~/.bashrc for interactive extras.
# The guard avoids an infinite loop when ~/.bashrc later sources ~/.profile.
# Use expr instead of a case statement here to keep this block friendly to
# older/vendor shells that may read ~/.profile.
if [ -n "${BASH_VERSION:-}" ] && [ -r "$HOME/.bashrc" ] && [ -z "${__SETUPCONFIG_SOURCING_PROFILE_FROM_BASHRC:-}" ] && expr "x$-" : 'x.*i' >/dev/null 2>&1; then
  . "$HOME/.bashrc"
fi

# Prefer user-local bin directories when they exist. Add them first, then
# dedupe once below so rerunning/sourceing this block does not grow PATH.
[ -d "$HOME/bin" ] && PATH="$HOME/bin:$PATH"
[ -d "$HOME/.local/bin" ] && PATH="$HOME/.local/bin:$PATH"

# Bun: configure it only when installed so shells that do not use Bun pay
# almost no startup cost.
if [ -d "$HOME/.bun" ]; then
  export BUN_INSTALL="$HOME/.bun"
  [ -d "$BUN_INSTALL/bin" ] && PATH="$BUN_INSTALL/bin:$PATH"
fi

# Collapse duplicate entries while keeping the first occurrence, so the
# precedence above is preserved. Written without Bash-only locals so this
# block stays safe in ~/.profile on macOS/vendor shells.
__setupconfig_dedupe_path() {
  result=''
  old_ifs=$IFS
  IFS=':'
  for entry in $PATH; do
    [ -z "$entry" ] && continue
    duplicate=0
    for existing in $result; do
      if [ "$existing" = "$entry" ]; then
        duplicate=1
        break
      fi
    done
    [ "$duplicate" -eq 0 ] && result="${result:+$result:}$entry"
  done
  IFS=$old_ifs
  printf '%s' "$result"
}
PATH="$(__setupconfig_dedupe_path)"
unset -f __setupconfig_dedupe_path
unset result entry existing duplicate old_ifs
export PATH

# Editor defaults live here so other tools can simply inherit them.
export EDITOR="__DEFAULT_EDITOR__"
export VISUAL="__DEFAULT_EDITOR__"
export SYSTEMD_EDITOR="__DEFAULT_EDITOR__"
export INPUTRC="${INPUTRC:-$HOME/.inputrc}"
EOF
)
PROFILE_CONTENT="${PROFILE_CONTENT//__DEFAULT_EDITOR__/$DEFAULT_EDITOR}"

BASH_PROFILE_CONTENT=$(cat <<'EOF'
# Ensure Bash login shells also load ~/.profile.
if [ -r "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi
EOF
)

ZSHRC_CONTENT=$(cat <<'EOF'
# Prefer Fish for interactive Zsh work when it is installed.
# This stays tiny on purpose: the full shell setup lives in Fish/Bash config,
# and missing Fish should never break Zsh startup.
if [[ -o interactive ]] && [[ -z "${FISH_VERSION:-}" ]] && command -v fish >/dev/null 2>&1; then
  exec "$(command -v fish)"
fi
EOF
)

BASHRC_CONTENT=$(cat <<'EOF'
# Editor defaults should exist before any early return so child CLI tools inherit them.
export EDITOR="${EDITOR:-__DEFAULT_EDITOR__}"
export VISUAL="${VISUAL:-$EDITOR}"

# Stop here for non-interactive shells.
[[ $- == *i* ]] || return

# ~/.profile sources this file back, both in its managed block and in
# preserved user content. If we are already inside such a source, stop:
# everything below was already defined by the outer pass. Without this the
# two files would source each other forever and every shell would hang.
if [ -n "${__SETUPCONFIG_SOURCING_PROFILE_FROM_BASHRC:-}" ]; then
  return
fi

__SYSTEM_BASHRC_BLOCK__
# Many terminals start Bash as a non-login shell, which skips ~/.profile.
# Source it here so PATH and editor defaults are consistent in every shell.
# The guard prevents recursion because ~/.profile sources this file back.
if [ -r "$HOME/.profile" ]; then
  __SETUPCONFIG_SOURCING_PROFILE_FROM_BASHRC=1
  . "$HOME/.profile"
  unset __SETUPCONFIG_SOURCING_PROFILE_FROM_BASHRC
fi

# Prefer Fish for interactive work when it is installed.
if [ -z "${FISH_VERSION:-}" ] && command -v fish >/dev/null 2>&1; then
  exec "$(command -v fish)"
fi

export INPUTRC="${INPUTRC:-$HOME/.inputrc}"

# History behavior.
HISTCONTROL=ignoredups:erasedups
HISTSIZE=50000
HISTFILESIZE=100000
HISTTIMEFORMAT="%d/%m/%y %T "
shopt -s histappend
shopt -s checkwinsize

__setupconfig_history_sync() {
  # Append this shell's new history lines, then pull in lines from other shells.
  history -a
  history -n
}

if expr "x;${PROMPT_COMMAND:-};" : 'x.*;__setupconfig_history_sync;.*' >/dev/null 2>&1; then
  :
elif [ -z "${PROMPT_COMMAND:-}" ]; then
  PROMPT_COMMAND="__setupconfig_history_sync"
else
  PROMPT_COMMAND="__setupconfig_history_sync;${PROMPT_COMMAND}"
fi
export PROMPT_COMMAND

# Bash completion.
if [ -r /usr/share/bash-completion/bash_completion ]; then
  . /usr/share/bash-completion/bash_completion
elif [ -r /etc/bash_completion ]; then
  . /etc/bash_completion
fi

if [ -r /usr/share/bash-completion/completions/git ]; then
  . /usr/share/bash-completion/completions/git
elif [ -r /etc/bash_completion.d/git ]; then
  . /etc/bash_completion.d/git
fi

# fzf integration (Ctrl-T/Ctrl-R/Alt-C keybindings and completion).
if command -v fzf >/dev/null 2>&1; then
  eval "$(fzf --bash)"
fi

# Tool integrations. Each optional integration is guarded so a missing
# user-local binary never creates a broken alias or pager configuration.
if command -v eza >/dev/null 2>&1; then
  alias ll='eza -lag --git --icons --group-directories-first'
else
  # Portable fallback for systems whose ls does not support GNU color/grouping flags
  # (macOS, Termux, BusyBox, etc.).
  alias ll='ls -lah'
fi

if command -v bat >/dev/null 2>&1; then
  alias b='bat'

  # bat's direct man-page mode preserves groff formatting and adds readable
  # syntax colors. Avoid pre-processing through col: it can corrupt ANSI
  # sequences on modern man implementations.
  if command -v man >/dev/null 2>&1; then
    export MANPAGER='bat --plain --language=man'
  fi
fi

# Aliases.
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias c='clear'
alias k='kubectl'
alias myip='hostname -I 2>/dev/null | awk "{print \$1}"'
alias src='source "$HOME/.profile"'
alias venv='source .venv/bin/activate'
alias ver='cat /etc/*-release'
alias vim='vim -u "$HOME/.vimrc"'
alias whoson='last -w | tac'
alias details='get_machine_info'
if command -v zellij >/dev/null 2>&1; then
  alias z='zellij attach -c main'
fi

# Functions.
mmkdir() {
  if [ $# -ne 1 ]; then
    printf 'usage: mmkdir <dir>\n' >&2
    return 1
  fi

  command mkdir -p "$1" && cd -- "$1"
}

get_machine_info() {
  local distro version_id os ver name ip

  if [ -r /etc/os-release ]; then
    . /etc/os-release
    distro="$ID"
    version_id="$VERSION_ID"
  else
    distro="unknown"
    version_id="unknown"
  fi

  if [ "$distro" = "ubuntu" ]; then
    os="ubu"
  else
    os="$distro"
  fi

  ver="${os}${version_id}"
  name="$(hostname)"
  ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  if [ -z "$ip" ]; then
    ip="$(hostname -i 2>/dev/null || true)"
  fi

  printf '******************************\n'
  printf 'Hostname: %s\n' "$name"
  printf 'IP address: %s\n' "$ip"
  printf 'Operating system: %s\n' "$ver"
  printf '******************************\n'
}

get_os_short() {
  if [ -r /etc/os-release ]; then
    . /etc/os-release
    printf '%s%s' "$ID" "$VERSION_ID"
  else
    printf 'unknown'
  fi
}

ssu() {
  # Preserve your HOME and rc setup when opening a root shell.
  sudo --preserve-env=HOME env HOME="$HOME" bash --rcfile "$HOME/.bashrc" -i
}

y() {
  # Open yazi and change to the directory it left us in on exit.
  if ! command -v yazi >/dev/null 2>&1; then
    printf 'y: yazi is not installed; install it with your system package manager or this setup script on Linux x64.\n' >&2
    return 127
  fi

  local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
  command yazi "$@" --cwd-file="$tmp"
  IFS= read -r -d '' cwd < "$tmp"
  [ "$cwd" != "$PWD" ] && [ -d "$cwd" ] && builtin cd -- "$cwd"
  command rm -f "$tmp"
}


if ! command -v osc52 >/dev/null 2>&1; then
  osc52() {
      local data

      if [ $# -gt 0 ]; then
          data="$*"
      else
          data="$(cat)"
      fi

      local encoded

      if base64 --wrap=0 </dev/null >/dev/null 2>&1; then
          encoded="$(printf '%s' "$data" | base64 --wrap=0)"
      else
          encoded="$(printf '%s' "$data" | base64 | tr -d '\n')"
      fi

      printf '\033]52;c;%s\a' "$encoded"
  }
fi

# Prompt.
# NOTE: You mentioned you may replace this later with Starship.
# This section is intentionally isolated so it is easy to remove/swap.
__setupconfig_set_prompt() {
  if [ "$TERM" = "xterm-color" ]; then
    PS1='\u@\h \w $ '
    return
  fi

  if [ "$EUID" -ne 0 ]; then
    PS1='\[\e[1;32m\]\u\[\e[0m\]@\[\e[0;31m\]\h\[\e[1;36m\]($(get_os_short)) \[\e[1;34m\]\w \[\e[0m\]$ '
  else
    PS1='\[\e[1;35m\]\u\[\e[0m\]@\[\e[0;31m\]\h\[\e[1;36m\]($(get_os_short)) \[\e[1;34m\]\w\[\e[0m\] # '
  fi
}
__setupconfig_set_prompt
export PS1

# Readline quality-of-life.
bind 'set bell-style none'

# Delete backward until punctuation/whitespace instead of treating punctuation as part of a word.
my_custom_backwards_kill_word() {
  local line="$READLINE_LINE"
  local pos="$READLINE_POINT"
  local boundary_chars='[^[:alnum:]]'
  local char

  if [ "$READLINE_POINT" -eq 0 ]; then
    return
  fi

  (( pos-- ))
  while (( pos > 0 )); do
    char=${line:pos-1:1}
    if [[ $char =~ $boundary_chars ]]; then
      break
    fi
    (( pos-- ))
  done

  READLINE_LINE="${line:0:pos}${line:READLINE_POINT}"
  READLINE_POINT=$pos
}

# Ctrl+Backspace often arrives as Ctrl+H in terminals.
bind -x '"\C-h": my_custom_backwards_kill_word'

# Ctrl+W is rebound to match the custom Ctrl+Backspace behavior above.
bind -x '"\C-w": my_custom_backwards_kill_word'
EOF
)
BASHRC_CONTENT="${BASHRC_CONTENT//__DEFAULT_EDITOR__/$DEFAULT_EDITOR}"
BASHRC_CONTENT="${BASHRC_CONTENT/__SYSTEM_BASHRC_BLOCK__/$SYSTEM_BASHRC_BLOCK}"

VIMRC_CONTENT=$(cat <<'EOF'
set nocompatible

syntax on
if has('autocmd')
  filetype plugin indent on
endif

" Basic editing and search defaults.
set number
set showcmd
set ruler
set wildmenu

if exists('&wildmode')
  set wildmode=longest:full,full
endif

set lazyredraw
set showmatch
set incsearch
set hlsearch
set ignorecase
set smartcase
set backspace=indent,eol,start
set autoindent
set expandtab
set tabstop=2
set shiftwidth=2

if exists('&softtabstop')
  set softtabstop=2
endif

set mouse=a
set hidden
set splitbelow
set splitright
set scrolloff=3
set history=1000
set noerrorbells
set visualbell
set laststatus=2
set cursorline

" Terminal cursor shapes: blinking block in Normal, blinking bar in Insert,
" blinking underline in Replace. Terminal support may vary.
let &t_SI = "\<Esc>[5 q"
let &t_SR = "\<Esc>[3 q"
let &t_EI = "\<Esc>[1 q"

" Save undo history on disk so undo still works after reopening a file.
if has('persistent_undo')
  set undodir=~/.vim/undodir
  set undofile
  set undolevels=1000
  set undoreload=10000
endif

" F6 toggles the highlighted current line. Double-Esc clears search highlighting.
nnoremap <silent> <F6> :set cursorline!<CR>
inoremap <silent> <F6> <C-o>:set cursorline!<CR>
nnoremap <silent> <Esc><Esc> :nohlsearch<CR>

" Use space as the leader key for custom shortcuts.
if !exists('mapleader')
  let mapleader = ' '
endif

" OSC 52 lets Vim copy over SSH/remote terminals without needing a local clipboard provider.
" <leader>c copies the current motion or visual selection.
nmap <leader>c <Plug>OSCYankOperator
nmap <leader>cc <leader>c_
vmap <leader>c <Plug>OSCYankVisual

" Reopen files at the last cursor position from the previous edit session.
augroup setupconfig_vim_startup
  autocmd!
  autocmd BufReadPost *
    \ if line("'\"") > 0 && line("'\"") <= line('$') && &filetype !~# 'commit' |
    \   execute 'normal! g' . nr2char(96) . '"' |
    \ endif
augroup END
EOF
)

FISH_CONFIG_CONTENT=$(cat <<'EOF'
# ---------------------------------------------------------------------------
# Environment
# ---------------------------------------------------------------------------

# Preserve inherited values when they already exist.
if not set -q EDITOR
    set -gx EDITOR __DEFAULT_EDITOR__
end

if not set -q VISUAL
    set -gx VISUAL $EDITOR
end

if not set -q SYSTEMD_EDITOR
    set -gx SYSTEMD_EDITOR $EDITOR
end

# Prefer user-local executable directories. Use fish_add_path when available,
# but keep a portable fallback for older Fish builds.
if functions -q fish_add_path
    fish_add_path --path --move "$HOME/bin"
    fish_add_path --path --move "$HOME/.local/bin"
else
    for dir in "$HOME/bin" "$HOME/.local/bin"
        if test -d "$dir"
            if not contains -- "$dir" $PATH
                set -gx PATH "$dir" $PATH
            end
        end
    end
end

# Bun: only configure it when installed, so shells that do not use Bun pay
# almost no startup cost.
if test -d "$HOME/.bun"
    set -gx BUN_INSTALL "$HOME/.bun"

    if test -d "$BUN_INSTALL/bin"
        if functions -q fish_add_path
            fish_add_path --path --move "$BUN_INSTALL/bin"
        else if not contains -- "$BUN_INSTALL/bin" $PATH
            set -gx PATH "$BUN_INSTALL/bin" $PATH
        end
    end
end

# Everything below is only needed in an interactive shell.
status is-interactive; or return

# ---------------------------------------------------------------------------
# fzf
# ---------------------------------------------------------------------------

if command -q fzf
    fzf --fish | source
end

# ---------------------------------------------------------------------------
# Tool integrations / aliases
# ---------------------------------------------------------------------------

if command -q eza
    abbr --add ll 'eza -lag --git --icons --group-directories-first'
else
    # Portable fallback for systems whose ls does not support GNU color/grouping flags.
    abbr --add ll 'ls -lah'
end

if command -q bat
    abbr --add b 'bat'
    if command -q man
        set -gx MANPAGER 'bat -plman'
    end
end

# ---------------------------------------------------------------------------
# Aliases
# ---------------------------------------------------------------------------

abbr --add .. 'cd ..'
abbr --add ... 'cd ../..'
abbr --add .... 'cd ../../..'
abbr --add ..... 'cd ../../../..'

abbr --add c clear
abbr --add k kubectl
abbr --add ver 'cat /etc/*-release'
abbr --add whoson 'last -w | tac'
abbr --add details get_machine_info
if command -q zellij
    abbr --add z 'zellij attach -c main'
end

# Reload Fish configuration.
abbr --add src 'source "$__fish_config_dir/config.fish"'

# Python venvs provide a Fish-specific activation script.
abbr --add venv 'source .venv/bin/activate.fish'

# ---------------------------------------------------------------------------
# Small helper functions
# ---------------------------------------------------------------------------

function myip --description 'Print primary IP address'
    hostname -I 2>/dev/null | awk '{print $1}'
end

function mmkdir --description 'Create a directory and enter it'
    if test (count $argv) -ne 1
        printf 'usage: mmkdir <dir>\n' >&2
        return 1
    end

    command mkdir -p "$argv[1]"
    and builtin cd -- "$argv[1]"
end

function get_machine_info --description 'Print host, IP, and OS summary'
    set -l distro unknown
    set -l version_id unknown
    set -l os
    set -l ver
    set -l name (hostname)
    set -l ip

    if test -r /etc/os-release
        set -l id_line (string match -r '^ID=.*' </etc/os-release)
        set -l version_line (string match -r '^VERSION_ID=.*' </etc/os-release)

        if test -n "$id_line"
            set distro (string replace 'ID=' '' "$id_line" | string trim -c '"')
        end

        if test -n "$version_line"
            set version_id (string replace 'VERSION_ID=' '' "$version_line" | string trim -c '"')
        end
    end

    if test "$distro" = ubuntu
        set os ubu
    else
        set os "$distro"
    end

    set ver "$os$version_id"
    set ip (hostname -I 2>/dev/null | awk '{print $1}')
    if test -z "$ip"
        set ip (hostname -i 2>/dev/null)
    end

    printf '******************************\n'
    printf 'Hostname: %s\n' "$name"
    printf 'IP address: %s\n' "$ip"
    printf 'Operating system: %s\n' "$ver"
    printf '******************************\n'
end

function get_os_short --description 'Print short OS identifier'
    set -l os_id unknown
    set -l os_version

    if test -r /etc/os-release
        set -l id_line (string match -r '^ID=.*' </etc/os-release)
        set -l version_line (string match -r '^VERSION_ID=.*' </etc/os-release)

        if test -n "$id_line"
            set os_id (string replace 'ID=' '' "$id_line" | string trim -c '"')
        end

        if test -n "$version_line"
            set os_version (string replace 'VERSION_ID=' '' "$version_line" | string trim -c '"')
        end
    end

    if test "$os_id" = ubuntu
        set os_id ubu
    end

    printf '%s%s' "$os_id" "$os_version"
end

function ssu --description 'Open root Fish shell using current user config and history'
    set -l fish_path (command -s fish)

    if test -z "$fish_path"
        printf 'ssu: fish not found in PATH\n' >&2
        return 127
    end

    set -l root_env "HOME=$HOME"
    set -q XDG_CONFIG_HOME; and set -a root_env "XDG_CONFIG_HOME=$XDG_CONFIG_HOME"
    set -q XDG_DATA_HOME; and set -a root_env "XDG_DATA_HOME=$XDG_DATA_HOME"

    command sudo env $root_env "$fish_path" -i
end

function y --description 'Open yazi and cd to the directory it leaves behind'
    if not command -q yazi
        printf 'y: yazi is not installed; install it with your system package manager or this setup script on Linux x64.\n' >&2
        return 127
    end

    set -l tmp (mktemp -t "yazi-cwd.XXXXXX")
    command yazi $argv --cwd-file="$tmp"
    if read -z cwd <"$tmp"; and test "$cwd" != "$PWD"; and test -d "$cwd"
        builtin cd -- "$cwd"
    end
    command rm -f "$tmp"
end

# ---------------------------------------------------------------------------
# Key bindings
# ---------------------------------------------------------------------------

function fish_user_key_bindings
    bind \cw backward-kill-word
    bind \ch backward-kill-word
end

# ---------------------------------------------------------------------------
# Prompt
# ---------------------------------------------------------------------------

function fish_prompt
    set -l user_color green
    set -l prompt_symbol '>'

    if fish_is_root_user
        set user_color magenta
        set prompt_symbol '#'
    end

    set_color --bold $user_color
    printf '%s' "$USER"

    set_color normal
    printf '@'

    set_color red
    printf '%s' (prompt_hostname)

    set_color --bold cyan
    printf '(%s) ' (get_os_short)

    set_color --bold blue
    printf '%s' (prompt_pwd)

    set_color normal
    printf ' %s ' "$prompt_symbol"
end
EOF
)
FISH_CONFIG_CONTENT="${FISH_CONFIG_CONTENT//__DEFAULT_EDITOR__/$DEFAULT_EDITOR}"

INPUTRC_CONTENT=$(cat <<'EOF'
set input-meta on
set output-meta on
set bell-style none

# Let custom Readline bindings win instead of auto-reserving tty keys like Ctrl+W.
set bind-tty-special-chars off

set completion-ignore-case on
set show-all-if-ambiguous on
set mark-symlinked-directories on

$if mode=emacs
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[3~": delete-char
"\e[2~": quoted-insert

"\e[1;5C": forward-word
"\e[1;5D": backward-word
"\e[5C": forward-word
"\e[5D": backward-word
"\e\e[C": forward-word
"\e\e[D": backward-word

$if term=rxvt
"\e[7~": beginning-of-line
"\e[8~": end-of-line
"\eOc": forward-word
"\eOd": backward-word
$endif
$endif
EOF
)

# Install a small custom Vim plugin so copy works reliably in SSH, tmux, and other remote terminals.
# It uses OSC 52 escape sequences instead of depending on xclip/pbcopy or a local GUI clipboard.
OSCYANK_PLUGIN_CONTENT=$(cat <<'EOF'
" -------------------- INIT --------------------------------
if exists('g:loaded_oscyank')
  finish
endif
let g:loaded_oscyank = 1

" -------------------- VARIABLES ---------------------------
let s:mark = nr2char(96)
let s:commands = {
  \ 'operator': {'block': s:mark . '[\<C-v>' . s:mark . ']y', 'char': s:mark . '[v' . s:mark . ']y', 'line': "'[V']y"},
  \ 'visual': {'': 'gvy', 'V': 'gvy', 'v': 'gvy', '\x16': 'gvy'}}
let s:b64_table = [
  \ 'A','B','C','D','E','F','G','H','I','J','K','L','M','N','O','P',
  \ 'Q','R','S','T','U','V','W','X','Y','Z','a','b','c','d','e','f',
  \ 'g','h','i','j','k','l','m','n','o','p','q','r','s','t','u','v',
  \ 'w','x','y','z','0','1','2','3','4','5','6','7','8','9','+','/']

" -------------------- OPTIONS ---------------------------
function s:options_max_length()
  return get(g:, 'oscyank_max_length', 0)
endfunction

function s:options_silent()
  return get(g:, 'oscyank_silent', 0)
endfunction

function s:options_trim()
  return get(g:, 'oscyank_trim', 0)
endfunction

function s:options_osc52()
  return get(g:, 'oscyank_osc52', "\x1b]52;c;%s\x07")
endfunction

" -------------------- UTILS -------------------------------
function s:echo(text, hl)
  echohl a:hl
  echo printf('[oscyank] %s', a:text)
  echohl None
endfunction

function s:encode_b64(str, size)
  let bytes = map(range(len(a:str)), 'char2nr(a:str[v:val])')
  let b64 = []

  for i in range(0, len(bytes) - 1, 3)
    let n = bytes[i] * 0x10000
          \ + get(bytes, i + 1, 0) * 0x100
          \ + get(bytes, i + 2, 0)
    call add(b64, s:b64_table[n / 0x40000])
    call add(b64, s:b64_table[n / 0x1000 % 0x40])
    call add(b64, s:b64_table[n / 0x40 % 0x40])
    call add(b64, s:b64_table[n % 0x40])
  endfor

  if len(bytes) % 3 == 1
    let b64[-1] = '='
    let b64[-2] = '='
  endif

  if len(bytes) % 3 == 2
    let b64[-1] = '='
  endif

  let b64 = join(b64, '')
  if a:size <= 0
    return b64
  endif

  let chunked = ''
  while strlen(b64) > 0
    let chunked .= strpart(b64, 0, a:size) . "\n"
    let b64 = strpart(b64, a:size)
  endwhile

  return chunked
endfunction

function s:get_text(mode, type)
  let l:clipboard = &clipboard
  let l:selection = &selection
  let l:register = getreg('"')
  let l:visual_marks = [getpos("'<"), getpos("'>")]

  set clipboard=
  set selection=inclusive
  silent execute printf('keepjumps normal! %s', s:commands[a:mode][a:type])
  let l:text = getreg('"')

  let &clipboard = l:clipboard
  let &selection = l:selection
  call setreg('"', l:register)
  call setpos("'<", l:visual_marks[0])
  call setpos("'>", l:visual_marks[1])

  return l:text
endfunction

function s:trim_text(text)
  let l:text = a:text
  let l:indent = matchstrpos(l:text, '^\s\+')

  if l:indent[1] >= 0
    let l:pattern = printf('\n%s', repeat('\s', l:indent[2] - l:indent[1]))
    let l:text = substitute(l:text, l:pattern, '\n', 'g')
  endif

  return trim(l:text)
endfunction

function s:write(osc52)
  if filewritable('/dev/fd/2') == 1
    let l:success = writefile([a:osc52], '/dev/fd/2', 'b') == 0
  elseif has('nvim')
    let l:success = chansend(v:stderr, a:osc52) > 0
  else
    exec('silent! !echo ' . shellescape(a:osc52))
    redraw!
    let l:success = 1
  endif
  return l:success
endfunction

" -------------------- PUBLIC ------------------------------
function! OSCYank(text) abort
  let l:text = s:options_trim() ? s:trim_text(a:text) : a:text

  if s:options_max_length() > 0 && strlen(l:text) > s:options_max_length()
    call s:echo(printf('Selection is too big: length is %d, limit is %d', strlen(l:text), s:options_max_length()), 'WarningMsg')
    return
  endif

  let l:text_b64 = s:encode_b64(l:text, 0)
  let l:osc52 = printf(s:options_osc52(), l:text_b64)
  let l:success = s:write(l:osc52)

  if !l:success
    call s:echo('Failed to copy selection', 'ErrorMsg')
  elseif !s:options_silent()
    call s:echo(printf('%d characters copied', strlen(l:text)), 'Normal')
  endif

  return l:success
endfunction

function! OSCYankOperatorCallback(type) abort
  let l:text = s:get_text('operator', a:type)
  return OSCYank(l:text)
endfunction

function! OSCYankOperator() abort
  set operatorfunc=OSCYankOperatorCallback
  return 'g@'
endfunction

function! OSCYankVisual() abort
  let l:text = s:get_text('visual', visualmode())
  return OSCYank(l:text)
endfunction

function! OSCYankRegister(register) abort
  let l:text = getreg(a:register)
  return OSCYank(l:text)
endfunction

" -------------------- COMMANDS ----------------------------
command! -nargs=1 OSCYank call OSCYank('<args>')
command! -range OSCYankVisual call OSCYankVisual()
command! -register OSCYankRegister call OSCYankRegister('<reg>')

nnoremap <expr> <Plug>OSCYankOperator OSCYankOperator()
vnoremap <Plug>OSCYankVisual :OSCYankVisual<CR>
EOF
)

log "Applying managed configuration blocks"
mkdir -p "$VIM_PLUGIN_DIR" "$VIM_UNDO_DIR"

upsert_existing_managed_block "$PROFILE_FILE" "profile" "$PROFILE_CONTENT"
upsert_existing_managed_block "$BASH_PROFILE_FILE" "bash_profile" "$BASH_PROFILE_CONTENT"
upsert_existing_managed_block "$BASHRC_FILE" "bashrc" "$BASHRC_CONTENT"
upsert_existing_managed_block "$ZSHRC_FILE" "zshrc" "$ZSHRC_CONTENT"
upsert_managed_block "$FISH_CONFIG_FILE" "fish" "$FISH_CONFIG_CONTENT"
upsert_managed_block "$VIMRC_FILE" "vimrc" "$VIMRC_CONTENT" '"'
upsert_managed_block "$INPUTRC_FILE" "inputrc" "$INPUTRC_CONTENT"
write_managed_file "$OSCYANK_FILE" "$OSCYANK_PLUGIN_CONTENT"

if command -v git >/dev/null 2>&1; then
  log "Updating Git defaults"
  # Remove a hardcoded Git editor so Git inherits $EDITOR from ~/.profile.
  git config --global --unset-all core.editor >/dev/null 2>&1 || true
  git config --global init.defaultBranch main
  git config --global alias.lg "log --graph --all --decorate --pretty=format:'%C(blue)%h%Creset%C(yellow)%d%Creset %s %C(blue)%an%Creset %C(green)(%ar)%Creset'"
fi

log "Done. Open a new shell to pick up PATH and shell configuration changes."
log "If Vim is already open, restart it to load updated config/plugin."
