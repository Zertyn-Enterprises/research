<!-- managed-by: multi-agent-coding -->
# Cross-model review

**Status: not shipped in v0.1.** The rules file asks your agent to get an
independent review when a second model family is available and to say plainly when
none ran. The tooling that automates it is on the [roadmap](../ROADMAP.md). This
page is the reasoning, so you can do it by hand today and so you know what you are
signing up for if you adopt the module later.

## What it is

Before a change goes back to you, a model from a **different vendor family** reads
the diff and returns a verdict plus findings. Not a linter, not a test run — a
second reader with different training, different defaults, and different blind
spots.

## Why a different family

A model reviewing its own family's output tends to ratify it. It recognises the
conventions because they are its own conventions, it accepts the same framing of
the problem, and it misses the same things. The value of the review comes almost
entirely from the disagreement, so if you have to choose between a stronger
same-family reviewer and a weaker cross-family one, take the cross-family one.

Practical pairings, with whatever you actually pay for:

| You drive | Reviewer |
|---|---|
| Claude Code | Codex, Grok Build, or a Kimi / GLM session |
| Codex | Claude Code, Grok Build, or Kimi / GLM |
| Grok Build | Claude Code or Codex |

Kimi Code and the Z.ai (GLM) plans run inside Claude Code but are a different model
family, so they count as a second opinion. See
[per-cli-paths.md](per-cli-paths.md).

## What it costs

Be concrete about this before you wire it into a workflow, because the cost is not
a rounding error:

- **One review is one full session of another model.** It loads the diff and enough
  surrounding code to judge it, reasons over the whole thing, and writes findings.
  That is a real session against that vendor's quota, not a cheap API ping.
- **It is wall-clock time you wait for.** A thorough review at high reasoning
  effort is minutes, not seconds, and it sits between "code is written" and "you can
  look at it".
- **Panel mode multiplies everything.** Three families means three full sessions,
  three quotas, and — if you run them in parallel — three times the tokens in the
  same wall-clock window.
- **You need at least two paid subscriptions**, from different vendors. There is no
  way around that. One subscription means no cross-model review, only the
  substitute below.

## When to review

Decide per change, not once per project. The question is blast radius: what breaks,
and who notices, if this change is wrong.

| Change | Reviewers | Why |
|---|---|---|
| Docs, comments, formatting, a rename your tools verified | none | Nothing to find. A review here is pure cost. |
| A one-line fix with a test that went red then green | none | The test is the review. |
| Normal application code, roughly 30 lines and up | one, from another family | The common case. Catches the misread requirement and the wrong-but-typechecking code. |
| 🔴 money, entitlements, auth, persisted data, shared contracts | panel — every available family | Wrong here is expensive, often silent, and sometimes not reversible. |
| Roughly 300 lines and up, or a refactor across modules | panel | Too much surface for one reader. |

🔴 = money, entitlements, auth, persisted data, shared contracts. 🟡 = needs a
dependency or security review.

Two rules that make the whole thing worth doing:

1. **Never review with your own family.** It is not a review, and recording it as
   one is worse than skipping it.
2. **Never imply a review that did not run.** If no reviewer was available, the
   handoff says so in those words.

## What a review does not replace

Tests, type checking and lint run first and must be green. A reviewer that spends
its session finding a type error you could have found in two seconds is a reviewer
you wasted. The review is for the things a tool cannot check: the requirement you
misread, the case you did not think of, the contract you changed without noticing,
the abstraction that will be wrong in three weeks.

It also does not replace a human decision. The output is a verdict and findings for
you to act on, not permission to merge.

## With a single subscription

The honest substitute, and it is genuinely worth doing:

1. **Write the tests implementation-blind.** Level 3 of this kit ships a
   `test-author` agent for Claude Code: it writes tests from the acceptance criteria
   without reading the implementation, and the implementer never edits those tests
   toward green. Most of what a cross-model review catches on 🔴 surfaces, a test
   written from intent catches earlier and cheaper.
2. **Review in a fresh context, same family.** Start a new session that has not seen
   the conversation that produced the code, give it the diff and the acceptance
   criteria, and ask for findings. Fresh context removes the sunk-cost bias; it does
   not remove the family bias.
3. **Say which one you did.** "Fresh-context same-family review, no cross-family
   reviewer available" is a useful sentence. "Reviewed" is not.

## How the planned module behaves

The roadmap module is a command — `xreview` — plus a hook that gates PR creation
until the current tree has been reviewed. Its contract, so that adopting it never
leaves you stuck:

- It prints one verdict line, `OK`, `ISSUES` or `BLOCK`, followed by findings.
- Single mode picks the first available family that is not yours. Panel mode asks
  every available family that is not yours and takes the worst verdict.
- **A reviewer that does not run is `SKIPPED`**, with the reason (quota, crash, no
  verdict) in the output, and is never counted as `OK`.
- **No second family available is `SKIPPED`, never `BLOCK`.** A single-subscription
  user is not blocked from opening a PR. The gate's job is to stop you from claiming
  a review you did not get, not to stop you from working.
- A new commit needs a new review. A verdict is recorded against a tree, not
  against a branch name.
