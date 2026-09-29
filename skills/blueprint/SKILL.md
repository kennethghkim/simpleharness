---
name: blueprint
description: Use when you have a spec or requirements for a multi-step task and need a plan document before touching code. Produces a decision-complete plan an agent can execute with zero judgment calls. Triggers on "write a plan", "plan this out", "draft an implementation plan", and any multi-step implementation work.
---

# Blueprint (writing plans)

## Overview

Write comprehensive implementation plans assuming the engineer has zero context for this codebase and questionable taste. Document everything they need: which files to touch for each task, the actual code, the tests, docs they might need to check, and how to verify it. Give them the whole plan as bite-sized tasks.

Assume they are a skilled developer, but know almost nothing about this toolset or problem domain, and may read tasks out of order. Assume they don't know good test design very well.

**Announce at start:** state that you are writing an implementation plan (intent announcement) before you begin.

## North Star: Decision-Complete

Write the plan so the implementer needs **ZERO judgment calls**. Research every discoverable fact yourself — exact file paths, signatures, existing patterns, exact commands — and bake it into the plan. Only genuine *preferences* go to the user as open questions; never facts you could have looked up.

**Save plans to:** `docs/plans/YYYY-MM-DD-<topic>.md`.

## Scope Check

If the spec covers multiple independent subsystems, split it into one plan per subsystem — each plan must produce working, testable software on its own. If the spec wasn't decomposed upstream, suggest breaking it into separate plans before writing.

## File Structure First

Before defining tasks, map out which files will be created or modified and what each one is responsible for. This is where decomposition decisions get locked in.

- Design units with clear boundaries and well-defined interfaces. Each file should have one clear responsibility.
- You reason best about code you can hold in context at once, and edits are more reliable when files are focused. Prefer smaller, focused files over large ones that do too much.
- Files that change together should live together. Split by responsibility, not by technical layer.
- In existing codebases, follow established patterns. If the codebase uses large files, don't unilaterally restructure — but if a file you're modifying has grown unwieldy, including a split in the plan is reasonable.

This structure informs the task decomposition. Each task should produce self-contained changes that make sense independently.

## Plan Document Header (TL;DR for humans)

**Every plan MUST start with this header:**

```markdown
# <Feature> Implementation Plan

> **For agentic workers:** implement this plan task-by-task using the harness
> delegation protocol (CLAUDE.md “Delegation Protocol”) — dispatch a fresh author subagent per
> task with a full 6-section contract, and review between tasks with the
> crosscheck skill. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** <one sentence describing what this builds>

**Architecture:** <2-3 sentences on the approach>

**Tech Stack:** <key technologies/libraries>

**Global Constraints:** <the spec's project-wide requirements — version
floors, dependency limits, naming/copy rules, platform requirements — one
line each, exact values copied verbatim from the spec. Every task's
requirements implicitly include this section.>

Tasks are grouped in waves; tasks within a wave are independent and may run in
parallel.

---
```

## Task Granularity

A task = **one coherent change with its test + verify**. Steps within a task may be bite-sized (write the test, run it red, implement, run it green, commit), but strict 2–5-minute TDD micro-steps are NOT mandated — this is Light TDD per CLAUDE.md “Coding Baseline”. Keep each task to a single coherent change so it can be authored, reviewed, and verified as one unit.

**Right-sizing:** a task is the smallest unit that carries its own test cycle and is worth a fresh reviewer's gate. Fold setup, configuration, scaffolding, and documentation steps into the task whose deliverable needs them; split only where a reviewer could meaningfully reject one task while approving its neighbor. Each task ends with an independently testable deliverable.

Group tasks into **waves**: a wave is a set of tasks with no dependency on each other, so they can be dispatched in parallel. Sequence waves by their dependencies.

Each task carries **agent-executable acceptance criteria**: concrete commands or selectors that pass/fail with zero human intervention — except a final eyeball check for UI.

## Task Structure

````markdown
### Task N: <Component> (Wave <k>)

**Files:**
- Create: `exact/path/to/file.py`
- Modify: `exact/path/to/existing.py:123-145`
- Test: `tests/exact/path/to/test_file.py`

**Interfaces:**
- Consumes: <what this task uses from earlier tasks — exact signatures>
- Produces: <what later tasks rely on — exact function names, parameter and
  return types. An implementer sees only their own task; this block is how
  they learn the names and types neighboring tasks use.>

**Change:** <what this task does and why, in prose>

**Implementation** — complete code (show the code, never describe it):

```python
def function(arg: str) -> Result:
    ...  # the actual code the implementer pastes
```

**Test** — the failing regression test / new-feature test, in full:

```python
def test_specific_behavior():
    assert function("input") == expected
```

**Acceptance criteria (agent-executable):**
- Run: `python -m pytest tests/path/test_file.py::test_specific_behavior -v`  → PASS
- Run: `sg run -p '<old pattern>' --lang py src/`  → 0 matches (migration complete)
- [ ] Task complete
````

When a task ends in a commit, stage intended files explicitly (no bare `git add .` / `git add -A`) and show the exact command:

```bash
git add tests/path/test_file.py src/path/file.py
git commit -m "feat: add specific behavior"
```

## No-Placeholder Rule (these are plan failures — never write them)

- "TBD", "TODO", "implement later", "fill in details".
- "Add appropriate error handling" / "add validation" / "handle edge cases".
- "Write tests for the above" (without the actual test code).
- "Similar to Task N" — repeat the code; the implementer may read tasks out of order.
- Steps that describe what to do without showing how (code blocks required for code steps).
- References to types, functions, or methods not defined in any task.

## Remember

- Exact file paths always.
- Complete code in every code-changing step — if a step changes code, show the code.
- Exact commands with expected output.
- Windows-first commands (PowerShell 7 / `python` / scratchpad, not `/tmp`); note the UTF-8 console rule wherever a step prints non-ASCII (write to a UTF-8 file and Read it back rather than trusting stdout).
- YAGNI, DRY, minimal diff, match surrounding style, small scoped commits.

## Self-Review (run yourself, not a subagent)

After writing the complete plan, look at the spec with fresh eyes and check the plan against it. This is a checklist you run yourself — not a subagent dispatch.

1. **Spec coverage:** skim each section/requirement in the spec. Can you point to a task that implements it? List any gaps.
2. **Placeholder scan:** search the plan for every red flag in the No-Placeholder list; fix them.
3. **Type/name consistency:** do the types, signatures, and property names used in later tasks match what earlier tasks defined? (`clearLayers()` in Task 3 vs `clearFullLayers()` in Task 7 is a bug.)

Fix issues inline; no need to re-review. If a spec requirement has no task, add the task.

## Gap-Analysis Pass (independent, before the plan is final)
After your own self-review, run ONE independent gap-analysis pass before
presenting the plan for approval: dispatch a fresh `reviewer` (separate context)
to read the spec + the plan and surface only STRUCTURAL gaps --
- contradictions, ambiguity, missing constraints, execution risks, and topology
  gaps (a task depending on something no task produces).
Verdict: `CLEAR` or `GAPS-FOUND`. One pass, no loop; do not invent problems.
Fold any real `GAPS-FOUND` items back into the plan, then proceed to the
approval gate. Skip this only for a trivial single-task plan.

## Approval Gate

**Plan approval is a user gate.** After saving, present the plan and wait for approval. While awaiting approval, do NOT re-explore or re-research — that is a durable gate; hold state and wait.

## Execution Handoff

After the plan is approved, offer the execution choice:

**"Plan approved and saved to `docs/plans/<filename>.md`. Two execution options:**

**1. Subagent-driven (recommended)** — dispatch a fresh author subagent per task via the harness delegation protocol (CLAUDE.md “Delegation Protocol”), reviewing between tasks with the crosscheck skill. Fast iteration, isolated context per task.

**2. Inline execution** — execute the tasks in this session, in dependency order (wave by wave), with review checkpoints between waves.

**Which approach?"**

## Cross-Session Tracking (ACTIVE-PLAN.md)

When a plan will execute across multiple turns or sessions, mirror its task checklist to `ACTIVE-PLAN.md` at the project root — same `- [ ]` / `- [x]` checkbox format, gitignored like HANDOFF.md. Tick each item the moment it completes. While unchecked items remain, the Stop hook keeps the session executing; a deliberate pause is either a fresh HANDOFF.md newer than the plan (checkpoint via handoff) or a `status: paused` line in the plan's first 20 lines. On completion or abandonment, delete the file.
