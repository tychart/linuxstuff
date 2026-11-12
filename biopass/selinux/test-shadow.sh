#!/bin/bash
set -u
T=/usr/local/bin/getent-xdm
cleanup() { sudo rm -f "$T"; }
trap cleanup EXIT

probe() { # $1 = label, rest = command
  local label="$1"; shift
  local out rc
  out=$("$@" 2>&1); rc=$?
  echo "--- $label: exit=$rc"
  echo "$out" | cut -d: -f1 | sed 's/^/    /'
}

echo "=== baseline: root, unconfined_t ==="
probe unconfined sudo getent shadow tychart

echo
echo "=== target: root, xdm_t (biopass-helper's login-screen domain) ==="
sudo install -o root -g root -m 755 /usr/bin/getent "$T"
sudo chcon -t xdm_exec_t "$T"
probe xdm_t sudo runcon system_u:system_r:xdm_t:s0-s0:c0.c1023 "$T" shadow tychart

echo
echo "=== biopass_shadow module installed? ==="
sudo semodule -l 2>/dev/null | grep -i biopass || echo "  (not listed / needs root)"
