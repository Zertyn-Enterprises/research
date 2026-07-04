# Git & Safety

Always-on safety floor for git and system commands. Applies to every session,
interactive or dispatched. Most of this is also hard-enforced by the
`block-dangerous` PreToolUse hook — that's the backstop, not a reason to relax.

## 1. Never commit secrets
- API keys, tokens, passwords, OAuth secrets, DB URLs with credentials — never in git.
- `.env`, `.env.local`, `.env.*.local` stay gitignored. Document required vars in `.env.example` (names only).
- Staged a secret by accident? Surface it to the human immediately. Don't silently rewrite history.

## 2. Never run destructive system commands
- `rm -rf /`, `rm -rf ~/`, or any wildcard delete at root.
- `chmod -R 777`, `dd` to a disk device, `mkfs`/`fdisk`/`parted`, `shutdown`/`reboot`.
- Piping a remote script straight to a shell (`curl … | bash`).

## 3. Branch & PR discipline
- Work on a feature branch. Never commit or push to `main`/`master` directly.
- Open PRs for review. Merging to main is how prod deploys — the human drives it.
- Never force-push. Never `git reset --hard` on a branch you didn't create.
- New top-level dependencies need a one-line justification in the PR description.

## 4. Never modify branch protection or repo settings
- Don't change branch-protection rules, required checks, collaborators, or Actions secrets.
- If a task seems to need this, it's a human action — surface it and stop.

## 5. Identity & org boundaries
- Production code lives in your primary GitHub org; every commit there goes through a PR.
- Git identity is set by the environment, not by you. Don't `git config user.*` from a task.
- Don't reference org or repo names you weren't given.

## 6. Deploys, publishes, submits — human actions
- Never run a deploy (`vercel deploy --prod`, `flyctl deploy`, …), a publish (`npm publish`, …), or a store submit (`eas submit`, …).
- Surface it as a next step and stop.

## 7. Database migrations
- Migration files in the PR — yes. Running them against any database (staging/prod) — no.
- Applying a migration is a human action: document the exact command + target, and stop.

## 8. Worktrees & leftovers
- Created a git worktree? Remove it before exiting (`git worktree prune`).
- No temp files, `.bak`, debug artifacts, or commented-out "old code in case we need it" — that's what git history is for.
- Don't commit generated files, `node_modules`, or build artifacts — they belong in `.gitignore`.

## 9. Commit traceability (decisions live in git)
Git history is the durable, compaction-proof record of WHY. Write commits so a
fresh agent — at compaction or at ship — can reconstruct what changed and why
without the conversation.
- Subject: imperative, scoped, specific. Dispatched agents: `<role>(<task-id>): <desc>`.
- Body, whenever the change carries a decision, tradeoff, or reversal:
  - WHAT changed, at a high level.
  - WHY — the decision and the alternative you rejected, one line each.
  - REVERSAL — if it undoes or changes an earlier choice, say so explicitly
    (e.g. "replaces context7 with WebFetch; context7 removed").
- One logical change per commit. Never bundle unrelated edits — it destroys traceability.
- Never write empty or uninformative messages (`wip`, `fix`, `update`).
