---
name: "techdebt"
description: "Scan a codebase for technical debt — duplicates, dead code, unused imports, TODOs, inconsistent patterns, unused dependencies."
user-invocable: true
disable-model-invocation: false
---
<!-- managed-by: multi-agent-coding -->

# /techdebt — technical debt scanner

Scan the current project and report its technical debt. Report only; the human
decides what gets fixed.

## What to look for

1. **Duplicated code** — functions, components or blocks that do the same thing,
   or nearly the same thing, in different files.
2. **Dead code** — functions, variables, exports or components nothing imports
   or calls.
3. **Unused imports** — imports never referenced in their file.
4. **Forgotten TODOs** — `TODO`, `FIXME`, `HACK`, `XXX` comments that have been
   sitting there.
5. **Inconsistent patterns** — the project solves the same problem two ways
   (for example `fetch` in one place and `axios` in another, or two different
   error-handling shapes).
6. **Unused dependencies** — packages in `package.json` / `requirements.txt` /
   `pyproject.toml` that nothing imports.

## Output

For every issue, report:

- **Type:** duplicate | dead | import | todo | inconsistency | dependency
- **File(s):** the affected paths
- **Description:** what you found, in one line
- **Suggested action:** remove, consolidate, or refactor
- **Impact:** low | medium | high

Sort by impact, highest first.

## Rules

- Report only. Never change anything.
- Ignore `node_modules`, `.git`, `dist`, `build`, `.next`, `__pycache__`,
  `vendor`, and lock files.
- If the project has fewer than 10 source files, say so and stop.
- Be concrete. "There is duplicated code" is useless;
  "`src/utils/format.ts:23` and `src/helpers/string.ts:45` do the same thing" is
  the bar.
- At most 15 issues. If there are more, keep the high-impact ones and say how
  many you dropped.
- Verify each claim before reporting it: grep for the identifier you believe is
  unused instead of assuming it from a single file.
