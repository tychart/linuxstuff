#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd -P)"
PATH_WITHOUT_USER_TOOLS="/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

command -v git >/dev/null 2>&1 || { printf 'SKIP: git is unavailable\n'; exit 0; }
command -v vim >/dev/null 2>&1 || { printf 'SKIP: vim is unavailable\n'; exit 0; }

bash -n "$ROOT_DIR/setupconfig/setupconfig.sh"
sh -n "$ROOT_DIR/scripts/osc52"

[ "$("$ROOT_DIR/scripts/osc52" --version)" = 'osc52 2.0.0' ]
[ "$(OSC52_TTY=- "$ROOT_DIR/scripts/osc52" --text hi)" = "$(printf '\033]52;c;aGk=\007')" ]

if OSC52_TTY=- "$ROOT_DIR/scripts/osc52" one two >/dev/null 2>&1; then
  printf 'FAIL: osc52 accepted multiple arguments\n' >&2
  exit 1
fi

TEST_HOME="$(mktemp -d)"
TEST_BIN="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME" "$TEST_BIN"' EXIT
# Keep the test independent of any globally installed yazi package. The setup
# script will exercise its config guards, while the fake ya avoids a network
# package install for the optional theme.
printf '#!/bin/sh\nexit 0\n' > "$TEST_BIN/yazi"
printf '#!/bin/sh\nexit 1\n' > "$TEST_BIN/ya"
chmod 755 "$TEST_BIN/yazi" "$TEST_BIN/ya"

run_setup() {
  HOME="$TEST_HOME" \
  XDG_CONFIG_HOME="$TEST_HOME/config" \
  XDG_STATE_HOME="$TEST_HOME/state" \
  PATH="$TEST_BIN:$PATH_WITHOUT_USER_TOOLS" \
  bash "$ROOT_DIR/setupconfig/setupconfig.sh" "$@"
}

mkdir -p "$TEST_HOME/.local/bin"
printf '#!/bin/sh\nprintf old\\n\n' > "$TEST_HOME/.local/bin/osc52"
chmod 755 "$TEST_HOME/.local/bin/osc52"
run_setup >"$TEST_HOME/first-run.log"
[ "$(HOME="$TEST_HOME" "$TEST_HOME/.local/bin/osc52" --version)" = 'osc52 2.0.0' ]

# ALWAYS_CREATE_BLOCKS: a fresh HOME must get these managed files created,
# including the Fish config's missing parent directories.
for created in \
  "$TEST_HOME/.config/setupconfig/env.sh" \
  "$TEST_HOME/.bash_profile" \
  "$TEST_HOME/.bashrc" \
  "$TEST_HOME/config/fish/config.fish" \
  "$TEST_HOME/.vimrc" \
  "$TEST_HOME/.inputrc"; do
  [ -s "$created" ] || { printf 'FAIL: expected %s to be created\n' "$created" >&2; exit 1; }
done
grep -q "Created managed block 'env' in $TEST_HOME/.config/setupconfig/env.sh" "$TEST_HOME/first-run.log"
grep -q "setupconfig:bashrc >>>" "$TEST_HOME/.bashrc"
# A block outside ALWAYS_CREATE_BLOCKS must not be created from nothing.
[ ! -e "$TEST_HOME/.zshrc" ]
[ ! -e "$TEST_HOME/.profile" ]
grep -q "Skipping managed block 'profile': $TEST_HOME/.profile does not exist" "$TEST_HOME/first-run.log"

# One environment file, sourced by every shell that exists on this host.
for consumer in "$TEST_HOME/.bashrc" "$TEST_HOME/config/fish/config.fish"; do
  grep -q 'setupconfig/env.sh' "$consumer" || {
    printf 'FAIL: %s does not source the shared environment\n' "$consumer" >&2
    exit 1
  }
done
# Nothing else may redefine the values; that is what the shared file is for.
[ "$(grep -l 'EDITOR' "$ROOT_DIR"/setupconfig/managed/*.sh | wc -l)" -eq 1 ]

# A Bash login shell must see the shared values.
BASH_BIN="$(command -v bash)"
login_env="$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/config" \
  PATH="$PATH_WITHOUT_USER_TOOLS" "$BASH_BIN" -lc 'printf "%s|%s" "$EDITOR" "$PATH"')"
[ "${login_env%%|*}" = 'vim' ]
login_path="${login_env#*|}"
case "$login_path" in
  "$TEST_HOME/.local/bin:$TEST_HOME/.bun/bin:$TEST_HOME/bin:"*) ;;
  *) printf 'FAIL: unexpected login PATH: %s\n' "$login_path" >&2; exit 1 ;;
esac
# Sourcing the environment more than once would repeat these entries.
count_local_bin() {
  printf '%s' "$1" | tr ':' '\n' | grep -c -x -F "$TEST_HOME/.local/bin"
}
[ "$(count_local_bin "$login_path")" -eq 1 ] || {
  printf 'FAIL: environment applied more than once: %s\n' "$login_path" >&2
  exit 1
}

# Existing dotfiles often source each other repeatedly (a ~/.bash_profile that
# sources ~/.profile and ~/.bashrc more than once is common), so repeated
# sourcing must not grow PATH.
twice_path="$(HOME="$TEST_HOME" PATH="$PATH_WITHOUT_USER_TOOLS" \
  "$BASH_BIN" -c '. "$HOME/.bashrc"; . "$HOME/.bashrc"; printf %s "$PATH"')"
[ "$(count_local_bin "$twice_path")" -eq 1 ] || {
  printf 'FAIL: repeated source duplicated PATH: %s\n' "$twice_path" >&2
  exit 1
}

# A nested login shell inherits the values and must not prepend them again.
nested_path="$(HOME="$TEST_HOME" PATH="$PATH_WITHOUT_USER_TOOLS" \
  "$BASH_BIN" -lc 'bash -lc "echo \$PATH"')"
[ "$(count_local_bin "$nested_path")" -eq 1 ] || {
  printf 'FAIL: nested login shell duplicated PATH: %s\n' "$nested_path" >&2
  exit 1
}

# Fish must read the same file and reach the same PATH prefix.
FISH_BIN="$(command -v fish || true)"
if [ -n "$FISH_BIN" ]; then
  fish_env="$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/config" \
    PATH="$PATH_WITHOUT_USER_TOOLS" "$FISH_BIN" -c 'printf "%s|%s" "$EDITOR" "$PATH[1]"')"
  [ "${fish_env%%|*}" = 'vim' ]
  [ "${fish_env#*|}" = "$TEST_HOME/.local/bin" ]
  # Fish inherits the marker, so re-reading its config must not repeat entries.
  fish_cfg="$TEST_HOME/config/fish/config.fish"
  fish_once="$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/config" \
    PATH="$PATH_WITHOUT_USER_TOOLS" "$FISH_BIN" -c "source $fish_cfg; string join : \$PATH")"
  fish_thrice="$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/config" \
    PATH="$PATH_WITHOUT_USER_TOOLS" "$FISH_BIN" -c "source $fish_cfg; source $fish_cfg; source $fish_cfg; string join : \$PATH")"
  [ "$fish_once" = "$fish_thrice" ]
  [ "$(count_local_bin "$fish_once")" -eq 1 ]
  # The Fish helper that skips the handoff must exist and export the variable.
  bashonly_out="$(HOME="$TEST_HOME" XDG_CONFIG_HOME="$TEST_HOME/config" \
    PATH="$PATH_WITHOUT_USER_TOOLS" "$FISH_BIN" -i -c \
    'bashonly -c "printf %s \$SETUPCONFIG_NO_FISH"' 2>/dev/null | tail -1)"
  [ "$bashonly_out" = '1' ] || {
    printf 'FAIL: fish bashonly helper did not export SETUPCONFIG_NO_FISH (%s)\n' \
      "$bashonly_out" >&2
    exit 1
  }
fi

# Fish hands interactive Bash over to Fish; a stub proves both sides of the
# switch without depending on Fish being installed.
STUB_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_HOME" "$TEST_BIN" "$STUB_DIR"' EXIT
printf '#!/bin/sh\necho HANDOFF_TO_FISH\n' > "$STUB_DIR/fish"
chmod 755 "$STUB_DIR/fish"
handoff="$(HOME="$TEST_HOME" PATH="$STUB_DIR:$PATH_WITHOUT_USER_TOOLS" \
  "$BASH_BIN" -ic 'printf STAYED_IN_BASH' 2>/dev/null | tail -1)"
[ "$handoff" = 'HANDOFF_TO_FISH' ] || {
  printf 'FAIL: interactive Bash did not hand off to Fish (got %s)\n' "$handoff" >&2
  exit 1
}
no_handoff="$(HOME="$TEST_HOME" SETUPCONFIG_NO_FISH=1 PATH="$STUB_DIR:$PATH_WITHOUT_USER_TOOLS" \
  "$BASH_BIN" -ic 'printf STAYED_IN_BASH' 2>/dev/null | tail -1)"
[ "$no_handoff" = 'STAYED_IN_BASH' ] || {
  printf 'FAIL: SETUPCONFIG_NO_FISH did not keep Bash (got %s)\n' "$no_handoff" >&2
  exit 1
}

checksum_before="$(cksum "$TEST_HOME/.local/bin/osc52")"
run_setup >"$TEST_HOME/rerun.log"
checksum_after="$(cksum "$TEST_HOME/.local/bin/osc52")"
[ "$checksum_before" = "$checksum_after" ]
grep -q "Managed executable 'osc52' unchanged" "$TEST_HOME/rerun.log"
grep -q "Managed block 'env' unchanged in $TEST_HOME/.config/setupconfig/env.sh" "$TEST_HOME/rerun.log"

# An existing ~/.profile (every default Ubuntu install has one) is extended in
# place, and its user content is preserved; nothing is created from nothing.
printf '# my own login setup\nexport MY_PROFILE_VAR=kept\n' > "$TEST_HOME/.profile"
run_setup > "$TEST_HOME/profile.log"
grep -q "setupconfig:profile >>>" "$TEST_HOME/.profile"
grep -q "MY_PROFILE_VAR=kept" "$TEST_HOME/.profile"
grep -q 'setupconfig/env.sh' "$TEST_HOME/.profile"
[ "$(grep -c "setupconfig:profile >>>" "$TEST_HOME/.profile")" -eq 1 ]
[ ! -e "$TEST_HOME/.zshrc" ]

# An existing ~/.zshrc gets the shared environment and the same Fish handoff as
# ~/.bashrc. The block is POSIX, so its decision logic can be exercised with sh
# even when no zsh binary is installed.
printf '# my zsh setup\nbindkey -e\n' > "$TEST_HOME/.zshrc"
run_setup > "$TEST_HOME/zsh.log"
grep -q "setupconfig:zshrc >>>" "$TEST_HOME/.zshrc"
grep -q "bindkey -e" "$TEST_HOME/.zshrc"
zsh_handoff="$(HOME="$TEST_HOME" PATH="$STUB_DIR:$PATH_WITHOUT_USER_TOOLS" \
  /bin/sh -c '. "$HOME/.zshrc"; printf STAYED_IN_ZSH' 2>/dev/null | tail -1)"
[ "$zsh_handoff" = 'HANDOFF_TO_FISH' ] || {
  printf 'FAIL: ~/.zshrc did not hand off to Fish (got %s)\n' "$zsh_handoff" >&2
  exit 1
}
zsh_stay="$(HOME="$TEST_HOME" SETUPCONFIG_NO_FISH=1 PATH="$STUB_DIR:$PATH_WITHOUT_USER_TOOLS" \
  /bin/sh -c '. "$HOME/.zshrc"; printf STAYED_IN_ZSH' 2>/dev/null | tail -1)"
[ "$zsh_stay" = 'STAYED_IN_ZSH' ] || {
  printf 'FAIL: SETUPCONFIG_NO_FISH did not keep Zsh (got %s)\n' "$zsh_stay" >&2
  exit 1
}

printf 'setupconfig tests passed\n'
