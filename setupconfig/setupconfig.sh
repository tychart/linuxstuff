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
#   - Synchronizes the portable scripts under scripts/ on every run.
#   - Optionally installs or updates compiled tools from each provider's latest
#     stable GitHub release, using setupconfig/release-assets.tsv to select the
#     matching OS, architecture, archive format, and member. Candidates are
#     validated and atomically installed into ~/.local/bin; incompatible rows
#     are skipped rather than forced onto a host.
#   - Adds shell integration for them to the managed ~/.bashrc block when
#     ~/.bashrc already exists: the y()
#     yazi wrapper, the zellij z alias, fzf keybindings/completion, and
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
#   - Interactive runs ask once whether to install all non-Fish optional tools,
#     skip them, or keep the existing per-tool prompts. The prompt also works
#     for curl-pipe-to-bash by reading /dev/tty. Fully non-interactive runs
#     skip optional tools and Fish unless their explicit flags are passed.
#
# Usage:
#   chmod +x setupconfig/setupconfig.sh
#   ./setupconfig/setupconfig.sh
#   ./setupconfig/setupconfig.sh --install-optional
#   ./setupconfig/setupconfig.sh --install-fish
#
#   or
#   curl -fsSL https://raw.githubusercontent.com/tychart/linuxstuff/main/setupconfig/setupconfig.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/tychart/linuxstuff/main/setupconfig/setupconfig.sh | bash -s -- --install-optional
#   curl -fsSL https://raw.githubusercontent.com/tychart/linuxstuff/main/setupconfig/setupconfig.sh | bash -s -- --install-fish

set -euo pipefail

SCRIPT_TAG="setupconfig"
readonly SCRIPT_TAG
# Single source of truth for the preferred editor written into ~/.profile.
DEFAULT_EDITOR="vim"
readonly DEFAULT_EDITOR

# Repository source configuration. Local checkouts are used directly; curl|bash
# runs fetch supporting files from the selected GitHub ref. Keep this code Bash
# 3.2-compatible so the same bootstrap works with macOS's system Bash.
SETUPCONFIG_REPO="tychart/linuxstuff"
SETUPCONFIG_REF="${SETUPCONFIG_REF:-main}"
SETUPCONFIG_SOURCE_ROOT=''
readonly SETUPCONFIG_REPO SETUPCONFIG_REF

find_local_source_root() {
  local script_path="${BASH_SOURCE[0]:-}"
  local candidate

  [[ -n $script_path && -f $script_path ]] || return 1
  candidate="$(cd "$(dirname "$script_path")" 2>/dev/null && pwd -P)" || return 1
  if [[ -d $candidate/setupconfig && -d $candidate/scripts ]]; then
    printf '%s' "$candidate"
    return 0
  fi
  if [[ -d $candidate/../setupconfig && -d $candidate/../scripts ]]; then
    candidate="$(cd "$candidate/.." 2>/dev/null && pwd -P)" || return 1
    printf '%s' "$candidate"
    return 0
  fi
  return 1
}

if SETUPCONFIG_SOURCE_ROOT="$(find_local_source_root)"; then
  readonly SETUPCONFIG_SOURCE_ROOT
else
  SETUPCONFIG_SOURCE_ROOT=''
  readonly SETUPCONFIG_SOURCE_ROOT
fi

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

# --install-optional selects all seven non-Fish compiled tools without
# prompting. Interactive runs otherwise offer All, None, or the existing
# per-tool selection flow. The manifest always enforces OS and architecture
# matching; incompatible binaries are never forced onto a host.
INSTALL_NICE_TO_HAVES=0
INSTALL_FISH=0

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

validate_repo_relative_path() {
  local path="$1"

  [[ -n $path && $path != /* && $path != *'..'* ]] || return 1
  case "$path" in
    *[!A-Za-z0-9._/+@-]*) return 1 ;;
  esac
}

fetch_repo_file() {
  local remote_path="$1"
  local destination="$2"
  local url

  validate_repo_relative_path "$remote_path" || {
    printf '[setup] Invalid repository-relative path: %s\n' "$remote_path" >&2
    return 1
  }

  if [[ -n $SETUPCONFIG_SOURCE_ROOT && -f $SETUPCONFIG_SOURCE_ROOT/$remote_path ]]; then
    cp "$SETUPCONFIG_SOURCE_ROOT/$remote_path" "$destination"
    return 0
  fi

  command -v curl >/dev/null 2>&1 || {
    printf '[setup] curl is required to fetch %s from %s\n' "$remote_path" "$SETUPCONFIG_REPO" >&2
    return 1
  }

  case "$SETUPCONFIG_REF" in
    ''|*[!A-Za-z0-9._/+@-]*)
      printf '[setup] Invalid SETUPCONFIG_REF: %s\n' "$SETUPCONFIG_REF" >&2
      return 1
      ;;
  esac

  url="https://raw.githubusercontent.com/${SETUPCONFIG_REPO}/${SETUPCONFIG_REF}/${remote_path}"
  curl -fL --retry 3 --max-time 30 -sS -o "$destination" "$url"
}

load_repo_content() {
  local var_name="$1"
  local remote_path="$2"
  local tmp

  tmp="$(mktemp)"
  register_temp_file "$tmp"
  if ! fetch_repo_file "$remote_path" "$tmp"; then
    printf '[setup] Could not load required setup source: %s\n' "$remote_path" >&2
    return 1
  fi
  [[ -s $tmp ]] || {
    printf '[setup] Required setup source is empty: %s\n' "$remote_path" >&2
    return 1
  }
  read_content "$var_name" <"$tmp"
}

read_content() {
  # Bash 3.2 can misparse heredocs inside $(...) command substitutions when
  # the heredoc body contains shell metacharacters. Read heredocs directly
  # instead; printf -v is available in Bash 3.2 and avoids eval.
  local var_name="$1"
  local line
  local content=''

  while IFS= read -r line; do
    if [[ -n $content ]]; then
      content="${content}"$'\n'
    fi
    content="${content}${line}"
  done

  printf -v "$var_name" '%s' "$content"
}

log() {
  printf '[setup] %s\n' "$*"
}

show_usage() {
  cat <<EOF
Usage:
  ./setupconfig/setupconfig.sh
  ./setupconfig/setupconfig.sh --install-optional
  ./setupconfig/setupconfig.sh --install-fish

  --install-optional   install/update all seven non-Fish compiled tools
                       without prompting; only matching OS/architectures run
  --install-fish       install/update Fish from its matching release asset
                       into ~/.local/bin without prompting
  --install-x64-binaries
                       deprecated compatibility alias for --install-optional;
                       architecture matching is still enforced
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
        INSTALL_NICE_TO_HAVES=1
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
    # stdin is not a terminal (for example, curl-pipe-to-bash feeds the
    # script through a pipe): prompt on the controlling terminal instead. If there
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
# Compiled tools are installed from their upstream GitHub releases according to
# setupconfig/release-assets.tsv. The portable osc52 helper is synchronized by
# the managed-script section below on every run and is not optional.
# ---------------------------------------------------------------------------

NICE_TO_HAVE_BIN_DIR="$HOME/.local/bin"
readonly NICE_TO_HAVE_BIN_DIR

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

# ---------------------------------------------------------------------------
# Managed portable scripts and third-party GitHub release assets
#
# Portable scripts are fetched from this repository and synchronized on every
# setup run. Compiled tools come from their upstream GitHub releases, selected
# by the manifest in setupconfig/release-assets.tsv. A per-tool state file
# avoids downloading a release again when neither its tag nor manifest row
# changed.
# ---------------------------------------------------------------------------

GITHUB_TAG_CACHE=''
CURRENT_PLATFORM_ARCH=''

is_macho_binary() {
  local magic
  magic="$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d '[:space:]')"
  case "$magic" in
    cffaedfe|feedfacf|cafebabe|cefaedfe|feedface|cafebabf) return 0 ;;
    *) return 1 ;;
  esac
}

is_valid_release_executable() {
  is_elf_binary "$1" || is_macho_binary "$1" || is_shebang_script "$1"
}

normalize_arch() {
  case "$1" in
    x86_64|amd64) printf 'x86_64' ;;
    aarch64|arm64) printf 'aarch64' ;;
    armv7*|arm) printf 'armv7' ;;
    *) printf '%s' "$1" ;;
  esac
}

is_termux() {
  [[ -n ${TERMUX_VERSION:-} ]] && return 0
  [[ -n ${PREFIX:-} && $PREFIX == */com.termux/* ]] && return 0
  return 1
}

platform_os() {
  if is_termux; then
    printf 'Termux'
  else
    uname -s 2>/dev/null || printf unknown
  fi
}

platform_arch() {
  normalize_arch "$(uname -m 2>/dev/null || printf unknown)"
}

release_tag_from_github_redirect() {
  local repository="$1"
  local latest_url="https://github.com/${repository}/releases/latest"
  local final_url
  local tag

  final_url="$(curl -fsSL --max-time 30 -o /dev/null -w '%{url_effective}' "$latest_url" 2>/dev/null)" || return 1
  case "$final_url" in
    */releases/tag/*) tag="${final_url##*/releases/tag/}" ;;
    *) return 1 ;;
  esac

  case "$tag" in
    ''|*[!A-Za-z0-9._/@+-]*) return 1 ;;
  esac
  printf '%s' "$tag"
}

release_tag_for_repo() {
  local repository="$1"
  local api_url="https://api.github.com/repos/${repository}/releases/latest"
  local tag
  local response

  if [[ -n $GITHUB_TAG_CACHE && -f $GITHUB_TAG_CACHE ]]; then
    tag="$(awk -F '\t' -v repo="$repository" '$1 == repo { print $2; exit }' "$GITHUB_TAG_CACHE")"
    if [[ -n $tag ]]; then
      printf '%s' "$tag"
      return 0
    fi
  fi

  response="$(mktemp)"
  register_temp_file "$response"
  if curl -fsSL --retry 3 --max-time 30 -sS -o "$response" "$api_url"; then
    tag="$(grep -Eo '"tag_name"[[:space:]]*:[[:space:]]*"[^"]+"' "$response" |
      head -n 1 |
      sed -E 's/.*"([^"]+)"$/\1/')"
  else
    tag=''
  fi
  rm -f "$response"

  # GitHub's API can be rate-limited or temporarily unavailable. The normal
  # releases/latest page redirects to the same stable tag without consuming
  # the REST API quota, so use it as a fallback before giving up.
  if [[ -z $tag ]]; then
    tag="$(release_tag_from_github_redirect "$repository" 2>/dev/null)" || tag=''
  fi

  case "$tag" in
    ''|*[!A-Za-z0-9._/@+-]*) return 1 ;;
  esac

  if [[ -n $GITHUB_TAG_CACHE ]]; then
    printf '%s\t%s\n' "$repository" "$tag" >> "$GITHUB_TAG_CACHE"
  fi
  printf '%s' "$tag"
}

manifest_value() {
  local value="$1"
  local tag="$2"
  local arch="$3"
  local version="${tag#v}"

  value="${value//\{tag\}/$tag}"
  value="${value//\{version\}/$version}"
  value="${value//\{arch\}/$arch}"
  printf '%s' "$value"
}

validate_archive_member() {
  local member="$1"

  [[ -n $member && $member != /* && $member != *'..'* ]] || return 1
  case "$member" in
    *[!A-Za-z0-9._/+@-]*) return 1 ;;
  esac
}

extract_release_member() {
  local archive="$1"
  local format="$2"
  local member="$3"
  local destination="$4"

  if [[ $format == raw ]]; then
    cp "$archive" "$destination"
    return $?
  fi

  validate_archive_member "$member" || {
    log "Unsafe archive member '$member'; refusing to extract it"
    return 1
  }

  case "$format" in
    tar)
      tar -tf "$archive" 2>/dev/null | grep -F -x "$member" >/dev/null 2>&1 || {
        log "Archive does not contain exact member '$member'"
        return 1
      }
      tar -xOf "$archive" "$member" > "$destination"
      ;;
    zip)
      command -v unzip >/dev/null 2>&1 || {
        log "unzip is required for archive member '$member'; skipping"
        return 1
      }
      unzip -p "$archive" "$member" > "$destination"
      ;;
    *)
      log "Unsupported release format '$format'"
      return 1
      ;;
  esac
}

install_repo_executable() {
  local remote_path="$1"
  local destination="$2"
  local label="$3"
  local dir
  local tmp
  local version

  dir="$(dirname "$destination")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.${label}.part.XXXXXX")"
  register_temp_file "$tmp"

  if ! fetch_repo_file "$remote_path" "$tmp"; then
    rm -f "$tmp"
    log "Failed to fetch managed executable '$label'; leaving any existing installation untouched"
    return 0
  fi
  if ! is_shebang_script "$tmp"; then
    rm -f "$tmp"
    log "Managed executable '$label' has no shebang; not installing"
    return 0
  fi

  chmod 755 "$tmp"
  if ! version="$("$tmp" --version 2>/dev/null | head -n 1)" || [[ -z $version ]]; then
    rm -f "$tmp"
    log "Managed executable '$label' failed its --version smoke test; not installing"
    return 0
  fi

  if [[ -f $destination ]] && cmp -s "$destination" "$tmp"; then
    rm -f "$tmp"
    chmod 755 "$destination" 2>/dev/null || true
    log "Managed executable '$label' unchanged ($destination)"
    return 0
  fi

  mv -f "$tmp" "$destination"
  version="$($destination --version 2>/dev/null | head -n 1)"
  log "Installed managed executable '$label' -> $destination ($version)"
}

PENDING_TOOL_NAMES=()
PENDING_REPOS=()
PENDING_TAGS=()
PENDING_ASSETS=()
PENDING_FORMATS=()
PENDING_MEMBERS=()
PENDING_VERSION_ARGS=()
PENDING_ACTIONS=()
PENDING_INSTALLED_VERSIONS=()
PENDING_TARGET_VERSIONS=()

reset_pending_tools() {
  PENDING_TOOL_NAMES=()
  PENDING_REPOS=()
  PENDING_TAGS=()
  PENDING_ASSETS=()
  PENDING_FORMATS=()
  PENDING_MEMBERS=()
  PENDING_VERSION_ARGS=()
  PENDING_ACTIONS=()
  PENDING_INSTALLED_VERSIONS=()
  PENDING_TARGET_VERSIONS=()
}

normalize_version() {
  # Extract the first semantic version without Bash 4 string features. The
  # explicit true keeps set -euo pipefail from treating a version-less output
  # as a fatal installer error.
  printf '%s\n' "$1" |
    grep -Eo '[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*' |
    head -n 1 || true
}

read_installed_version() {
  local executable="$1"
  local version_argument="$2"
  local output

  [[ -x $executable ]] || return 1
  output="$($executable "$version_argument" 2>/dev/null)" || return 1
  [[ -n $output ]] || return 1
  normalize_version "$output"
}

append_pending_tool() {
  local index=${#PENDING_TOOL_NAMES[@]}

  PENDING_TOOL_NAMES[$index]="$1"
  PENDING_REPOS[$index]="$2"
  PENDING_TAGS[$index]="$3"
  PENDING_ASSETS[$index]="$4"
  PENDING_FORMATS[$index]="$5"
  PENDING_MEMBERS[$index]="$6"
  PENDING_VERSION_ARGS[$index]="$7"
  PENDING_ACTIONS[$index]="$8"
  PENDING_INSTALLED_VERSIONS[$index]="$9"
  PENDING_TARGET_VERSIONS[${index}]="${10}"
}

preflight_manifest_tool() {
  local tool="$1"
  local manifest_file="$2"
  local target_os="$3"
  local target_arch="$4"
  local row_tool row_repo row_os row_arch row_asset row_format row_member row_version_arg
  local tag target_version installed_version action destination
  local found=0

  while IFS="$(printf '\t')" read -r row_tool row_repo row_os row_arch row_asset row_format row_member row_version_arg; do
    [[ -z $row_tool || ${row_tool#\#} != "$row_tool" ]] && continue
    [[ $row_tool == "$tool" && $row_os == "$target_os" && $row_arch == "$target_arch" ]] || continue
    found=1

    if ! tag="$(release_tag_for_repo "$row_repo")"; then
      log "Could not resolve the latest GitHub release for $row_repo; leaving $tool unchanged"
      return 0
    fi
    target_version="$(normalize_version "$tag")"
    if [[ -z $target_version ]]; then
      log "Could not determine a semantic version from release tag '$tag' for $tool; leaving it unchanged"
      return 0
    fi

    destination="$NICE_TO_HAVE_BIN_DIR/$tool"
    action=install
    installed_version=''
    if [[ -e $destination || -L $destination ]]; then
      action=update
      if is_valid_release_executable "$destination"; then
        installed_version="$(read_installed_version "$destination" "$row_version_arg")" || installed_version=''
      fi
      if [[ -n $installed_version && $installed_version == "$target_version" ]]; then
        log "$tool is current ($destination, version $installed_version)"
        return 0
      fi
      [[ -n $installed_version ]] || installed_version='unknown'
    fi

    append_pending_tool \
      "$row_tool" "$row_repo" "$tag" "$row_asset" "$row_format" \
      "$row_member" "$row_version_arg" "$action" "$installed_version" \
      "$target_version"
    return 0
  done < "$manifest_file"

  [[ $found -eq 1 ]] || log "No GitHub release asset is configured for $tool on ${target_os}/${target_arch}; skipping"
}

print_pending_summary() {
  local i=0
  local action tool installed target

  [[ ${#PENDING_TOOL_NAMES[@]} -gt 0 ]] || return 0
  log "Optional tools needing action:"
  while [[ $i -lt ${#PENDING_TOOL_NAMES[@]} ]]; do
    action="${PENDING_ACTIONS[$i]}"
    tool="${PENDING_TOOL_NAMES[$i]}"
    installed="${PENDING_INSTALLED_VERSIONS[$i]}"
    target="${PENDING_TARGET_VERSIONS[$i]}"
    if [[ $action == install ]]; then
      log "  Install $tool $target"
    else
      log "  Update $tool ${installed} -> ${target}"
    fi
    i=$((i + 1))
  done
}

confirm_pending_tool() {
  local index="$1"
  local action="${PENDING_ACTIONS[$index]}"
  local tool="${PENDING_TOOL_NAMES[$index]}"
  local installed="${PENDING_INSTALLED_VERSIONS[$index]}"
  local target="${PENDING_TARGET_VERSIONS[$index]}"
  local prompt

  if [[ $action == install ]]; then
    prompt="Install $tool $target?"
  else
    prompt="Update $tool ${installed} -> ${target}?"
  fi
  confirm_prompt "$prompt"
}

install_pending_tool() {
  local index="$1"
  local tool="${PENDING_TOOL_NAMES[$index]}"
  local repository="${PENDING_REPOS[$index]}"
  local tag="${PENDING_TAGS[$index]}"
  local asset_template="${PENDING_ASSETS[$index]}"
  local format="${PENDING_FORMATS[$index]}"
  local member_template="${PENDING_MEMBERS[$index]}"
  local version_argument="${PENDING_VERSION_ARGS[$index]}"
  local action="${PENDING_ACTIONS[$index]}"
  local target_version="${PENDING_TARGET_VERSIONS[$index]}"
  local asset member url destination
  local asset_tmp candidate candidate_output candidate_version
  local version version_output action_label

  asset="$(manifest_value "$asset_template" "$tag" "$CURRENT_PLATFORM_ARCH")"
  member="$(manifest_value "$member_template" "$tag" "$CURRENT_PLATFORM_ARCH")"
  destination="$NICE_TO_HAVE_BIN_DIR/$tool"
  mkdir -p "$NICE_TO_HAVE_BIN_DIR"
  asset_tmp="$(mktemp "$NICE_TO_HAVE_BIN_DIR/.${tool}.asset.XXXXXX")"
  candidate="$(mktemp "$NICE_TO_HAVE_BIN_DIR/.${tool}.candidate.XXXXXX")"
  register_temp_file "$asset_tmp"
  register_temp_file "$candidate"
  url="https://github.com/${repository}/releases/download/${tag}/${asset}"

  if ! curl -fL --retry 3 --max-time 120 -sS -o "$asset_tmp" "$url"; then
    rm -f "$asset_tmp" "$candidate"
    log "Failed to download $tool from $url; leaving the existing executable untouched"
    return 0
  fi
  if ! extract_release_member "$asset_tmp" "$format" "$member" "$candidate" ||
     [[ ! -s $candidate ]] || ! is_valid_release_executable "$candidate"; then
    rm -f "$asset_tmp" "$candidate"
    log "Downloaded $tool did not contain a valid executable; leaving the existing executable untouched"
    return 0
  fi

  chmod 755 "$candidate"
  candidate_output="$($candidate "$version_argument" 2>/dev/null)" || candidate_output=''
  candidate_version="$(normalize_version "$candidate_output")"
  if [[ -z $candidate_output || -z $candidate_version || $candidate_version != "$target_version" ]]; then
    rm -f "$asset_tmp" "$candidate"
    log "Downloaded $tool reported version '${candidate_version:-unknown}', expected $target_version; leaving the existing executable untouched"
    return 0
  fi

  mv -f "$candidate" "$destination"
  rm -f "$asset_tmp"
  version_output="$($destination "$version_argument" 2>/dev/null)" || version_output=''
  version="$(normalize_version "$version_output")"
  if [[ $action == install ]]; then
    action_label=Installed
  else
    action_label=Updated
  fi
  log "$action_label $tool -> $destination (${version:-$target_version}; release $tag)"
}

ensure_manifest_tools() {
  local auto_install="$1"
  local prompt_style="$2"
  shift 2
  local manifest_file
  local os arch tool i mode

  reset_pending_tools
  command -v curl >/dev/null 2>&1 || {
    log "curl is required for GitHub release assets; skipping compiled tools"
    return 0
  }

  manifest_file="$(mktemp)"
  register_temp_file "$manifest_file"
  if ! fetch_repo_file "setupconfig/release-assets.tsv" "$manifest_file"; then
    rm -f "$manifest_file"
    log "Could not load the release manifest; skipping compiled tools"
    return 0
  fi

  os="$(platform_os)"
  arch="$(platform_arch)"
  CURRENT_PLATFORM_ARCH="$arch"
  GITHUB_TAG_CACHE="$(mktemp)"
  register_temp_file "$GITHUB_TAG_CACHE"

  for tool in "$@"; do
    preflight_manifest_tool "$tool" "$manifest_file" "$os" "$arch"
  done

  if [[ ${#PENDING_TOOL_NAMES[@]} -eq 0 ]]; then
    return 0
  fi
  print_pending_summary

  if [[ $auto_install == 1 ]]; then
    i=0
    while [[ $i -lt ${#PENDING_TOOL_NAMES[@]} ]]; do
      install_pending_tool "$i"
      i=$((i + 1))
    done
    return 0
  fi

  if ! has_prompt_tty; then
    log "No interactive terminal; skipping these tools."
    return 0
  fi

  if [[ $prompt_style == single ]]; then
    i=0
    while [[ $i -lt ${#PENDING_TOOL_NAMES[@]} ]]; do
      if confirm_pending_tool "$i"; then
        install_pending_tool "$i"
      else
        log "Skipping ${PENDING_TOOL_NAMES[$i]}"
      fi
      i=$((i + 1))
    done
    return 0
  fi

  if ! mode="$(prompt_optional_tool_mode)"; then
    log "No interactive terminal; skipping these tools."
    return 0
  fi

  case "$mode" in
    all)
      i=0
      while [[ $i -lt ${#PENDING_TOOL_NAMES[@]} ]]; do
        install_pending_tool "$i"
        i=$((i + 1))
      done
      ;;
    individual)
      i=0
      while [[ $i -lt ${#PENDING_TOOL_NAMES[@]} ]]; do
        if confirm_pending_tool "$i"; then
          install_pending_tool "$i"
        else
          log "Skipping ${PENDING_TOOL_NAMES[$i]}"
        fi
        i=$((i + 1))
      done
      ;;
    none)
      log "Skipping all optional tools at user request"
      ;;
  esac
}

has_prompt_tty() {
  [[ -t 0 ]] || ( exec 3< /dev/tty ) 2>/dev/null
}

# Portable scripts are not optional: they are repository-managed source and are
# synchronized even on ARM, Darwin, Termux, and unsupported platforms.
ensure_nice_to_haves() {
  install_repo_executable "scripts/osc52" "$NICE_TO_HAVE_BIN_DIR/osc52" "osc52"
  ensure_manifest_tools "$INSTALL_NICE_TO_HAVES" group fzf bat eza rg ya yazi zellij
}

ensure_fish() {
  if [[ $INSTALL_FISH == 1 ]]; then
    ensure_manifest_tools 1 single fish
    return 0
  fi

  ensure_manifest_tools 0 single fish
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

  if ! tool_is_present "$tool"; then
    log "Skipping ${tool} config (${dest}): ${tool} binary not installed"
    return 0
  fi

  dir="$(dirname "$dest")"
  mkdir -p "$dir"

  # Remove stale partial downloads from any previously interrupted run.
  shopt -s nullglob
  rm -f "$dir"/.*.config.part.*
  shopt -u nullglob

  tmp="$(mktemp "$dir/.${tool}.config.part.XXXXXX")"
  register_temp_file "$tmp"

  if ! fetch_repo_file "$remote_path" "$tmp"; then
    rm -f "$tmp"
    log "Failed to fetch managed config ${remote_path}; leaving any existing config untouched"
    return 0
  fi

  if [[ ! -s $tmp ]]; then
    rm -f "$tmp"
    log "Managed config ${remote_path} is empty; not installing"
    return 0
  fi

  # Cheap guard against HTML error pages served with a 200 status; none of
  # these config formats starts with '<'.
  if [[ $(head -c 1 "$tmp") == '<' ]]; then
    rm -f "$tmp"
    log "Managed config ${remote_path} looks like an HTML error page; not installing"
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
  read_content SYSTEM_BASHRC_BLOCK <<EOF
# Source distro-provided Bash defaults before user customizations.
if [ -r "${SYSTEM_BASHRC_PATH}" ]; then
  . "${SYSTEM_BASHRC_PATH}"
fi
EOF
else
  log "No known system Bash rc for this OS; leaving any existing ~/.bashrc fully self-managed"
fi

load_repo_content PROFILE_CONTENT "setupconfig/managed/profile.sh"
PROFILE_CONTENT="${PROFILE_CONTENT//__DEFAULT_EDITOR__/$DEFAULT_EDITOR}"

load_repo_content BASH_PROFILE_CONTENT "setupconfig/managed/bash_profile.sh"

load_repo_content ZSHRC_CONTENT "setupconfig/managed/zshrc.sh"

load_repo_content BASHRC_CONTENT "setupconfig/managed/bashrc.sh"
BASHRC_CONTENT="${BASHRC_CONTENT//__DEFAULT_EDITOR__/$DEFAULT_EDITOR}"
BASHRC_CONTENT="${BASHRC_CONTENT/__SYSTEM_BASHRC_BLOCK__/$SYSTEM_BASHRC_BLOCK}"

load_repo_content VIMRC_CONTENT "setupconfig/managed/vimrc.vim"

load_repo_content FISH_CONFIG_CONTENT "fish/config.fish"
FISH_CONFIG_CONTENT="${FISH_CONFIG_CONTENT//__DEFAULT_EDITOR__/$DEFAULT_EDITOR}"

load_repo_content INPUTRC_CONTENT "setupconfig/managed/inputrc"

# Install a small custom Vim plugin so copy works reliably in SSH, tmux, and other remote terminals.
# It uses OSC 52 escape sequences instead of depending on xclip/pbcopy or a local GUI clipboard.
load_repo_content OSCYANK_PLUGIN_CONTENT "setupconfig/files/oscyank.vim"

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
