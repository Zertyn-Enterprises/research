<!-- managed-by: multi-agent-coding -->
# Agent-guided install

Paste this page to any coding agent — Claude Code, Codex, Grok Build, Gemini CLI,
Cursor, anything with a shell — when you want it to install this kit for you.
Everything below is addressed to the agent.

---

You are installing `multi-agent-coding` into this machine's `$HOME`. This is a
configuration change to the user's own tooling, so the user approves each step. You
run commands and report; you do not decide.

Work through the seven steps in order. Do not skip ahead. Do not batch the
confirmations.

## 1. Diagnose, then paste the output

```bash
bash multi-agent-coding/doctor.sh
```

`doctor.sh` is read-only. Paste its complete output into your reply — do not
summarise it. It reports the operating system (macOS, Linux, or WSL2), the bash
version, whether `git`, `jq`, `gitleaks` and `python3` are present, which CLIs it
detected, and every existing file that an install would back up.

If it reports a missing `jq`, say so: levels 2 and 3 need it and the installer
refuses them without it. Levels 1 and 4 still work.

## 2. Ask which levels the user wants

Show the four levels and ask. Do not assume all four.

| Level | Name | What it changes |
|---|---|---|
| 1 | `rules` | Writes the shared rules file into each detected CLI's global instruction path. |
| 2 | `safety` | Wires a `PreToolUse` hook that can block a shell command, merges a deny/ask permission fragment into `~/.claude/settings.json`, and may set a global git hooks path. |
| 3 | `claude-quality` | Claude Code only: statusline, one agent, two skills, two commands in `~/.local/bin`. |
| 4 | `plan` | Two templates in the install prefix. |

Say plainly that level 2 is the one that can interrupt commands the user wanted to
run, and that level 3 has no effect on Codex or Grok Build.

## 3. Dry-run, and show every path

```bash
bash multi-agent-coding/install.sh --dry-run --level <N>
# or, for a single level:
bash multi-agent-coding/install.sh --dry-run --only <rules|safety|claude-quality|plan>
```

Paste the full list of paths. If the user asked for `--link` instead of copies, add
`--link` to the dry run as well, and tell them the consequence: the installed files
become symlinks into this checkout, so a later `git pull` changes their behaviour
without another install.

## 4. Get an explicit confirmation before each of these three things

Ask separately. A single "go ahead" earlier in the conversation does not cover all
three.

1. **Writing anything under `$HOME`.** Name the directories: `~/.claude`,
   `~/.codex`, `~/.grok`, `~/.local/bin`, and the install prefix
   (`$MULTI_AGENT_CODING_HOME`, default `~/.multi-agent-coding`).
2. **Touching `~/.claude/settings.json`.** Say that it is a merge, not a rewrite:
   union of the `deny` and `ask` lists, plus hook entries keyed by command string.
   Show the user their current file first if it exists.
3. **Running `git config --global core.hooksPath`.** This is global git state. The
   installer only does it when no global hooks path is set; if one is set, it prints
   how to chain and skips. Confirm before the write either way.

Then run the real install with the same flags as the dry run, minus `--dry-run`,
plus `--yes`. You are not a terminal: without `--yes` the installer cannot ask its
per-level questions, so it writes nothing and exits. Add `--yes` only after the
user has approved the exact plan you printed.

## 5. Forbidden, whatever the reason

- Do not create, invent, or fill in any secret, token, API key, or credential.
- Do not set `permissions.defaultMode` to `auto`, `acceptEdits`, `bypassPermissions`
  or any other value. The installer never touches that key and neither do you.
- Do not remove or weaken entries from the `deny` or `ask` lists to make a command
  run.
- Do not download or run any third-party installer, package, or script that is not
  in this checkout. Installing `jq` or `gitleaks` is the user's call, with the
  user's own package manager, after you have told them the command.
- Do not edit any file outside the paths the dry run printed. If something looks
  wrong, report it; do not fix it.
- Do not use `sudo`.
- Do not delete a `.bak-*` file. Those are the user's rollback.

## 6. Verify, then report what was skipped

```bash
bash multi-agent-coding/doctor.sh
bash multi-agent-coding/tests/run-tests.sh
```

The suite exits `0` when every test passed, `1` on any failure, and `3` when
anything was skipped. A skip is not a pass. Report:

- which levels were installed, and every path written;
- every file that was backed up, with its `.bak-*` name;
- the test result, including the exit code and each skipped test with its reason
  (usually a missing optional binary);
- anything the installer printed that it decided not to touch.

Tell the user to restart each CLI, and how to confirm the rules loaded: Claude Code
`/memory`, Grok Build `grok inspect`. For Codex, the rules are a single file at
`~/.codex/AGENTS.md`; confirm it exists and that `project_doc_max_bytes` in
`~/.codex/config.toml` is at least the file's size.

If the user wants it gone:

```bash
bash multi-agent-coding/uninstall.sh --restore-backups
```

## 7. If this is native Windows, stop

If step 1 reports Windows without WSL2 — PowerShell or `cmd`, no `/proc/version`
containing `microsoft` — do not attempt the install. Tell the user that this kit is
bash-only and needs WSL2, point them at `docs/os-support.md`, and stop. Do not try
to translate the scripts, do not install a shell, and do not partially apply the
configuration by hand.
