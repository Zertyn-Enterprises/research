# Code Quality

Engineering quality bars every task must meet before it's done. These are
pass/fail gates — verifiable, automatable, non-subjective.

(Behavioral discipline — simplicity, surgical changes, think-before-coding —
lives in `coding-discipline.md`.)

## 1. Tests

- Run the project's test suite before you call the task done. All tests must pass.
- For UI components: write or run render tests at minimum.
- If no test framework exists, write the first one as part of your task —
  pick the project's stack-conventional choice (Vitest for React, pytest for
  Python, etc.).
- **Mocks never substitute for the real data path.** A feature that reads or
  writes the database (or any external data) MUST have at least one integration
  test exercising the REAL query/wiring against an ephemeral DB (testcontainers /
  pglite / a throwaway test database) — not a mocked client. A suite that stubs
  the DB or data layer end-to-end verifies nothing real, so it does NOT count as
  coverage for a data or UI feature: typesafe-but-wrong code (bad query, broken
  filter, mis-wired fetch) passes every mocked test and ships broken. Mocks are
  for unit-testing pure logic only.
- Never skip failing tests with `.skip`, `xit`, `pytest.mark.skip`, or similar.
  Fix them, or report blocked with the failure log.

## 2. Type Safety

- TypeScript: `tsc --noEmit` must exit 0. No type errors. No new warnings.
- Python: `mypy` (or `ty` / `pyright` if the project uses one) must exit 0.
- Never suppress type errors with `any`, `as any`, `# type: ignore`,
  `# noqa`, or equivalents. Fix the type. If you can't, report blocked.
- New code must be fully typed. No implicit `any`.

## 3. Lint

- Run the project's linter (`eslint`, `biome`, `ruff`, `prettier --check`,
  etc.). Zero warnings.
- Never disable lint rules in code (`// eslint-disable-line`, `# noqa`) without
  a comment explaining why. Prefer fixing the underlying issue.
- Format with the project's formatter. Match existing style exactly.

## 4. Input Validation

- Validate user input on every API endpoint or external boundary. Use the
  project's validation library (Zod, Pydantic, etc.) — don't invent one.
- Sanitize data at system boundaries (user input, external APIs, file
  uploads). Trust internal code; validate at the edge.
- Never expose internal errors, stack traces, or implementation details to
  clients. Return generic error messages; log details server-side.

## 5. Security

- Never commit secrets — API keys, tokens, passwords, credentials. Use env
  vars. Document required keys in `.env.example` (names only).
- Never hardcode credentials, even temporarily. Never use placeholder values
  that look real (`sk-abc123...`).
- Never use `eval()`, `exec()`, or string-built SQL. Parameterize all queries.
- Validate redirects, user-controlled URLs, file paths. Never trust user
  input as a filesystem path.

## 6. Comments and Docstrings

- Default: write no comment. Code should be self-explanatory through naming.
- Only add a comment when the WHY is non-obvious: a hidden constraint, a
  subtle invariant, a workaround for a known bug, behavior that would
  surprise a reader.
- Don't explain WHAT the code does — names should do that.
- Don't reference the current task, ticket, or caller in comments
  ("used by X", "added for the Y flow"). Those belong in the PR description.
- No multi-paragraph docstrings unless the project explicitly uses them.

## 7. Dependencies

- New top-level dependencies require justification in the PR description.
- Prefer the project's existing libraries over adding new ones. If the project
  uses `zod`, don't add `joi`. If it uses `pnpm`, don't add `npm`.
- Pin major versions. Run the project's audit tool (`npm audit`,
  `pnpm audit`, `pip-audit`) before you finish.

## 8. Definition of Done

A task is done only when:

1. All gates above pass (tests, types, lint, validation, security).
2. The success criteria you stated up front pass.
3. Changes are scoped to the task — no unrelated edits.

Anything less: stop and report it clearly — never silently lower the bar.
(Dispatched agents also satisfy the PR contract in `headless-dispatch.md`:
required sections, risk label, `status: blocked` on failure.)
