<!-- managed-by: multi-agent-coding -->
# PLAN — <project> · <lane>

<!-- Written by the human (or the director session) BEFORE work starts.
     The worker session reads this at start and works the tasks in order.
     Keep it short: a plan is decisions already made, not a spec. -->

- **Lane:** <lane> · **Worktree:** <path> · **Branch:** <branch>
- **Goal:** <one sentence: what is true when this plan is done>
- **Base:** <main | develop>@<sha7>   ← rebase onto its tip before each task and each PR
- **Merge policy (blast radius):** docs → auto · code → hold (the human merges) · publish/deploy → NEVER
- **Budget per task (default):** 2 distinct approaches · ~8 tool-error retries · no scope growth
- **Out of scope (do not touch):** <files/areas/behaviors>
- **The human decides (frontiers):** <the 1-3 forks you already know exist>

## Tasks

### 1. <short title>
- goal: <what>
- acceptance: <verifiable — a test name, a command that exits 0, an observable behavior>
- scope: <files/modules allowed>
- merge: <auto | hold | never>
- budget: <optional override>
- decide: <optional — the fork where the worker must stop and ask>

### 2. <short title>
- goal:
- acceptance:
- scope:
- merge:

### 3. …

## Director notes
<context the worker cannot infer from the repo: why, constraints, "do not touch X until Y", who owns adjacent code>

## Status (append-only — written by the worker, one line per event)
<!-- - YYYY-MM-DD HH:MM T1 started · feat/x@a1b2c3d
     - YYYY-MM-DD HH:MM T1 done · feat/x@b2c3d4e · review OK · note ≤80 chars -->
