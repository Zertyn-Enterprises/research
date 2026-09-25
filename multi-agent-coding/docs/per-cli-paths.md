<!-- managed-by: multi-agent-coding -->
# Where each CLI reads its global configuration

This is the map the installer works from. Every claim below is either backed by the
vendor's own documentation (URL inline) or marked as not verified by us.

## At a glance

| | Claude Code | Codex CLI | Grok Build |
|---|---|---|---|
| Global rules | `~/.claude/rules/*.md` | `~/.codex/AGENTS.md` (one file) | `~/.grok/rules/*.md` and `~/.claude/rules/*.md` |
| Size cap | no documented cap | `project_doc_max_bytes`, default 32 KiB | no character cap for instruction files |
| Agents | `~/.claude/agents/*.md` | not applicable | Claude's, via compatibility |
| Skills | `~/.claude/skills/<name>/SKILL.md` | `~/.agents/skills` (not verified by us) | `~/.grok/skills` (not verified by us) |
| Hooks | `hooks` key in `~/.claude/settings.json` | `~/.codex/hooks.json` | `~/.grok/hooks/*.json` |
| Deny on hook | exit 2, stderr is the reason | exit 2, stderr is the reason | exit 2 denies |
| Permissions | `permissions` key in `~/.claude/settings.json` | not applicable | Claude's, via compatibility |
| What this kit writes | levels 1-3 | level 1 rules + level 2 hook | level 2 hook; rules only if Claude Code is absent |

## Claude Code

**Rules.** Files in `~/.claude/rules/` are user rules and apply to every project
([memory](https://code.claude.com/docs/en/memory)). That is why level 1 can install
one file and have it apply everywhere, with no per-repo step. The kit writes exactly
one file, `~/.claude/rules/core.md`, and leaves any other file in that directory
alone.

**Config directory.** If `CLAUDE_CONFIG_DIR` is set in your environment, that is the
config root instead of `~/.claude`. `doctor.sh` warns when it sees it and uses it.

**Agents and skills.** `~/.claude/agents/test-author.md` is a subagent definition.
`~/.claude/skills/context-init/SKILL.md` and `~/.claude/skills/techdebt/SKILL.md` are
skills, each with the standard `name` and `description` frontmatter. Level 3 installs
these three files and nothing else in those directories.

**Hooks.** Hooks live under the `hooks` key of `~/.claude/settings.json`. A hook that
exits with code 2 blocks the tool call, and its stderr is fed back to the model as
the reason ([hooks](https://code.claude.com/docs/en/hooks)). `block-dangerous.sh`
relies on exactly that: `echo "BLOCKED: <reason>" >&2; exit 2`. Level 2 merges its
entry rather than replacing the key, and keys the entry by its command string so a
reinstall does not duplicate it.

**Permissions.** Path rules must be written as `Edit(path)` or `Read(path)`. A
`Write(...)` rule is accepted by the settings parser but is never consulted
([permissions](https://code.claude.com/docs/en/permissions)). This is not a
theoretical detail: a `Write(.env)` entry looks like it protects your secrets file
and does nothing at all. `config/permissions.json` uses `Edit(...)` throughout.
Level 2 merges the `deny` and `ask` lists as set unions and does not touch
`defaultMode` or any other key.

**The `Notification` hook event** fires on `permission_prompt`, `idle_prompt`,
`elicitation_dialog` and `auth_success` ([hooks](https://code.claude.com/docs/en/hooks)).
Nothing in v0.1 uses it; it is the mechanism the roadmap's Linux and WSL2 desktop
notifications would use instead of a macOS menu-bar widget.

## Codex CLI

**Rules.** Codex reads one global instructions file, `~/.codex/AGENTS.md`, or
`~/.codex/AGENTS.override.md` if present
([AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md)). There is
no imports mechanism to split it, so level 1 copies the whole rules file there rather
than linking a directory. The `learn.chatgpt.com/docs/…` pages cited here are where
`developers.openai.com/codex/…` redirects (HTTP 308, checked 2026-09-26); both
hostnames are OpenAI's.

**The 32 KiB cap matters.** `project_doc_max_bytes` defaults to 32 KiB (same page),
and the rules file is large enough that the default would truncate it — silently,
mid-sentence, taking whichever sections happen to fall past the limit with it. Level 1
therefore patches `project_doc_max_bytes = 131072` into `~/.codex/config.toml`, but
only if the key is absent or lower than the rules file's size. It is a single-key
edit: the file is backed up first, rewritten through a temporary file, and created if
it did not exist. No other key is touched.

**Hooks.** Codex hooks live in `~/.codex/hooks.json`, use the same JSON shape as
Claude Code's, and a hook that exits 2 blocks the call
([hooks](https://learn.chatgpt.com/docs/hooks)). Level 2 writes or merges that file
idempotently, keyed by the command string, with the same `block-dangerous.sh` script
that Claude Code gets. We have not verified the dispatch end to end on this machine;
the shape follows the vendor's documentation.

**Skills.** Codex is documented to read skills from `~/.agents/skills`. Not verified
by us, and the kit installs nothing there — the level 3 pack is Claude Code only.

## Grok Build

**Rules.** `$GROK_HOME/rules/` (default `~/.grok/rules/`) is always scanned, and
`~/.claude/rules/` is scanned too through the `compat.claude.rules` setting, which is
on by default. There is no character cap for instruction files
([project rules](https://raw.githubusercontent.com/xai-org/grok-build/main/crates/codegen/xai-grok-pager/docs/user-guide/12-project-rules.md)).

We verified this on Grok 1.0.41 with `grok inspect`, which lists
`~/.claude/rules/core.md` as a loaded global instruction and also loads Claude skills,
agents and permissions.

**So level 1 writes nothing under `~/.grok` when Claude Code is present.** Installing
the same rules in both places would load them twice, which wastes context and — worse
— makes a partial update look like a contradiction between two instruction sources.
The installer prints that Grok reads the Claude rules directory and tells you to
confirm with `grok inspect`. Only when Claude Code is absent does it write
`~/.grok/rules/core.md`.

**Hooks.** Grok hooks are JSON files in `~/.grok/hooks/`. The payload on stdin uses
`toolName` and `toolInput` rather than Claude's `tool_name` and `tool_input`, exit 2
denies the call, and a `Bash` matcher is aliased to Grok's own
`run_terminal_command` ([hooks](https://raw.githubusercontent.com/xai-org/grok-build/main/crates/codegen/xai-grok-pager/docs/user-guide/10-hooks.md)).
`block-dangerous.sh` handles both payload spellings —
`jq -r '.tool_input.command // .toolInput.command // empty'` — and never inspects the
tool name itself, which is what lets one script serve all three CLIs.

Grok's documentation says hooks configured in `~/.claude/settings.json` also load
through the compatibility layer. We have not verified that they are dispatched, and
community reports say they are not, so level 2 writes the native file
`~/.grok/hooks/multi-agent-coding.json` instead. That whole file belongs to the kit,
so the uninstaller can remove it cleanly.

## Kimi Code and GLM (Z.ai) coding plans

These are not separate CLIs. Both run inside Claude Code: you set
`ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` to the provider's endpoint and keep
using the same binary and the same `~/.claude` directory
([Z.ai](https://docs.z.ai/devpack/tool/claude.md),
[Kimi Code](https://moonshotai.github.io/kimi-code/en/)).

Consequences worth stating out loud:

- They inherit levels 1, 2 and 3 with no extra install step.
- They share one `~/.claude`, so they share your rules, your permissions, your hooks
  and your session history. There is no per-provider isolation unless you set
  `CLAUDE_CONFIG_DIR` yourself.
- For cross-model review, a Kimi or GLM session is a genuinely different model
  family from Claude even though the harness is the same. That is the cheapest way
  to get a second opinion if you already pay for one of these plans.

`doctor.sh` prints this note whenever it detects Claude Code, because the directory
alone cannot tell it which provider you are pointed at.

## Not supported in v0.1

Gemini CLI, OpenCode and Cursor. Each has its own global instruction path and its own
hook model, and neither is wired up here. The rules file itself is plain markdown and
can be copied into any of them by hand; the installer will not do it for you.
