#!/bin/bash
echo "== keyring lock state (want: b false) =="
busctl --user get-property org.freedesktop.secrets \
  /org/freedesktop/secrets/collection/login \
  org.freedesktop.Secret.Collection Locked 2>&1
echo
echo "== pam_oo7 / gkr-pam for the last login (want: no 'null') =="
journalctl -b -o short 2>/dev/null | grep -E "PAM_AUTHTOK|gkr-pam|pam_oo7|biopass" | grep -v "audit\[" | tail -8
echo
echo "== biopass log, this boot (want: no 'no TPM' / 'cannot check' after login) =="
grep -iE "no TPM|cannot check|unreadable|malformed|hand the keyring" \
  ~/.local/share/com.ticklab.biopass/logs/$(date +%F).log 2>/dev/null | tail -4 || echo "  clean"
echo
echo "== SELinux denials this boot (want: none) =="
journalctl -b -o cat 2>/dev/null | grep "avc:  denied" || echo "  none"
echo
echo "== oo7-daemon start / credential pickup =="
systemctl --user show oo7-daemon.service -p ActiveEnterTimestamp
journalctl -b -o cat 2>/dev/null | grep -i "oo7-daemon" | head -6
echo
echo "== ssh with stored passphrase (want: ssh OK, no prompt) =="
if timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=6 tychart@192.168.10.35 true 2>/dev/null; then
  echo "  ssh OK"
else
  echo "  ssh FAILED"
fi
