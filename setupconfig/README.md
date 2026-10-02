# setupconfig sources

`setupconfig.sh` treats this directory as repository-managed input.

- `managed/` contains fragments inserted into marked blocks in user dotfiles.
- `files/oscyank.vim` is installed as the Vim plugin.
- `release-assets.tsv` describes upstream GitHub release assets.

The script uses checked-out files when run from this repository. In a
`curl | bash` invocation it fetches these paths from `tychart/linuxstuff` on
`SETUPCONFIG_REF` (default: `main`). Set `SETUPCONFIG_REF` to a tag or commit
when reproducibility matters.

## Release manifest

The manifest is tab-separated:

```text
tool  repository  os  arch  asset-template  format  archive-member  version-argument
```

`{tag}`, `{version}`, and normalized `{arch}` in the asset/member fields are
replaced from the upstream GitHub `releases/latest` tag and selected platform.
`format` is `raw`, `tar`, or `zip`.
Archive members are exact names and are extracted into a private temporary
candidate before validation. Unsafe member names are rejected.

Rows are selected by normalized `uname` values. `amd64`/`x86_64` become
`x86_64`, and `arm64`/`aarch64` become `aarch64`. Add a row for a provider's
published naming convention rather than adding shell logic.

Compiled tools installed by this script are owned by setupconfig and live in
`~/.local/bin`. Their release tag and manifest row are recorded under
`${XDG_STATE_HOME:-~/.local/state}/setupconfig/releases`. A replacement is
only moved into place after download, extraction, executable validation, and
`--version` succeeds. Existing executables are never deleted first.

Use `--install-optional` to install or update the configured compiled tools
without prompting. A normal interactive run asks before installing a missing
tool or replacing a stale managed one. The portable `scripts/osc52` helper is
not optional: it is synchronized on every setup run, including macOS, ARM,
Termux, and other platforms without a matching compiled release row.

The manifest intentionally supports several rows for one tool. This is how a
provider can publish different archive names or members for Linux, Darwin,
x86_64, and aarch64 without changing the installer.
