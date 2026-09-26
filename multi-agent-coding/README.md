<!-- managed-by: multi-agent-coding -->
# multi-agent-coding

One set of engineering rules, one safety floor, and one installer for every coding
agent you run. If you work with Claude Code one day, Codex the next and Grok Build
after that, each CLI reads its own global config and each one behaves differently.
This kit writes the same rules and the same destructive-command guard into all of
them, from a single source, with a dry run, a backup of everything it replaces, and
an uninstaller that only removes what it installed.

Version 0.1. Read [docs/limitations.md](docs/limitations.md) before you rely on it.

## Quick start

`git` and `jq` first: `sudo apt install -y git jq` on Ubuntu or WSL2,
`brew install jq` on macOS.

```bash
git clone https://github.com/Zertyn-Enterprises/research.git
cd research
bash multi-agent-coding/doctor.sh              # read-only: what is installed, what would change
bash multi-agent-coding/install.sh --dry-run   # prints every path it would write, writes nothing
bash multi-agent-coding/install.sh             # asks [y/N] once per level, then writes
```

`install.sh` with no flags runs the doctor, prints the plan, and asks for
confirmation once per level. Nothing is written before you answer.

Prefer to let your agent do it? Clone, open your CLI in the checkout, and tell it:

> Read `multi-agent-coding/AGENT-INSTALL.md` and follow it step by step.

That page is a contract for the agent: diagnose, dry-run, ask before every write,
never touch secrets or permission modes. It works with any CLI that has a shell.

### Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Print every path that would be written or changed. Write nothing. |
| `--yes` | Skip the per-level prompts. Required whenever stdin is not a terminal; without it the installer writes nothing and exits 1. |
| `--link` | Symlink into the cloned checkout instead of copying. Updates follow `git pull`. |
| `--level N` | Install levels 1 through N (see the table below). `--level 3` installs 1-4, because level 3 pulls in level 4. |
| `--only LIST` | Install exactly these levels: a comma-separated list of names or numbers, e.g. `--only rules,safety` or `--only 2`. Selecting `claude-quality` also adds `plan`. |
| `--prefix DIR` | Install prefix (must be inside `$HOME`). Same as `MULTI_AGENT_CODING_HOME`. |
| `--uninstall` | Hands over to `uninstall.sh`; only `--dry-run`, `--yes`, `--prefix` and `--restore-backups` pass through, level flags are rejected. |
| `--help` | Usage. |

Exit codes: `0` success, `1` error, `2` usage error. `doctor.sh` and
`uninstall.sh` accept `--help` and `--prefix` too; `uninstall.sh` also accepts
`--dry-run`, `--yes` and `--restore-backups`.

When stdin is not a terminal (an agent or a script is running the installer) and
`--yes` is absent, nothing is installed: the prompts cannot be answered, so the
installer writes nothing, says so, and exits 1. Pass `--yes` after a dry run.

### Environment

| Variable | Default | Meaning |
|---|---|---|
| `MULTI_AGENT_CODING_HOME` | `$HOME/.multi-agent-coding` | Install prefix. Holds the copied hook, git hooks, the two tools, templates and `manifest.txt`. |
| `MAC_PROTECTED_BRANCHES` | `main master` | Branches the safety hook refuses to push to directly. An empty value falls back to the default, so the guard cannot be switched off this way. Set it in the CLI's own environment — your shell profile, or the `env` block of `settings.json` — so the hook sees it. |
| `CLAUDE_CONFIG_DIR` | unset | Honoured when set; must live inside `$HOME` or the installer exits 1. |
| `MAC_SKIP_PATH_DETECT` | unset | `1` detects CLIs by config directory only, ignoring `PATH`. Used by the tests. |

### After installing

Restart each CLI — none of them reloads global instructions in a running session.
In Claude Code, `/context` lists the loaded memory files; `~/.claude/rules/core.md`
should be among them. For Codex, confirm that `~/.codex/AGENTS.md` exists. If you
installed level 2, smoke-test the hook:

```bash
printf '{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}' \
  | bash "$HOME/.multi-agent-coding/hooks/block-dangerous.sh"
```

It must print `BLOCKED: …` and exit 2.

### Updating

```bash
git pull
bash multi-agent-coding/install.sh --yes
```

A second run rewrites only what the pull changed and prints `unchanged` for the
rest; it never backs up a file it installed itself. With `--link` the installed files are symlinks into the checkout, so
`git pull` alone updates them. Switching between the two is one more run — with
`--link` to move to symlinks, without it to move back to copies — and neither
creates a new `.bak-*`, because the file being replaced is already the kit's.

## Levels

A level is a group of files installed together, prompted for separately,
selectable with `--only`, and removable by the uninstaller. Levels are opt-in and
combine freely, with one dependency: the `agentsify` and `plan-init` commands from
level 3 read the templates that level 4 installs, so choosing `claude-quality`
auto-adds level `plan` and the installer prints `level plan added to the
selection`. `--level 3` therefore installs levels 1-4.

| Level | Name | What it writes |
|---|---|---|
| 1 | `rules` | The shared rules file into each CLI's global instruction path: `~/.claude/rules/core.md` for Claude Code, `~/.codex/AGENTS.md` for Codex (plus `project_doc_max_bytes = 131072` in `~/.codex/config.toml`, because Codex's default 32 KiB is a combined budget for this file and every project `AGENTS.md` it loads). Grok Build already reads `~/.claude/rules/`, so nothing is written under `~/.grok` unless Claude Code is absent. |
| 2 | `safety` | `block-dangerous.sh` into the install prefix, wired as a `PreToolUse` hook in every CLI that is present. A deny/ask permission fragment merged into `~/.claude/settings.json`. A `gitleaks` pre-commit hook, enabled with `git config --global core.hooksPath` only if you have no global hooks path already. |
| 3 | `claude-quality` | Claude Code only: a statusline, the `test-author` agent, the `context-init` and `techdebt` skills, and `agentsify` + `plan-init` symlinked into `~/.local/bin`. |
| 4 | `plan` | The `AGENTS.md` and `PLAN.md` templates into the install prefix, where `agentsify` and `plan-init` read them. |

Level 1 is the whole point of the kit. Level 2 is the part that can block a command
you wanted to run. Level 3 only touches Claude Code, and its two commands land in
`~/.local/bin`: the installer and `doctor.sh` both say so when that directory is not
on your `PATH`, and neither edits a shell profile (on Ubuntu a new login shell adds
it once the directory exists).

## Which CLIs

| CLI | Rules | Safety hook | Quality pack (level 3) |
|---|---|---|---|
| Claude Code | `~/.claude/rules/core.md` | `~/.claude/settings.json` | yes |
| Codex CLI | `~/.codex/AGENTS.md` | `~/.codex/hooks.json` | no |
| Grok Build | reads `~/.claude/rules/` through its Claude compatibility layer; `~/.grok/rules/core.md` only if Claude Code is absent | `~/.grok/hooks/multi-agent-coding.json` | partly, through the same compatibility layer |
| Kimi Code, GLM (Z.ai) coding plans | same files as Claude Code | same | yes |
| Gemini CLI, OpenCode, Cursor | not supported in v0.1 | no | no |

Kimi Code and the Z.ai (GLM) coding plans run inside Claude Code itself: you point
`ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` at the provider and keep the same
`~/.claude` directory ([Z.ai](https://docs.z.ai/devpack/tool/claude.md),
[Kimi Code](https://moonshotai.github.io/kimi-code/en/)). So they inherit levels 1-3
with no extra work, and the doctor says so. If you keep each provider in its own
`CLAUDE_CONFIG_DIR`, run the installer once per config directory:
`CLAUDE_CONFIG_DIR=… bash multi-agent-coding/install.sh`.

Grok Build's Claude compatibility is real: verified on Grok 1.0.41 with
`grok inspect`, which lists `~/.claude/rules/core.md` as a loaded global instruction
and also loads Claude skills, agents and permissions. Its hook dispatch through
`~/.claude/settings.json` is not verified by us, which is why level 2 writes Grok's
native hook file instead. Details and vendor URLs:
[docs/per-cli-paths.md](docs/per-cli-paths.md).

## Operating systems

| OS | Status |
|---|---|
| macOS 13+ | Supported. Developed here. |
| Ubuntu 20.04+, Debian 10+ | Supported. Level 1-4 run in CI on `ubuntu-latest`. |
| Windows 10/11 via WSL2 | Expected to work: the same Linux path runs in CI on `ubuntu-latest` and was exercised in a stock Ubuntu 22.04 container (suite, install, reinstall, uninstall), but WSL2 itself is not verified by us. Install inside the Linux distribution, not on the Windows side. |
| Native Windows (PowerShell, cmd) | Not supported. |

Native Windows is out because every managed file here is a bash script and because
the parts of each CLI this kit hooks into behave differently there: without Git for
Windows, Claude Code falls back to PowerShell as its shell tool, and its sandbox
does not run on native Windows at all
([setup](https://code.claude.com/docs/en/setup),
[sandboxing](https://code.claude.com/docs/en/sandboxing)). Symlinks — which
`--link`, `plan-init` and `agentsify` all use — additionally need Developer Mode or
`SeCreateSymbolicLinkPrivilege` ([Git for Windows](https://gitforwindows.org/symbolic-links.html)).
Full matrix and the WSL2 setup steps: [docs/os-support.md](docs/os-support.md).

## Cross-model review is optional, and it is not free

A second model family reviewing your diff catches real bugs, and each review costs
a full session of another model — its own context window, its own quota, multiplied
by every reviewer in a panel — so it needs subscriptions with two different vendors.
**Not in v0.1:** the rules file asks for an independent review when a second family
is available and for plain words when none ran; the `xreview` command and its pre-PR
gate are on the [roadmap](ROADMAP.md). Cost model, and how the future module degrades
to `SKIPPED` instead of blocking a PR: [docs/cross-model-review.md](docs/cross-model-review.md).

## Widgets and extras

Two macOS-only menu-bar widgets exist and are **not** in v0.1; what they need and
the Linux/WSL2 equivalent are in [extras/README.md](extras/README.md).

## Security: read before you install

This kit installs a hook that your agent runs before every shell command. That is
the point of it, and it is also exactly the kind of thing you should not install
from a stranger without reading.

- **Read `hooks/block-dangerous.sh` first.** It is one bash script. It reads JSON on
  stdin, and it either exits 0 (allow, no output) or prints `BLOCKED: <reason>` to
  stderr and exits 2 (deny, with the reason shown to the agent). It never modifies
  anything.
- **Pin a tag or a commit.** Do not install from a branch that moves under you, and
  do not use `--link` against a checkout you will later `git pull` without reading
  the diff.
- **Always dry-run.** `install.sh --dry-run` prints every path it would touch.
- **Nothing is installed outside `$HOME`.** Scratch files go to `$TMPDIR` while a
  run lasts and are removed. Every file that already existed and was not installed
  by this kit is copied to `<file>.bak-<YYYYmmdd-HHMMSS>` before it is replaced,
  and the path is printed.
- **`~/.claude/settings.json` is merged, never overwritten.** The installer unions
  the `deny` and `ask` permission lists and adds hook entries keyed by their command
  string. It does not touch `defaultMode` or any other key. It never sets a
  permission mode that would let an agent act without asking.
- **Every path is recorded** in `$MULTI_AGENT_CODING_HOME/manifest.txt`, which is
  what makes the uninstaller precise instead of destructive.

If you want an agent to do the install for you, hand it
[AGENT-INSTALL.md](AGENT-INSTALL.md) — it is written as a contract that forbids
exactly the shortcuts an eager agent would otherwise take.

## Uninstall

```bash
bash multi-agent-coding/uninstall.sh                     # remove what the manifest lists
bash multi-agent-coding/uninstall.sh --restore-backups   # and restore the newest .bak-* of each replaced file
bash multi-agent-coding/install.sh --uninstall           # same thing, from the installer
```

The uninstaller reads `manifest.txt` and removes only its own files and symlinks,
only the hook entries whose command points into the install prefix, and only the
permission entries it added. It unsets `statusLine` only if the value is the one it
installed. Anything it decided not to touch is printed, so you can finish by hand.

Three things survive on purpose: `project_doc_max_bytes` in `~/.codex/config.toml`
(a raised cap harms nothing), every `.bak-*` file, and an otherwise empty
`~/.claude/settings.json` that the installer created.

## Layout

```
multi-agent-coding/
  README.md  AGENT-INSTALL.md  ROADMAP.md  CHANGELOG.md
  install.sh  doctor.sh  uninstall.sh      # bash 3.2, all support --help
  lib/kit.sh                               # detection, backup, JSON merge, manifest
  rules/core.md                            # the one rules file, CLI-agnostic
  templates/AGENTS.md  templates/PLAN.md
  hooks/block-dangerous.sh
  config/permissions.json                  # deny/ask fragment, merged into settings
  config/hooks.json                        # PreToolUse fragment, merged into settings
  claude/statusline-command.sh
  claude/agents/test-author.md
  claude/skills/context-init/SKILL.md  claude/skills/techdebt/SKILL.md
  tools/agentsify  tools/plan-init
  githooks/pre-commit                      # gitleaks over staged changes
  docs/                                    # os-support, per-cli-paths, cross-model-review, limitations
  extras/README.md                         # macOS widgets: what they are, status
  tests/                                   # run-tests.sh + test-*.sh, green on macOS and Ubuntu
```

Every managed file carries a `managed-by: multi-agent-coding` marker within its
first 20 lines — below the YAML frontmatter in the agent and skill files; the JSON
fragments carry none. That marker is how the installer tells its own files from
yours, and it is why reinstalling is idempotent instead of backing up its own
previous copy.

## Requirements

`git`, `bash` 3.2 or newer (the macOS default qualifies), and `jq` for levels 2 and 3.
Optional: `gitleaks` for the pre-commit hook. `doctor.sh` reports
what is missing.

## License

MIT. See [LICENSE](../LICENSE) at the repository root.
