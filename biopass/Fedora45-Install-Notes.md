# Biopass 1.5.1 on Fedora 45 — Framework Laptop 13

**Status:** Confirmed working after reboot — keyring unlock additionally requires two local SELinux policy modules (see [SELinux policy for TPM + shadow](#selinux-policy-for-tpm--shadow))  
**Date tested:** 2026-11-05 (biometric login, PAM); keyring-unlock chain re-verified after a full reboot on 2026-11-11  
**Hardware:** Framework Laptop 13, Goodix MOC fingerprint sensor, TPM 2.0  
**Desktop/login manager:** GNOME 51 / GDM 51  
**OS:** Fedora Workstation 45, upgraded from Fedora 44  
**Biopass:** 1.5.1-1.x86_64 RPM

## Executive summary

Biopass 1.5.1 works on a fresh Fedora 45 installation after four Fedora-specific adjustments:

1. Install `libxcrypt-compat`, because the Biopass TPM helper requires the legacy `libcrypt.so.1` ABI.
2. Install `gnome-keyring-pam` separately from `gnome-keyring`; Fedora 45 splits the PAM module into its own package.
3. Integrate Biopass into GDM's PAM substack instead of changing Fedora's shared `system-auth` or `password-auth` files.
4. Add two local SELinux policy modules so the TPM unseal and the `/etc/shadow` re-check work inside GDM's `xdm_t` domain. Without them biometric login works but the keyring silently stays locked.

The final setup successfully:

- enrolls and verifies fingerprints;
- saves the login password sealed by the TPM;
- authenticates at the GNOME/GDM login screen with a fingerprint;
- unlocks the GNOME Keyring after biometric login;
- works after a complete reboot;
- retains normal password fallback;
- leaves `sudo`, TTY login, `su`, and other shared PAM services on Fedora's normal authselect configuration.

> **Correction (2026-11-11).** An earlier revision of this document recorded keyring unlock as confirmed on 2026-11-05. That was a false positive. The biopass app log contains `Biopass: no TPM to unlock the keyring` on every day since installation (`~/.local/share/com.ticklab.biopass/logs/`), and the keyring only *appeared* unlocked because it had already been unlocked by hand earlier in that session. The actual cause was missing SELinux policy, and the fix is the section below; the full chain was re-verified after a complete reboot on 2026-11-11.

## Hardware and software verification

Installed packages:

```text
biopass-1.5.1-1.x86_64
libxcrypt-compat-4.5.2-4.fc45.x86_64
gnome-keyring-51.1-1.fc45.x86_64
gnome-keyring-pam-51.1-1.fc45.x86_64
fprintd-1.94.5-6.fc45.x86_64
fprintd-pam-1.94.5-6.fc45.x86_64
gdm-51.0-1.fc45.x86_64
```

Fingerprint enrollment and direct verification worked:

```text
Goodix MOC Fingerprint Sensor
five enrolled fingers
Verify result: verify-match (done)
```

## Initial problem: TPM password save failed

The Biopass GUI initially reported:

```text
Failed to save the password: Not authorized.
Biopass needs a polkit authentication agent to save the password.
```

The Polkit policy was present and correct:

```text
/usr/share/polkit-1/actions/com.ticklab.biopass.policy
```

The systemd Polkit helper override was also present:

```text
/etc/systemd/system/polkit-agent-helper@.service.d/override.conf
```

The journal showed that Polkit authentication succeeded and launched the helper:

```text
COMMAND=/usr/libexec/biopass/biopass-keyring seal --pcr7
```

The actual failure was discovered by running:

```bash
ldd /usr/libexec/biopass/biopass-keyring
```

Before the fix:

```text
libcrypt.so.1 => not found
```

### Fix

```bash
sudo dnf install libxcrypt-compat
```

Afterward:

```text
libcrypt.so.1 => /lib64/libcrypt.so.1
```

The helper then loaded successfully and printed its usage message when run without arguments:

```text
biopass-keyring: usage: biopass-keyring seal [--pcr7] | forget | update USER
```

The Biopass GUI then successfully saved the password using TPM sealing.

## Fedora 45 GNOME Keyring package split

Installing only `gnome-keyring` did not provide the PAM module:

```text
/usr/lib64/security/pam_gnome_keyring.so: No such file or directory
```

Fedora 45 provides the PAM module in a separate package:

```bash
sudo dnf install gnome-keyring-pam
```

Verification:

```bash
rpm -ql gnome-keyring-pam | grep pam_gnome_keyring
```

Output:

```text
/usr/lib64/security/pam_gnome_keyring.so
```

## SELinux policy for TPM + shadow

### Symptom

Biopass authenticated at GDM (face or fingerprint) and the session opened, but the login keyring was still locked. The first app that touched the Secret Service then prompted for the keyring password:

```text
$ busctl --user get-property org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/login \
    org.freedesktop.Secret.Collection Locked
b true
```

Because typing the password once per session makes everything work again, this is easy to mistake for success (see the correction at the top).

### Diagnosis

Biopass's keyring handoff lives in `auth/keyring/`, and after a biometric match `biopass-helper` (which runs in GDM's SELinux domain `xdm_t`) does four things: read the sealed blob, unseal it with the TPM, re-check the result against `/etc/shadow`, then write it to the PAM module, which sets `PAM_AUTHTOK`. Two of those four steps are denied by SELinux on Fedora 45, and biopass 1.5.1 ships no policy of its own.

| Stage | Log evidence | Cause |
| --- | --- | --- |
| TPM unseal | `Biopass: no TPM to unlock the keyring` + `avc denied { open }` / `{ read write }` on `/dev/tpmrm0`, `xdm_t` → `tpm_device_t` | no policy allow |
| shadow re-check | `Biopass: cannot check the saved keyring password (2)` | `2` = `PasswordCheck::NoLocalAccount`; `getspnam_r()` cannot read `shadow_t` from `xdm_t` |
| PAM handoff | `pam_oo7: PAM_AUTHTOK is null (password not available)` and `gkr-pam: no password is available for user` | nothing was handed over, so the keyring cannot unlock |

Note the failure mode: biometric login is unaffected, so only the keyring breaks, and the only user-visible symptom is an unrelated-looking password prompt.

### Fix

Two local policy modules. Save the sources from [`biopass/selinux/`](selinux/) in this repository:

```text
biopass_tpm.te
module biopass_tpm 1.0;

require {
        type xdm_t;
        type tpm_device_t;
        class chr_file { open read write ioctl getattr };
}

allow xdm_t tpm_device_t:chr_file { open read write ioctl getattr };
```

```text
biopass_shadow.te
module biopass_shadow 1.0;

require {
        type xdm_t;
        type shadow_t;
        class file { getattr open read };
}

allow xdm_t shadow_t:file { getattr open read };
```

Build and install both:

```bash
cd biopass/selinux
for m in biopass_tpm biopass_shadow; do
  checkmodule -M -m -o "$m.mod" "$m.te"
  semodule_package -o "$m.pp" -m "$m.mod"
  sudo semodule -i "$m.pp"
done
```

No reboot is needed; the policy reloads immediately and the next login picks it up.

Why `open`/`ioctl` on the TPM rule: the first `audit2allow` pass only saw `{ read write }`, and the denial then moved to `{ open }`. Granting the wider device set up front avoids a second iteration.

### Why the second rule is hard to find

Fedora's policy `dontaudit`s the `xdm_t` → `shadow_t` probe, so it never appears in `journalctl | grep avc`, and biopass flattens the `EACCES` into `NoLocalAccount`. Verify it by running a lookup inside the domain (a copy must live outside `/tmp`, which is `nosuid`):

```bash
sudo install -m 755 /usr/bin/getent /usr/local/bin/getent-xdm
sudo chcon -t xdm_exec_t /usr/local/bin/getent-xdm
sudo runcon system_u:system_r:xdm_t:s0-s0:c0.c1023 /usr/local/bin/getent-xdm shadow tychart
sudo rm -f /usr/local/bin/getent-xdm
```

`selinux/` contains `test-shadow.sh`, which wraps this, and `verify-keyring.sh`, the post-login health check.

### Verification

After the modules are installed, log out and back in with a fingerprint or face, and **do not** type the keyring password. Then:

```text
$ journalctl -b | grep -E 'PAM_AUTHTOK|gkr-pam'
gdm-password: Captured PAM_AUTHTOK of length 8 bytes
gdm-password: gkr-pam: stashed password to try later in open session
gdm-password: gkr-pam: gnome-keyring-daemon started properly and unlocked keyring

$ busctl --user get-property org.freedesktop.secrets \
    /org/freedesktop/secrets/collection/login \
    org.freedesktop.Secret.Collection Locked
b false

$ biopass/selinux/verify-keyring.sh    # Locked=false, no warnings, ssh OK
```

Confirmed after a full reboot: biometric login, keyring already unlocked, and SSH keys stored in the keyring usable immediately.

### Note on Fedora 45's Secret Service

Fedora 45 runs `oo7-daemon` (`pam_oo7`, `ImportCredential=oo7.keyring-encryption-password`, store at `~/.local/share/keyrings/v1/`), not `pam_gnome_keyring`. `gnome-keyring-daemon` logs `another secret service is running`. The biopass handoff still works because `pam_oo7` consumes `PAM_AUTHTOK` from the auth phase, but this is why `docs/Keyring.md` mentions modules that are not the active ones here.

### Maintenance

- Upstream report: [phucvinh57/biopass#252](https://github.com/phucvinh57/biopass/issues/252).
- Re-run `selinux/verify-keyring.sh` after any `biopass`, `oo7-daemon`, or `selinux-policy-targeted` update.
- If the rules land in Fedora's or biopass's own policy, drop the local ones: `sudo semodule -r biopass_tpm biopass_shadow`.
- Re-derive from scratch if the denials change: `journalctl -b -o cat | grep 'avc:  denied' | grep biopass | audit2allow -M biopass_tpm`.

## Final authselect state

The final authselect configuration is intentionally Fedora's normal profile:

```text
Profile ID: local
Enabled features:
- with-silent-lastlog
- with-fingerprint
- with-mdns4
```

Validation:

```bash
authselect check
```

Output:

```text
Current authselect configuration is valid.
```

The shared files below were left under normal authselect control and were not modified to add Biopass:

```text
/etc/pam.d/system-auth
/etc/pam.d/password-auth
```

This is important because changing those files affected `sudo` and caused failed password fallback during an earlier experiment.

## Final GDM-only PAM integration

Fedora 45's GDM package provides:

```text
/usr/lib/pam.d/gdm-password
/usr/lib/pam.d/gdm-password-auth-substack
```

The vendor `gdm-password` file already invokes the GNOME Keyring module after the authentication substack. The safe integration is therefore an `/etc` override of only the substack:

```bash
sudo cp -a /usr/lib/pam.d/gdm-password-auth-substack \
  /etc/pam.d/gdm-password-auth-substack

sudo sed -i \
  '1i auth [success=done default=ignore] libbiopass_pam.so authtok' \
  /etc/pam.d/gdm-password-auth-substack
```

Final file:

```pam
auth [success=done default=ignore] libbiopass_pam.so authtok
auth     include   password-auth
auth     required  pam_deny.so

password include   password-auth
password required  pam_deny.so
```

Why this works:

- On a successful biometric match, `success=done` ends the GDM authentication substack successfully.
- GDM's outer PAM file then continues to its own `pam_gnome_keyring.so` line.
- The `authtok` option allows Biopass to provide the TPM-unsealed password to the keyring module.
- On Biopass failure or timeout, `default=ignore` allows the normal Fedora password stack to run.
- `sudo`, TTY login, and other services do not use this GDM-only override.

The final active GDM substack can be checked with:

```bash
cat /etc/pam.d/gdm-password-auth-substack
```

## Biopass configuration

The working configuration contains:

```yaml
strategy:
  debug: true
  execution_mode: parallel
  order:
  - face
  - fingerprint
  ignore_services:
  - polkit-1
  - pkexec
```

Face authentication is disabled on this laptop; fingerprint authentication is enabled:

```yaml
methods:
  face:
    enable: false
  fingerprint:
    enable: true
    retries: 1
    timeout: 5000
```

Keeping `polkit-1` and `pkexec` ignored prevents recursive Biopass authentication. `gdm-password` must not be ignored, because it is the GDM login service.

## Testing performed

### Direct fingerprint test

```bash
fprintd-verify "$USER"
```

Result:

```text
Verify result: verify-match (done)
```

### GDM test

After installing the packages, saving the password, and creating the GDM-only PAM override:

1. Logged out.
2. Authenticated at the GNOME login screen with a fingerprint.
3. Confirmed the desktop opened.
4. Confirmed the GNOME Keyring unlocked without a password prompt.
5. Rebooted the laptop completely.
6. Confirmed fingerprint login and keyring unlock still worked after reboot.

## Important failed approach to avoid

Do not insert this rule into Fedora's shared `system-auth` or `password-auth` files:

```pam
auth [success=...] libbiopass_pam.so authtok
```

Those files are used by `sudo`, TTY login, `su`, and many other services. An incorrect control flag can cause both biometric authentication and normal password fallback to fail, potentially requiring recovery-mode PAM repair.

The working solution is specifically:

```text
/etc/pam.d/gdm-password-auth-substack
```

## Recovery / rollback

If GDM login fails, remove the `/etc` override. Fedora will return to the vendor file in `/usr/lib/pam.d`:

```bash
sudo rm -f /etc/pam.d/gdm-password-auth-substack
```

If no graphical or TTY login is available, boot Fedora once with `init=/bin/bash`, then:

```bash
mount -o remount,rw /
rm -f /etc/pam.d/gdm-password-auth-substack
sync
exec /sbin/reboot -f
```

The shared authselect profile should normally remain:

```text
local with-silent-lastlog with-fingerprint with-mdns4
```

If it was accidentally changed, restore it as root:

```bash
authselect select local \
  with-silent-lastlog \
  with-fingerprint \
  with-mdns4 \
  --nobackup
```

## Recommended upstream documentation changes

The Fedora/RHEL section of the Biopass PAM guide should mention:

1. Fedora 45 requires `libxcrypt-compat` for Biopass 1.5.1 because the helper links against `libcrypt.so.1`.
2. Fedora 45 requires `gnome-keyring-pam` separately from `gnome-keyring`.
3. Fedora's `authselect` owns `system-auth` and `password-auth`; users should not directly insert Biopass there for GDM keyring integration.
4. Fedora 45 GDM provides `gdm-password-auth-substack`; a safe GDM-only integration is:

   ```pam
   auth [success=done default=ignore] libbiopass_pam.so authtok
   auth     include   password-auth
   auth     required  pam_deny.so
   ```

5. The guide should explicitly recommend keeping `polkit-1` and `pkexec` in Biopass's ignored PAM services and not ignoring `gdm-password`.
6. Fedora users should be told to keep a root shell or TTY available while testing PAM changes.
7. Fedora/RHEL users with SELinux enforcing need local policy for keyring unlock: `xdm_t` → `tpm_device_t:chr_file` **and** `xdm_t` → `shadow_t:file`. The second one is `dontaudit`ed, so it cannot be found from the AVC log; the docs should either ship the policy or show the modules.
8. On Fedora 45 the Secret Service is `oo7-daemon` with `pam_oo7`, not `pam_gnome_keyring`/`pam_kwallet`; the keyring section of the docs should say so.
9. `releaseKeyringPassword()` should log the `errno` behind `PasswordCheck::NoLocalAccount`; the current message made an SELinux denial look like an unsupported account type.

## Final conclusion

Biopass 1.5.1 is confirmed working on Fedora 45 on a Framework Laptop 13 with a Goodix MOC fingerprint reader and TPM 2.0. The reliable configuration uses Fedora's normal authselect profile and adds Biopass only to the GDM authentication substack, allowing both fingerprint login and automatic GNOME Keyring unlock without destabilizing `sudo` or the rest of the system PAM configuration.

Automatic keyring unlock additionally requires the two local SELinux modules documented above; without them biometric login works but the keyring stays locked. The complete chain (TPM unseal → shadow re-check → `PAM_AUTHTOK` → unlocked keyring → SSH keys usable) was verified after a full reboot on 2026-11-11. The missing policy and the misleading `NoLocalAccount` diagnostic were reported upstream as [phucvinh57/biopass#252](https://github.com/phucvinh57/biopass/issues/252).
