<!-- managed-by: multi-agent-coding -->
# Roadmap

v0.1 ships the parts that are useful to everyone: one rules file for every CLI, a
destructive-command floor, a small Claude Code quality pack, and an installer you
can dry-run and uninstall.

Everything below exists in some form in the setup this kit was extracted from, and
is **not** in v0.1. None of it is installed, enabled, or half-present — if you
install v0.1 you get v0.1. Each module will be opt-in and off by default when it
lands.

Status is `planned` for all of them. There are no dates.

## Modules

| Module | What it does | Requirements | Status |
|---|---|---|---|
| Cross-model review | An `xreview` command that has another model family review the current diff and print `OK` / `ISSUES` / `BLOCK`, plus a hook that gates PR creation until the current tree has been reviewed. | Two or more paid subscriptions from different vendors; each review is a full session of another model. See [docs/cross-model-review.md](docs/cross-model-review.md). | planned |
| Session coordination ledger | A machine-local record of which session is on which repo and branch, so parallel sessions notice each other before two of them fix the same thing twice. Surfaced to the agent as a prompt-time note. | A CLI with prompt and stop hooks; `jq`. | planned |
| Fleet and tmux navigation | A session index plus commands to jump between repos, worktrees and the tmux windows running agents in them. | tmux; a Unix shell; conventions about where worktrees live. | planned |
| Token and cost ledger (`tokuse`) | Per-session and per-day token and spend accounting, written from the CLI's own session data, with a locked append-only store. | `python3`; `fcntl`, which is Unix-only, so WSL2 rather than native Windows. | planned |
| Menu-bar widgets | A macOS menu-bar session index and a menu-bar spend readout. Live under [extras/](extras/README.md). | macOS 13+, the fleet module, tmux, and a terminal the index can raise through Accessibility — currently Ghostty. | planned |
| Design-quality rules | A `# Design Quality` rules section and a `design-system` skill for tokens-first UI work. Cut from the v0.1 rules file because the section is meaningless without the skill. | Nothing beyond level 1, once both ship together. | planned |
| Provider wrappers | Thin launchers for the Kimi Code and Z.ai (GLM) coding plans, and for MiniMax, that set the endpoint and token and keep each provider's history separate. | A subscription to the provider; `CLAUDE_CONFIG_DIR` per provider if you want isolation. | planned |

## Principles these will hold to

Any module that lands here inherits the v0.1 contract, because that contract is the
reason the kit is safe to install at all:

1. **Opt-in, off by default.** A module is a level or a flag you ask for, never
   something that appears because you upgraded.
2. **Dry-run first.** Every writer prints the exact paths it would touch.
3. **Backup and manifest.** Nothing is replaced without a `.bak-<timestamp>` copy,
   and nothing is written without a manifest line the uninstaller can read back.
4. **Merge, never overwrite, shared config.** `~/.claude/settings.json` and friends
   are merged by key, and `defaultMode` is never touched.
5. **Degrade, do not block.** A module that cannot do its job says so — the
   cross-model gate reports `SKIPPED` when you have one subscription, it does not
   stop you opening a PR.

## Not planned

- **Native Windows.** A PowerShell port of the installer and the hook is a separate
  project, not a compatibility flag. Use WSL2; see
  [docs/os-support.md](docs/os-support.md).
- **A hosted service, telemetry, or any network call at install time.** The
  installer reads and writes local files and nothing else.
- **A sandbox.** Each CLI has its own, and this kit does not try to be one. The
  safety hook is a floor against confident mistakes — see
  [docs/limitations.md](docs/limitations.md).
