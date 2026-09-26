<!-- managed-by: multi-agent-coding -->
# Operating system support

Short version: macOS 13+, Ubuntu 20.04+ / Debian 10+, and Windows through WSL2.
Native Windows is not supported.

Everything in this kit is a bash script or a file that a bash script installs. bash
3.2 is the floor, because that is what ships with macOS.

## Component matrix

| Component | macOS 13+ | Ubuntu 20.04+ / Debian 10+ | Windows + WSL2 | Native Windows |
|---|---|---|---|---|
| Level 1 — `rules/core.md` into each CLI | yes | yes | expected | no |
| Level 1 — `project_doc_max_bytes` patch in `~/.codex/config.toml` | yes | yes | expected | no |
| Level 2 — `block-dangerous.sh` hook | yes | yes | expected | no |
| Level 2 — permission fragment merged into `~/.claude/settings.json` | yes | yes | expected | the file is portable, the installer is not |
| Level 2 — `gitleaks` pre-commit via global `core.hooksPath` | yes, needs `gitleaks` | yes, needs `gitleaks` | expected, needs `gitleaks` | no |
| Level 3 — statusline | yes | yes | expected | no |
| Level 3 — `test-author` agent, `context-init` / `techdebt` skills | yes | yes | expected | the files are markdown, the installer is not |
| Level 3 — `agentsify`, `plan-init` in `~/.local/bin` | yes | yes | expected | no |
| Level 4 — templates | yes | yes | expected | no |
| Roadmap — cross-model review (`xreview`) | planned | planned | planned | no |
| Roadmap — session coordination ledger | planned | planned | planned | no |
| Roadmap — fleet / tmux navigation | planned | planned | planned | no |
| Roadmap — token and cost ledger | planned | planned | planned | no, see `fcntl` below |
| Roadmap — menu-bar widgets | planned, macOS only | no | no | no |

"yes" means we run the component on that platform: levels 1-4 are exercised by the
test suite on macOS and on `ubuntu-latest` in CI. "expected" means it should work
and we have not checked — WSL2 is not in CI and is not verified by us.

## Why native Windows is out

Two independent reasons, and either one would be enough.

**The scripts are bash.** `install.sh`, `doctor.sh`, `uninstall.sh`, the hook, the
git hook and both tools are `#!/usr/bin/env bash`. On native Windows there is no
guaranteed bash. Git for Windows provides one, but the CLIs do not agree on using
it: Claude Code's setup page says "Git for Windows is recommended for native
Windows so Claude Code can use the Bash tool. If Git for Windows is not installed,
Claude Code uses PowerShell as the shell tool instead"
([setup](https://code.claude.com/docs/en/setup)). A safety hook whose matcher
assumes a shell command, on a host that may hand the agent PowerShell instead, is a
guard that silently does not guard.

**The platform features differ.** Claude Code's sandbox "is built into Claude Code
and runs on macOS, Linux, and WSL2"
([sandboxing](https://code.claude.com/docs/en/sandboxing)) — the setup page states
that WSL2 supports sandboxing and native Windows does not. On Linux the sandbox also
needs `bubblewrap` and `socat` installed. Separately, symlinks on Windows require
Developer Mode or the `SeCreateSymbolicLinkPrivilege`
([Git for Windows](https://gitforwindows.org/symbolic-links.html)), and this kit
uses symlinks in three places: `install.sh --link`, the `~/.local/bin` entries for
`agentsify` and `plan-init`, and the `PLAN.md` symlink that `plan-init` creates.

Supporting native Windows properly would mean a second PowerShell implementation of
the installer and a second hook, both tested. That is a real project, not a
compatibility flag, and it is not in v0.1.

## Vendor support, for reference

| CLI | Documented platforms |
|---|---|
| Claude Code | macOS 13.0+, Windows 10 1809+ / Server 2019+, Ubuntu 20.04+, Debian 10+ ([setup](https://code.claude.com/docs/en/setup)) |
| Codex CLI | macOS and Linux; a Windows install via PowerShell exists ([CLI docs](https://learn.chatgpt.com/docs/cli)) |
| Grok Build | its README states that Windows builds are best-effort and untested |

So a CLI supporting native Windows does not mean this kit does. The gap is the
kit's, and it is deliberate.

## WSL2 setup

Do this once, then treat the Linux distribution as your development machine.

```powershell
wsl --install
```

Then restart, create your Linux user, and from inside the distribution:

```bash
sudo apt update && sudo apt install -y git jq
sudo apt install -y bubblewrap socat   # only if you want Claude Code's Linux sandbox
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

A fresh distribution has no git identity, no SSH key and no GitHub login: create a
key (`ssh-keygen -t ed25519`) and add it to GitHub, or run `gh auth login` if you
install the GitHub CLI. Then install the agent CLIs you use, inside the
distribution, and sign in to each one.

If you copied dotfiles or a `~/.claude` directory from another machine, look for
symlinks whose target does not exist here (for example `~/.claude/rules ->
~/somewhere/rules`). `doctor.sh` lists them under "blocking" and the installer
refuses to run until the link is removed or its target restored — `mkdir` cannot
create a directory on top of a dangling link.

Three things matter after that:

1. **Keep your repositories inside the Linux filesystem.** Clone into `~/code` or
   similar, not into `/mnt/c/...`. Two reasons. Microsoft's own guidance is to store
   project files in the Linux file system for performance
   ([WSL setup](https://learn.microsoft.com/en-us/windows/wsl/setup/environment)),
   and cross-filesystem work is slow enough to change how an agent feels to use. The
   second is symlinks: `install.sh --link`, `plan-init` and `agentsify` all create
   them, and on a mounted Windows drive they typically fail (not verified by us).
2. **Install the CLIs and this kit inside the distribution**, not on the Windows
   side. A Claude Code installed on Windows never sees this kit: it reads a Windows
   `%USERPROFILE%\.claude`, not the Linux `~/.claude` the installer writes. `$HOME`
   must be the Linux home, and if `doctor.sh` prints a `/mnt/c` path anywhere, you
   are in the wrong place.
3. **Set the Ubuntu profile's starting directory to your Linux home** (Windows
   Terminal → Settings → the Ubuntu profile → Starting directory), otherwise every
   new tab opens on the Windows drive under `/mnt/c/…` — the wrong filesystem for
   everything above. Then make the Ubuntu
   profile the default, so you are not accidentally in PowerShell when you start an
   agent.

`doctor.sh` detects WSL2 by looking for `microsoft` in `/proc/version`, and reports
it as a distinct platform rather than plain Linux.

## The cost ledger and `fcntl`

The roadmap's token and cost ledger serialises writes with an advisory file lock,
and Python's `fcntl` module is documented as "Availability: Unix"
([Python docs](https://docs.python.org/3/library/fcntl.html)). It therefore cannot
run under native Windows CPython without a different locking backend. Under WSL2 it
is ordinary Linux and works. This is one more reason the roadmap modules inherit the
same WSL2-or-Unix constraint as the base kit.
