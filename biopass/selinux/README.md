# biopass + oo7: keyring not unlocked at login (SELinux)

Symptom: after a biopass (face/fingerprint) login the login keyring is locked,
so Chromium/Obsidian/seahorse prompt for the keyring password, and
gcr-ssh-agent cannot fetch stored SSH passphrases.

Cause: biopass unseals the login password from the TPM at auth time to feed
PAM_AUTHTOK. The helper runs in SELinux domain xdm_t, and targeted policy has
no rule allowing xdm_t to use tpm_device_t (/dev/tpmrm0), so it fails with
ECDSA/"no TPM to unlock the keyring". pam_oo7 then has no AUTHTOK and
oo7-daemon starts with the login collection locked.

Evidence:
  journalctl -b -o cat | grep -e 'avc:  denied' -e 'no TPM'
  ~/.local/share/com.ticklab.biopass/logs/<date>.log
  journalctl -b -o cat | grep 'PAM_AUTHTOK is null'

Fix: install the local policy module
  sudo semodule -i ~/biopass-selinux/biopass_tpm.pp
Verify (after logout/login, before opening any app):
  busctl --user get-property org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/login \
    org.freedesktop.Secret.Collection Locked     # want: b false

Rebuild from scratch if AVCs change:
  journalctl -b -o cat | grep 'avc:  denied' | grep biopass | audit2allow -M biopass_tpm
  sudo semodule -i biopass_tpm.pp

## Round 2 (2026-11-11 19:40)

The first module only allowed `{ read write }` (all audit2allow saw). After
install the denial moved to `{ open }`, so the policy now allows
`{ open read write ioctl getattr }`. Re-install:

  sudo semodule -i ~/biopass-selinux/biopass_tpm.pp

No reboot needed - SELinux policy reloads immediately; just log out to GDM and
log back in with biopass, then run ~/biopass-selinux/verify-keyring.sh.

## FINAL STATE (2026-11-11 20:06) — working

Both modules installed; a biopass (face) login at GDM now unlocks the login
keyring and gcr-ssh-agent unlocks ~/.ssh/homesshkey with no prompt.

  biopass_tpm.pp     allow xdm_t tpm_device_t:chr_file { open read write ioctl getattr }
  biopass_shadow.pp  allow xdm_t shadow_t:file { getattr open read }

Health check after any biopass / selinux-policy / oo7 update:

  ~/biopass-selinux/verify-keyring.sh

Expect: Locked = b false, no "no TPM"/"cannot check" lines, no AVCs, ssh OK.
Remove the modules with:  sudo semodule -r biopass_tpm biopass_shadow
