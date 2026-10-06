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
run_setup >/dev/null
[ "$(HOME="$TEST_HOME" "$TEST_HOME/.local/bin/osc52" --version)" = 'osc52 2.0.0' ]

checksum_before="$(cksum "$TEST_HOME/.local/bin/osc52")"
run_setup >"$TEST_HOME/rerun.log"
checksum_after="$(cksum "$TEST_HOME/.local/bin/osc52")"
[ "$checksum_before" = "$checksum_after" ]
grep -q "Managed executable 'osc52' unchanged" "$TEST_HOME/rerun.log"

printf 'setupconfig tests passed\n'
