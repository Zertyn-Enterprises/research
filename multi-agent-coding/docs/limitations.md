<!-- managed-by: multi-agent-coding -->
# Limitations

What this kit does not do, and where it is unverified. Read it before you rely on
any of it. v0.1.

## What we actually tested

| Platform | Status |
|---|---|
| macOS 15 (Apple silicon), bash 3.2 | developed and tested here |
| `ubuntu-latest` in CI | full test suite on every push |
| Windows + WSL2 | expected to work, **not verified by us**, not in CI |
| Debian, Fedora, Arch, Alpine | **not verified by us** |
| Native Windows | not supported, see [os-support.md](os-support.md) |

The suite covers the installer's plan and idempotency, the settings merge, the
uninstaller, the safety hook's decisions, the statusline, `agentsify`,
`plan-init`, and a scrub that greps the package for private strings. It does not
launch a real CLI and watch a real hook fire. That gap is the honest boundary of
"tested".

## Per-CLI gaps

- **Claude Code** is the only CLI that gets the full kit. Levels 1 and 2 reach all
  three; level 3 — statusline, `test-author` agent, `context-init` and `techdebt`
  skills — is Claude Code only.
- **Codex hook dispatch is not verified by us.** Level 2 writes
  `~/.codex/hooks.json` in the shape the vendor documents, with the same exit-2
  contract. We have not watched it block a command on this machine. If you rely on
  the safety floor in Codex, verify it yourself with a harmless test command.
- **Grok Build's rules compatibility is verified; its hook compatibility is not.**
  `grok inspect` on Grok 1.0.41 lists `~/.claude/rules/core.md` as a loaded global
  instruction and also loads Claude skills, agents and permissions — that much we
  confirmed. Whether hooks declared in `~/.claude/settings.json` are dispatched is
  not verified, and community reports say they are not, which is why level 2 writes
  Grok's native hook file instead.
- **Gemini CLI, OpenCode and Cursor are not supported.** The rules file is plain
  markdown and you can paste it into any of them; the installer will not.
- **Kimi Code and GLM share one `~/.claude`.** There is no per-provider isolation
  unless you set `CLAUDE_CONFIG_DIR` yourself. Your rules, permissions, hooks and
  history are common to all providers you point Claude Code at.

## The safety hook is a floor, not a sandbox

This is the most important limitation on the page.

- **It only sees shell commands.** It is a `PreToolUse` hook on the shell tool. An
  agent that writes a destructive command into a script file and runs the script,
  or that does damage through a file-editing tool, is outside its view. The
  permission fragment covers some of that; neither is a boundary.
- **It matches patterns.** It blocks the specific shapes it knows: recursive
  deletes of `/` or `~`, disk-level writes, `chmod -R 777`, piping a remote script
  to a shell, pushes to a protected branch, reads of SSH keys and credential
  files, `DROP TABLE` and mass deletes. A command that means the same thing in a
  spelling it does not recognise gets through.
- **Deploys, publishes and repo-settings changes are not in the hook.** Those live
  in the permission fragment as `ask` rules (`vercel deploy`, `npm publish`,
  `git config --global`, …). Claude Code enforces them, and Grok Build reads the
  same file through its compatibility layer; Codex does not read Claude
  permissions, so on Codex those commands are guarded only by the rules text.
- **It fails open on input it cannot read.** A payload with no command (an empty
  or malformed stdin, or a CLI whose payload shape we do not parse) is allowed.
  Blocking blind would break every CLI we have not tested.
- **It is not an adversarial control.** It exists to stop a confident mistake, not a
  determined attempt. Do not treat it as a reason to give an agent broader
  permissions than you otherwise would.
- **Rules are instructions, not enforcement.** Everything in `rules/core.md` is
  advisory: the model may ignore it. The hook and the permission lists are the only
  parts with teeth, and their reach is what this section describes.

## Installer constraints

- **`jq` is required for level 2 and above.** The settings merge is a jq transform.
  Without jq, levels 2 and 3 cannot run; `doctor.sh` reports it.
- **bash 3.2 is the floor**, which rules out associative arrays, `mapfile`, and
  in-place `sed -i`. If you send a patch, it has to hold to that.
- **A global `core.hooksPath` already set wins.** Level 2 will not overwrite it. It
  prints how to chain the gitleaks hook and skips, which means you do not get the
  pre-commit scan until you wire it yourself.
- **`gitleaks` is optional.** Without it, the pre-commit hook prints a one-line
  warning and exits 0. It does not fail your commit and it does not scan anything.
- **`~/.local/bin` may not be on your `PATH`.** Level 3 warns; it does not edit your
  shell profile. This kit never touches `~/.zshrc`, `~/.bashrc`, or any other
  profile.
- **`~/.codex/config.toml` gets a single-key edit.** Level 1 raises
  `project_doc_max_bytes` because the 32 KiB default truncates the rules file. The
  file is backed up first. If your config.toml has unusual structure, check the
  result.
- **The uninstaller is only as good as the manifest.** It removes what
  `$MULTI_AGENT_CODING_HOME/manifest.txt` records. If you move or hand-edit
  installed files, it will tell you what it left alone rather than guess. Files you
  created yourself are never removed.
- **`--link` couples your config to this checkout.** A later `git pull` changes the
  behaviour of installed hooks and rules without another install. That is either the
  feature you wanted or a supply-chain problem you created; pick deliberately.

## Not shipped in v0.1

All of these are documented in [../ROADMAP.md](../ROADMAP.md) and none of them are
installed, enabled, or partially present:

cross-model review (`xreview` and its PR gate) · session coordination ledger ·
fleet and tmux navigation · token and cost ledger · menu-bar widgets, macOS only ·
design-quality rules and the design-system skill · provider wrappers for Kimi, GLM
and MiniMax.

The rules file references the review practice as a practice, because it is worth
doing by hand. It does not reference any command that this version does not
install.

## Not a product

One person's working setup, generalised and published. There is no support
commitment, no compatibility promise across versions, and the vendors' CLIs change
faster than this repository does. Pin a tag, read the diff before you upgrade, and
keep your `.bak-*` files until you are sure.
