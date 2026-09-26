<!-- managed-by: multi-agent-coding -->
# Changelog

## 0.1.2 — unreleased

### Fixed

- The "text piped into a shell" rule fires only when the shell reads its stdin
  (`| sh`, `| bash -`, `| sh -s`, `| bash -x`). A shell given a script operand
  (`| bash lint.sh`) runs the file, not the text — which is how the kit's own
  smoke test is spelled, and it was being blocked from inside Claude Code.
- `docs/os-support.md`: set the Windows Terminal profile's starting directory to
  the Linux home, or every tab opens in `/mnt/c`.

## 0.1.1 — 2026-09-26

### Fixed

- `doctor.sh` lists destination directories that are symlinks to a missing target
  (a `~/.claude/rules -> …` copied from another machine, for example) under
  "blocking" and exits 1, so `install.sh` stops before writing anything instead of
  dying halfway on `mkdir`. `docs/os-support.md` gains the first-machine steps for a
  fresh WSL2 distribution: git identity, SSH key or `gh auth login`, CLIs installed
  inside the distribution.

## 0.1.0 — 2026-09-26

First release under the name `multi-agent-coding`. It replaces the Claude-Code-only
`claude/` directory that used to live at the repository root.

### Added

- **`rules/core.md`** — one CLI-agnostic rules file covering agent behaviour,
  coding discipline, code quality, git and safety, plan and brief, cross-session
  work, and the repo file map. Sections are cited by name (`Git & Safety §3`), which
  is the contract the hook and the templates depend on.
- **Multi-CLI install (level 1).** Claude Code (`~/.claude/rules/core.md`), Codex
  (`~/.codex/AGENTS.md`, plus `project_doc_max_bytes = 131072` in
  `~/.codex/config.toml`: the 32 KiB default is a combined budget for the global file
  and every project `AGENTS.md` Codex loads, so a 29 KB global file would leave almost
  nothing for the repo's own), and Grok
  Build (which reads the Claude rules directory through its compatibility layer, so
  nothing is written under `~/.grok` unless Claude Code is absent).
- **Safety floor (level 2).** `hooks/block-dangerous.sh`, one script wired as a
  `PreToolUse` hook in every present CLI — Claude Code via `~/.claude/settings.json`,
  Codex via `~/.codex/hooks.json`, Grok Build via
  `~/.grok/hooks/multi-agent-coding.json`. It reads both payload spellings
  (`tool_input.command` and `toolInput.command`) and blocks with `exit 2` plus a
  stderr reason, which all three CLIs honour. Protected branches come from
  `MAC_PROTECTED_BRANCHES` (default `main master`).
- **Permission fragment (level 2).** `config/permissions.json`, merged as a set union
  into the `deny` and `ask` lists of `~/.claude/settings.json`. Linux equivalents of
  the macOS footguns are included.
- **`gitleaks` pre-commit hook (level 2)**, installed into the kit prefix and enabled
  with `git config --global core.hooksPath` only when no global hooks path is already
  set. Without `gitleaks` on `PATH` it warns once and exits 0.
- **Claude Code quality pack (level 3).** A statusline, the `test-author`
  implementation-blind test-writing agent, the `context-init` and `techdebt` skills,
  and the `agentsify` and `plan-init` commands symlinked into `~/.local/bin`.
- **Templates (level 4).** `templates/AGENTS.md` and `templates/PLAN.md`, read by
  `agentsify` and `plan-init`.
- **`doctor.sh`** — read-only diagnosis: OS (macOS, Linux, or WSL2 detected through
  `/proc/version`), bash version, `git` / `jq` / `gitleaks`, which CLIs
  are present, a note that Kimi Code and GLM share `~/.claude`, a warning when
  `CLAUDE_CONFIG_DIR` is set, and every file an install would back up.
- **`install.sh`** with `--dry-run`, `--yes`, `--link`, `--level N`,
  `--only rules|safety|claude-quality|plan`, `--prefix DIR`, `--uninstall` and
  `--help`. Interactive runs ask once per level; selecting `claude-quality` adds
  `plan`, whose templates its two commands read. Exit codes: 0 success, 1 error,
  2 usage.
- **`uninstall.sh`** with `--dry-run`, `--yes`, `--prefix DIR` and
  `--restore-backups`. It reads
  `$MULTI_AGENT_CODING_HOME/manifest.txt` and removes only its own files, links, hook
  entries and permission entries, then prints what it left alone.
- **Backups and a manifest for every write.** A pre-existing file that is not ours is
  copied to `<file>.bak-<YYYYmmdd-HHMMSS>` before it is replaced, and the path is
  printed. Reinstalling over our own files is silent and idempotent.
- **Tests** that run on macOS and `ubuntu-latest` in CI, including a scrub that greps
  the whole package for private strings.
- **Docs**: `README.md`, `AGENT-INSTALL.md` (a contract you can paste to any agent to
  have it install the kit), `ROADMAP.md`, `docs/os-support.md`,
  `docs/per-cli-paths.md`, `docs/cross-model-review.md`, `docs/limitations.md`, and
  `extras/README.md`.

### Changed

- **Layout.** The old `claude/` directory is now `multi-agent-coding/`, and its
  `claude/install.sh` and `claude/README.md` are gone — this package's installer and
  docs replace them. Update any link or bookmark that pointed at `claude/`.
- **Four rules files became one.** `agent-behavior.md`, `coding-discipline.md`,
  `code-quality.md` and `git-and-safety.md` are merged into `rules/core.md`, with the
  section names preserved so citations still resolve. If you installed the old
  version, delete those four files from `~/.claude/rules/` after installing this one.
- **`settings.example.json` is gone.** Settings are no longer a file you copy and
  merge by hand; `config/permissions.json` and `config/hooks.json` are fragments the
  installer merges with `jq`, keyed so that reinstalling does not duplicate entries.
  Three things the old template carried are not shipped by this version: its `env`
  block (`CLAUDE_CODE_DISABLE_AUTO_MEMORY`, `CLAUDE_CODE_DISABLE_GIT_INSTRUCTIONS`,
  `BASH_MAX_OUTPUT_LENGTH`), its `effortLevel`, and `permissions.defaultMode`. If you
  copied that file, they are still in your `~/.claude/settings.json`; this installer
  neither writes nor removes them.
- **Rules are CLI-agnostic.** The old rules named one harness's tooling. The
  discipline is unchanged; the wording now maps onto whichever CLI you run.

### Fixed

- **`.env` was not actually protected.** The old settings template used
  `Write(.env)`. Path permission rules must be written as `Edit(path)` or
  `Read(path)`; a `Write(...)` rule is accepted by the settings parser and then never
  consulted ([permissions](https://code.claude.com/docs/en/permissions)). So the
  entry looked like a guard on your secrets file and did nothing. Every path rule in
  `config/permissions.json` now uses `Edit(...)` or `Read(...)`. If you installed the
  old template, check your `~/.claude/settings.json` for `Write(` entries and convert
  them.

### Not included in 0.1.0

Cross-model review (`xreview` and its PR gate), the session coordination ledger,
fleet and tmux navigation, the token and cost ledger, the macOS menu-bar widgets,
design-quality rules and the design-system skill, and provider wrappers for Kimi, GLM
and MiniMax. All are documented in `ROADMAP.md` as planned and off by default.
Native Windows is not supported; use WSL2. Gemini CLI, OpenCode and Cursor are not
wired up.
