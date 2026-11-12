# Biopass + oo7: login keyring stays locked (SELinux)

Local SELinux policy needed for `biopass`'s "Keyring Unlock" feature on Fedora
(RHEL family) with SELinux enforcing. See the parent notes:
[Fedora45-Install-Notes.md](../Fedora45-Install-Notes.md#selinux-policy-for-tpm--shadow).

Upstream report: [phucvinh57/biopass#252](https://github.com/phucvinh57/biopass/issues/252)

## Symptom

Biometric login at GDM works, but the login keyring is still locked, so
Chromium/Electron apps and seahorse prompt for the keyring password.

```bash
busctl --user get-property org.freedesktop.secrets \
  /org/freedesktop/secrets/collection/login \
  org.freedesktop.Secret.Collection Locked      # b true = broken
```

## Cause

Biopass 1.5.1 ships no SELinux policy. Its helper runs in GDM's `xdm_t` domain
and needs two things that Fedora's targeted policy does not allow:

| Rule | Without it |
| --- | --- |
| `xdm_t` → `tpm_device_t:chr_file` (`/dev/tpmrm0`) | `Biopass: no TPM to unlock the keyring` + an AVC on `tpmrm0` |
| `xdm_t` → `shadow_t:file` (`/etc/shadow`) | `Biopass: cannot check the saved keyring password (2)` = `PasswordCheck::NoLocalAccount` |

Either failure means `PAM_AUTHTOK` is never set, so `pam_oo7` has nothing to
hand to `oo7-daemon` and the collection stays locked.

The `shadow_t` denial is **`dontaudit`ed**, so it never shows up in
`journalctl | grep avc` — `test-shadow.sh` probes it directly.

## Install

```bash
cd biopass/selinux
for m in biopass_tpm biopass_shadow; do
  checkmodule -M -m -o "$m.mod" "$m.te"
  semodule_package -o "$m.pp" -m "$m.mod"
  sudo semodule -i "$m.pp"
done
```

No reboot required; the next login uses the new policy.

## Verify

Log out, log back in with face or fingerprint, and **do not** type the keyring
password:

```bash
./verify-keyring.sh
```

Expect `b false`, no `no TPM` / `cannot check` warning for the current login,
no AVCs, and `ssh OK`.

```bash
journalctl -b | grep -E 'PAM_AUTHTOK|gkr-pam'
# Captured PAM_AUTHTOK of length N bytes
# gkr-pam: stashed password to try later in open session
# gkr-pam: gnome-keyring-daemon started properly and unlocked keyring
```

## Maintenance

- Re-run `verify-keyring.sh` after any `biopass`, `oo7-daemon`, or
  `selinux-policy-targeted` update.
- Re-derive the rules if the denials change:
  `journalctl -b -o cat | grep 'avc:  denied' | grep biopass | audit2allow -M biopass_tpm`
- Remove once upstream (or Fedora) ships the policy:
  `sudo semodule -r biopass_tpm biopass_shadow`
