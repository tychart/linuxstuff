# Publishing blesh for `setupconfig.sh`

The setup script downloads blesh from the latest `tychart/linuxstuff` GitHub
release. Publish one asset named exactly:

```text
blesh.tar.gz
```

It is intentionally simple: the asset is just the `out/` directory produced by
building this repository. `setupconfig.sh` extracts that directory and installs
it as:

```text
~/programs/blesh/
```

The archive must therefore contain `out/ble.sh`, `out/lib/`, and
`out/contrib/`. Do not publish only `ble.sh`; blesh loads files from `lib/` at
runtime, and its fzf integration is in `contrib/`.

## Build and package

On the machine where you maintain this repository:

```bash
# Update blesh and its bundled contrib files.
git pull --ff-only
git submodule update --init --recursive

# Build the runtime tree. This requires GNU Make and GNU Awk.
make

# Package the build output. gzip/tar are ubiquitous on Linux.
tar -czf blesh.tar.gz out
```

That last command is all that is needed to create the release asset.

## Check it before publishing

Optional but recommended:

```bash
# Confirm the archive contains the runtime files blesh needs.
tar -tzf blesh.tar.gz | grep -E '^(out/ble\.sh|out/lib/|out/contrib/)'

# Confirm it can be extracted.
test_dir="$(mktemp -d)"
tar -xzf blesh.tar.gz -C "$test_dir"
test -r "$test_dir/out/ble.sh"
test -d "$test_dir/out/lib"
rm -rf "$test_dir"
```

## Publish and update

1. Create a new GitHub release in `tychart/linuxstuff` with a new release tag.
2. Upload `blesh.tar.gz` to that release.
3. Run `setupconfig.sh --install-optional` on a test machine, or answer yes to
   its blesh prompt during a normal interactive run.
4. Start a new interactive shell and check:

   ```bash
   printf '%s\n' "$BLE_VERSION"
   ```

`setupconfig.sh` saves the installed LinuxStuff release tag in:

```text
~/programs/blesh/.linuxstuff-release
```

On later runs, it compares that marker to the newest LinuxStuff release. If
the tag changed, it downloads and replaces the installed blesh tree. Your
blesh settings remain separate in `~/.blerc` (or
`~/.config/blesh/init.sh`), so updates do not overwrite them.

## fzf note

When both blesh and fzf are installed, `setupconfig.sh` loads blesh's bundled
fzf integration. Do not separately add `eval "$(fzf --bash)"` for that case:
the standard fzf Readline bindings conflict with blesh.
