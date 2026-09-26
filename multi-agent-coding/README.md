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
| `--yes` | Skip the per-level prompts. Use it only after a dry run. |
| `--link` | Symlink into the cloned checkout instead of copying. Updates follow `git pull`. |
| `--level N` | Install levels 1 through N (see the table below). |
| `--only LIST` | Install exactly these levels: a comma-separated list of names or numbers, e.g. `--only rules,safety` or `--only 2`. |
| `--prefix DIR` | Install prefix (must be inside `$HOME`). Same as `MULTI_AGENT_CODING_HOME`. |
| `--uninstall` | Delegate to `uninstall.sh`; remaining flags are passed through. |
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
| `MULTI_AGENT_CODING_HOME` | `$HOME/.multi-agent-coding` | Install prefix. Holds the copied hook, git hooks, templates and `manifest.txt`. |
| `MAC_PROTECTED_BRANCHES` | `main master` | Branches the safety hook refuses to push to directly. |
| `CLAUDE_CONFIG_DIR` | unset | Honoured when set: the installer uses it instead of `~/.claude` and warns. |
| `MAC_SKIP_PATH_DETECT` | unset | `1` detects CLIs by config directory only, ignoring `PATH`. Used by the tests. |

## Levels

Levels are opt-in and can be selected in any combination. One dependency: the
`agentsify` and `plan-init` commands from level 3 read the templates that level 4
installs, so take both or neither.

| Level | Name | What it writes |
|---|---|---|
| 1 | `rules` | The shared rules file into each CLI's global instruction path: `~/.claude/rules/core.md` for Claude Code, `~/.codex/AGENTS.md` for Codex (plus `project_doc_max_bytes = 131072` in `~/.codex/config.toml`, because the default 32 KiB truncates the file). Grok Build already reads `~/.claude/rules/`, so nothing is written under `~/.grok` unless Claude Code is absent. |
| 2 | `safety` | `block-dangerous.sh` into the install prefix, wired as a `PreToolUse` hook in every CLI that is present. A deny/ask permission fragment merged into `~/.claude/settings.json`. A `gitleaks` pre-commit hook, enabled with `git config --global core.hooksPath` only if you have no global hooks path already. |
| 3 | `claude-quality` | Claude Code only: a statusline, the `test-author` agent, the `context-init` and `techdebt` skills, and `agentsify` + `plan-init` symlinked into `~/.local/bin`. |
| 4 | `plan` | The `AGENTS.md` and `PLAN.md` templates into the install prefix, where `agentsify` and `plan-init` read them. |

Level 1 is the whole point of the kit. Level 2 is the part that can block a command
you wanted to run. Level 3 only touches Claude Code.

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
with no extra work, and the doctor says so.

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
| Windows 10/11 via WSL2 | Supported. Install inside the Linux distribution, not on the Windows side. |
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

Having a second model family review your diff catches real bugs, and it costs real
money and real time. Be honest about the arithmetic before you build it into your
workflow:

- **Each review is a full session of another model.** It reads the diff and the
  surrounding code with its own context window and its own quota.
- **You need at least two subscriptions** from different vendors. A model reviewing
  its own family's output is not a second opinion.
- **Panel mode multiplies the cost** by the number of families you ask. Three
  reviewers means three full sessions and three times the wait.

So decide per change, not once per project:

| Change | Reviewers |
|---|---|
| Docs, comments, formatting, a one-line fix | none |
| Normal application code | one, from another family |
| 🔴 money, entitlements, auth, persisted data, shared contracts | panel |

**This module is not in v0.1.** The rules file tells your agent to get an
independent review when a second family is available, and to say plainly when none
ran. Automating it (an `xreview` command plus a pre-PR gate) is on the
[roadmap](ROADMAP.md). The reasoning, the cost model, and how the future module
degrades to `SKIPPED` rather than a blocked PR when you only have one subscription:
[docs/cross-model-review.md](docs/cross-model-review.md).

## Widgets and extras

A menu-bar session index and a token-cost menu bar exist, are macOS-only, and are
**not** in v0.1. What they need, and how a Linux or WSL2 user gets the same signal
from a `Notification` hook instead, is in [extras/README.md](extras/README.md).

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

Every managed file starts with a `managed-by: multi-agent-coding` marker line. That
marker is how the installer tells its own files from yours, and it is why
reinstalling is idempotent instead of backing up its own previous copy.

## Requirements

`git`, `bash` 3.2 or newer (the macOS default qualifies), and `jq` for levels 2 and 3.
Optional: `gitleaks` for the pre-commit hook, `python3`. `doctor.sh` reports
what is missing.

## License

MIT. See [LICENSE](../LICENSE) at the repository root.
