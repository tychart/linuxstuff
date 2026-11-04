# setupconfig sources

Quick copy and paste command:
```bash
curl -fsSL https://raw.githubusercontent.com/tychart/linuxstuff/main/setupconfig/setupconfig.sh | bash
```

`setupconfig/setupconfig.sh` treats this directory as repository-managed input.

- `managed/` contains fragments inserted into marked blocks in user dotfiles.
- `files/oscyank.vim` is installed as the Vim plugin.
- `release-assets.tsv` describes upstream GitHub release assets.

The script uses checked-out files when run from this repository. In a
`curl | bash` invocation it fetches these paths from `tychart/linuxstuff` on
`SETUPCONFIG_REF` (default: `main`). Set `SETUPCONFIG_REF` to a tag or commit
when reproducibility matters.

Every exported variable, PATH included, lives in exactly one managed file:
`~/.config/setupconfig/env.sh`. **Add your own variables there** — in
`setupconfig/managed/env.sh` (the repo copy) or just below the managed block in
`~/.config/setupconfig/env.sh`, where reruns preserve them. Do not add exports
to `~/.profile`, `~/.bashrc`, or the Fish config: each of those is read by only
some shells, so the value silently reaches some sessions and not others.

Shell startup files only source that one file: `~/.bashrc` (every Bash shell,
reached from `~/.bash_profile` for login shells), `~/.profile` (POSIX sh and
dash, when that file exists), and
`${XDG_CONFIG_HOME:-~/.config}/fish/config.fish` (Fish). An existing `~/.zshrc`
gets the same source line plus the same Fish handoff as `~/.bashrc`. No shell
keeps its own copy of the values.

Bash login shells follow `~/.bash_profile`, so they never read `~/.profile`.
Put exports in the shared environment file, not in `~/.profile`: that file is
the POSIX entry point for sh and dash, and its managed block does nothing else.

Fish parses the environment file directly, so it must stay limited to plain
`export NAME=value` lines. Fish cannot parse `if`, `[[ ]]`,
`${NAME:-default}`, functions, or bare `PATH=...` assignments; anything needing
logic belongs in that shell's own block instead. `export PATH="...:$PATH"`
does work in Fish, which splits and rejoins PATH as a list.

The environment is sourced once per shell, so the PATH entries appear once.
Inside `~/.bashrc` the distro file (`/etc/bashrc`, `/etc/bash.bashrc`) is
sourced first, because distros prepend system directories there (Fedora adds
`/usr/lib64/ccache`) and `~/.local/bin` has to stay in front of them.

Managed blocks are created when their file is missing only if they are listed
in `ALWAYS_CREATE_BLOCKS`: the shared `env` file, `~/.bash_profile`,
`~/.bashrc`, the Fish config, `~/.vimrc`, and `~/.inputrc`. Those are the shells
and files setupconfig drives itself; `~/.bash_profile` is what makes Bash login
behave the same on Fedora, RHEL, Ubuntu, and macOS.

`~/.profile` and `~/.zshrc` are handled the other way round: the block is added
when the file already exists and nothing is created, because they belong to a
login path setupconfig does not own (POSIX sh/dash) or to the user's own Zsh
config. A fresh install therefore has no `~/.profile`; it is not needed by Bash
or Fish, and a default Ubuntu install already has one and gets the block.

## Staying in Bash or Zsh

`~/.bashrc` and `~/.zshrc` hand an interactive shell over to Fish when Fish is
installed. To stay in the shell that was started, run the Fish helper
`bashonly`, or set the same variable yourself:

```fish
bashonly                     # Bash with aliases, prompt, history, the lot
bashonly -l                  # same, as a login shell
env SETUPCONFIG_NO_FISH=1 zsh   # Zsh, no handoff
SETUPCONFIG_NO_FISH=1 bash      # equivalent, from Bash
```

The variable is exported, so nested `bash` calls inside that session stay in
Bash as well.

## Release manifest

The manifest is tab-separated:

```text
tool  repository  os  arch  asset-template  format  archive-member  version-argument  source
```

`{tag}`, `{version}`, and normalized `{arch}` in the asset/member fields are
replaced from the GitHub `releases/latest` tag and selected platform. `format`
is `raw`, `tar`, or `zip`. The `source` column identifies the provider;
maintained rows use `official` or a custom fork label. Matching sources are
compared by release version, and the newest is preferred. Interactive installs
ask which source to use only when an install or update is actually needed. The
same asset and version format is used for all sources.
Archive members are exact names and are extracted into a private temporary
candidate before validation. Unsafe member names are rejected.

Rows are selected by normalized platform values. `amd64`/`x86_64` become
`x86_64`, and `arm64`/`aarch64` become `aarch64`. Linux x86_64 and ARM64
(`aarch64`) are supported for the configured providers; Darwin support depends
on whether that provider publishes a matching macOS asset. Termux is detected
separately and does not receive Linux/glibc release binaries. Add a row for a
provider's published naming convention rather than adding shell logic.

Compiled tools installed by this script are owned by setupconfig and live in
`~/.local/bin`. Each run resolves the provider's latest stable release and runs the
installed executable's version command. The first semantic version in that
output is compared with the release tag; no state files are required. A
replacement is only moved into place after download, extraction, executable
validation, version validation, and `--version` succeeds. Existing
executables are never deleted first.

Use `--install-optional` to install or update all seven configured non-Fish
compiled tools without prompting. On an interactive run without that flag,
the script asks one question: `Y` installs/updates all seven, `N` skips them
without querying GitHub, and `S` preserves the existing per-tool prompts.
Current tools remain quiet; only missing, stale, or unknown-version tools
require a per-tool question in `S` mode.

Fish is asked about separately after that decision when a matching release row
exists. `--install-fish` installs or updates Fish without prompting when a
matching release asset exists. On unsupported platforms such as macOS, the
script skips Fish and prints an official/manual installation suggestion rather
than invoking a system package manager. In a non-interactive run, optional
tools and Fish are skipped unless their explicit flags are supplied. The
portable `scripts/osc52` helper is not optional: it is synchronized on every
setup run, including macOS, ARM, Termux, and other platforms without a matching
compiled release row.

The manifest intentionally supports several rows for one tool. This is how a
provider can publish different archive names or members for Linux, Darwin,
x86_64, and aarch64 without changing the installer. Add a second row with the
same tool, OS, and architecture plus a custom `source` label to use a
compatible fork for only that platform. Fish currently has only Linux
standalone binary rows
because upstream does not publish a standalone macOS binary archive in the same
format.
