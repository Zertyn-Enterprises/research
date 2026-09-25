---
name: "context-init"
description: "Analyze a codebase and generate a comprehensive CONTEXT.md for the project."
user-invocable: true
disable-model-invocation: true
---
<!-- managed-by: multi-agent-coding -->

# /context-init — generate CONTEXT.md for a project

When the user runs /context-init, analyze the codebase and write a CONTEXT.md
that describes the product's live state. CONTEXT.md is state, not rules: the
repo's rules live in AGENTS.md (see step 3).

## Steps

### 1. Scan the project

```bash
find . -type f -not -path './node_modules/*' -not -path './.git/*' -not -path './dist/*' \
  -not -path './build/*' -not -path './.next/*' -not -path './__pycache__/*' | head -200
cat package.json 2>/dev/null || cat pyproject.toml 2>/dev/null || cat requirements.txt 2>/dev/null
ls -la tsconfig.json next.config.* vite.config.* tailwind.config.* .eslintrc* biome.json 2>/dev/null
```

### 2. Write CONTEXT.md with this structure

**Header:** project name and one paragraph describing it.

**Tech Stack:** framework, language, styling, state management, database, auth,
payments, deployment. Be specific about versions.

**Project Structure:** directory tree with a brief note on each important
directory.

**Key Patterns:** how routing works, data flow, auth implementation, payment
flow, any convention an agent cannot infer from a single file.

**Environment Variables:** every required variable, names only, no values.

**Important Commands:** dev, build, test, lint, typecheck.

**Current State:** what works, what is in progress, known issues.

**Architecture Decisions:** why each significant tool was chosen, and the
trade-off accepted.

### 3. Instructions file: AGENTS.md canonical, CLAUDE.md a symlink

Never write a regular `CLAUDE.md` — every agent family must read the same
instructions file (Repo Map in this kit's rules). After writing CONTEXT.md:

```bash
agentsify "$PWD"   # AGENTS.md from the template (or from an existing CLAUDE.md) + CLAUDE.md -> AGENTS.md
grep -q 'CONTEXT.md' AGENTS.md || printf '\nRead CONTEXT.md for the product state.\n' >> AGENTS.md
```

`agentsify` is installed at `~/.local/bin/agentsify` and takes its template from
`$MULTI_AGENT_CODING_HOME/templates/AGENTS.md` (default
`~/.multi-agent-coding/templates/AGENTS.md`). If it exits 1 it found rules and
state mixed in one file (for example `CLAUDE.md` symlinked to `CONTEXT.md`):
stop and report it — splitting them is the human's call.

### 4. Verify

```bash
echo "CONTEXT.md written ($(wc -l < CONTEXT.md) lines)"
```

## Rules

- NEVER put a real secret value in CONTEXT.md. Variable names only.
- Be specific about versions: "React 18.2", not "React".
- Describe the monorepo layout if the project is one.
- Report what you could not determine instead of guessing at it.
