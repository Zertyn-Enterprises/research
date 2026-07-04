# Coding Discipline

How agents reason about a task before, during, and after writing code. Strict.
Universal across runtimes. Read before any work.

## 1. Think Before Coding

State your understanding, your options, and your uncertainty before you write a
single line of code — to the human if you're interactive, in the Plan section of
your PR description if you're dispatched.

- State assumptions explicitly. If something could be read two ways, list both,
  pick the most likely, and flag the others.
- If a simpler approach exists than the one implied by the task description,
  propose it. Pick the simpler one unless the task explicitly rules it out.
- If something is unclear, name it. Interactive: ask the human before
  proceeding. Dispatched: you can't ask — proceed with the most reasonable
  interpretation, document it, and let PR review correct it.
- Show your reasoning. Why this approach over the alternatives. What tradeoffs.
  What you're uncertain about.

## 2. Simplicity First

Write the minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility", configurability, or extension points that weren't requested.
- No error handling for impossible scenarios. Trust internal code; validate at
  system boundaries only.
- Three similar lines beat a premature abstraction.
- If you write 200 lines and it could be 50, rewrite. The test: would a senior
  engineer call this overcomplicated?

## 3. Surgical Changes

Touch only what the task requires. Clean up only your own mess.

- Don't refactor adjacent code, comments, or formatting.
- Don't reorganize imports unrelated to the change.
- Match existing style even if you'd write it differently.
- Notice unrelated dead code? Mention it (interactive: to the human; dispatched:
  in the PR's "Files intentionally not touched" section). Do not delete it.
- Remove only what YOUR changes orphaned (imports, vars, functions).
- Every changed line must trace directly to the task. If it can't, drop it.

## 4. The Four Rules

These are non-negotiable.

1. **Ask, don't assume.** Interactive: ask the human. Dispatched (can't ask):
   surface the assumption in your Plan section, pick the most reasonable
   interpretation, proceed — PR review is the correction loop.
2. **Simplest solution first.** No abstractions or flexibility you weren't
   explicitly asked for.
3. **Don't touch unrelated code.** If a file or function is not part of the
   current task, do not modify it, even if you think it could be improved.
4. **Flag uncertainty explicitly.** If you're not confident, say so before
   proceeding. Confidence without certainty causes more damage than admitting
   a gap.

## 5. Goal-Driven Execution

Define success before coding. Verify before declaring done.

- Transform vague tasks into verifiable goals before writing code:
  - "Add validation" → "Write tests for invalid inputs, then make them pass"
  - "Fix the bug" → "Write a test that reproduces it, then make it pass"
  - "Refactor X" → "Tests must pass before and after; line count or complexity
    must not increase"
- State the success criteria up front (to the human, or in your PR Plan section).
- Verify against those criteria before you call it done. If a criterion fails,
  fix it or report blocked.

## 6. What "done" means

You may declare a task done only when:

1. All success criteria you stated up front pass.
2. Tests pass (see `code-quality.md`).
3. Type-check passes.
4. Lint passes.
5. You haven't modified files outside the task's scope (or have explicitly
   listed any unavoidable touches).

If any of these fail and you can't resolve them: stop and report it clearly
(interactive: tell the human; dispatched: open the PR `status: blocked` with the
failure log). Do not silently skip gates. Dispatched agents also follow the PR
contract in `headless-dispatch.md`.
