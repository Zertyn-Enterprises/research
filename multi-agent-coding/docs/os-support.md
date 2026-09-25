<!-- managed-by: multi-agent-coding -->
# Operating system support

Short version: macOS 13+, Ubuntu 20.04+ / Debian 10+, and Windows through WSL2.
Native Windows is not supported.

Everything in this kit is a bash script or a file that a bash script installs. bash
3.2 is the floor, because that is what ships with macOS.

## Component matrix

| Component | macOS 13+ | Ubuntu 20.04+ / Debian 10+ | Windows + WSL2 | Native Windows |
|---|---|---|---|---|
| Level 1 — `rules/core.md` into each CLI | yes | yes | yes | no |
| Level 1 — `project_doc_max_bytes` patch in `~/.codex/config.toml` | yes | yes | yes | no |
| Level 2 — `block-dangerous.sh` hook | yes | yes | yes | no |
| Level 2 — permission fragment merged into `~/.claude/settings.json` | yes | yes | yes | the file is portable, the installer is not |
| Level 2 — `gitleaks` pre-commit via global `core.hooksPath` | yes, needs `gitleaks` | yes, needs `gitleaks` | yes, needs `gitleaks` | no |
| Level 3 — statusline | yes | yes | yes | no |
| Level 3 — `test-author` agent, `context-init` / `techdebt` skills | yes | yes | yes | the files are markdown, the installer is not |
| Level 3 — `agentsify`, `plan-init` in `~/.local/bin` | yes | yes | yes | no |
| Level 4 — templates | yes | yes | yes | no |
| Roadmap — cross-model review (`xreview`) | planned | planned | planned | no |
| Roadmap — session coordination ledger | planned | planned | planned | no |
| Roadmap — fleet / tmux navigation | planned | planned | planned | no |
| Roadmap — token and cost ledger | planned | planned | planned | no, see `fcntl` below |
| Roadmap — menu-bar widgets | planned, macOS only | no | no | no |

"yes" here means the component is expected to work on that platform. Level 1-4 are
exercised by the test suite on macOS and on `ubuntu-latest` in CI; WSL2 is not in
CI, and is not verified by us.

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
```

Three things matter after that:

1. **Keep your repositories inside the Linux filesystem.** Clone into `~/code` or
   similar, not into `/mnt/c/...`. Microsoft's own guidance is to store project
   files in the Linux file system for performance
   ([WSL setup](https://learn.microsoft.com/en-us/windows/wsl/setup/environment)).
   Cross-filesystem work is slow enough to change how an agent feels to use.
2. **Install the CLIs and this kit inside WSL2**, not on the Windows side. `$HOME`
   must be the Linux home. If `doctor.sh` prints a `/mnt/c` path anywhere, you are
   in the wrong place.
3. **Add a Windows Terminal profile** for the distribution and make it your default,
   so you are not accidentally in PowerShell when you start an agent.

`doctor.sh` detects WSL2 by looking for `microsoft` in `/proc/version`, and reports
it as a distinct platform rather than plain Linux.

## The cost ledger and `fcntl`

The roadmap's token and cost ledger serialises writes with an advisory file lock,
and Python's `fcntl` module is documented as "Availability: Unix"
([Python docs](https://docs.python.org/3/library/fcntl.html)). It therefore cannot
run under native Windows CPython without a different locking backend. Under WSL2 it
is ordinary Linux and works. This is one more reason the roadmap modules inherit the
same WSL2-or-Unix constraint as the base kit.
