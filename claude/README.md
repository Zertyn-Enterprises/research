# Claude Code config — portable rules + settings

The operating rules I run Claude Code with, plus a settings template. Drop them
into your own `~/.claude` and get the same engineering discipline and safety
guardrails.

## What's inside

- `rules/` — four discipline docs, auto-loaded into every Claude Code session:
  - `agent-behavior.md` — how the agent communicates; the "never present
    inference as fact" hard rule.
  - `coding-discipline.md` — think-before-coding, simplicity, surgical changes.
  - `code-quality.md` — tests, types, lint, validation, security gates.
  - `git-and-safety.md` — git discipline, secret hygiene, destructive-command floor.
- `settings.example.json` — a permission model (deny footguns, confirm on
  deploys/publishes/force-push) plus a couple of sane defaults.
- `install.sh` — copies the above into `~/.claude`.

## Install

```bash
git clone https://github.com/Zertyn-Enterprises/research.git
bash research/claude/install.sh
```

The installer:
- copies `rules/*.md` → `~/.claude/rules/` (auto-loaded at session start),
- installs `settings.example.json` → `~/.claude/settings.json` **only if you
  don't already have one** (otherwise it writes `settings.example.json` for you
  to merge),
- backs up anything it would overwrite.

Restart Claude Code and run `/memory` to confirm the rules loaded. If your
version doesn't auto-load `~/.claude/rules/`, add these lines to
`~/.claude/CLAUDE.md`:

```
@~/.claude/rules/agent-behavior.md
@~/.claude/rules/coding-discipline.md
@~/.claude/rules/code-quality.md
@~/.claude/rules/git-and-safety.md
```

## Before you rely on it

- **Permission model.** `settings.example.json` sets `defaultMode: auto` (Claude
  proceeds on reversible actions) backed by an `ask` list that forces a
  confirmation on deploys, `npm publish`, force-pushes, `git reset --hard`, and
  `.env` writes, and a `deny` list that hard-blocks `rm -rf /` and reading
  `~/.ssh`. If you'd rather be prompted on everything, set `defaultMode` to
  `default`. Read the block before trusting it.
- **Harness references.** The rules mention "dispatched agents", a
  `headless-dispatch.md`, and a PR flow — those refer to my own automation
  harness. They're harmless if you don't run it; the core discipline is
  universal. Ignore them.
- **Auth is per-machine.** These are rules and settings only — you still sign in
  to Claude Code yourself.
