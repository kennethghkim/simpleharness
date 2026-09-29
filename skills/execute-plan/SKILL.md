---
name: execute-plan
description: Use to EXECUTE a written implementation plan in the current session — dispatch one author subagent per task, verify each independently before ticking it, track progress in ACTIVE-PLAN.md. The execution counterpart to blueprint. Not for a single scoped change (dispatch author directly) or read-only work.
---

# Execute Plan (subagent-driven, in-session)

Drive a written plan (from blueprint) to completion with subagents, in THIS
session. You orchestrate, integrate, and verify — you do NOT implement.

## Orchestrator, never implementer
About to edit a production file yourself? STOP — spawn an author. Your hands
touch only: the plan / `ACTIVE-PLAN.md`, dispatch prompts, verification, and
integration (CLAUDE.md Delegation Protocol).

## Setup
Mirror the plan's task checklist to `ACTIVE-PLAN.md` at the repo root (`- [ ]`
per task; gitignored). The plan + grant ledger are the source of truth — never
execute from stale memory; re-read the plan each wave.

## The loop (per wave)
1. Take the first unchecked top-level task; collect the same-wave unchecked tasks
   whose dependencies are met.
2. Dispatch them as ONE parallel burst (fan-out) — one author
   each, full 6-section contract (author.md). The prompt is an executable
   assignment, not a context handoff: paste only what the child needs.
3. Verify each returned task (below) before ticking its box.
4. Re-read the plan; confirm the remaining-unchecked count dropped. Do NOT ask
   whether to continue — run to BLOCKED / genuine ambiguity / done.

## Verify each task: DoneClaim -> independent check -> tick
- Author returns a **DoneClaim**: changed files, exact test commands + results,
  QA artifact, cleanup, residual risks (crosscheck Evidence Rubric).
- An INDEPENDENT agent confirms it — crosscheck, never the authoring agent
  ("subagents lie"). Verdict: confirmed / needs-fix.
- Only `confirmed` ticks the box `- [x]`. Any other verdict: leave it `- [ ]`,
  re-dispatch the SAME author via SendMessage with the exact failure
  (continue-before-respawn), then re-verify.

## Per-task ceremony (scale to risk)
- Default **LIGHT**: one verification pass.
- **HEAVY** (full crosscheck) when the task carries a nameable risk: new
  module/abstraction, auth/security/session, external integration, DB
  schema/migration, concurrency, cross-domain refactor, or the plan/user signals
  care. Unsure -> HEAVY. Never downgrade a task mid-flight.

## Progress
Keep a light append-only per-task log in the scratchpad (running notepad) —
step-granularity that survives compaction; distinct from `HANDOFF.md`
(checkpoint-granularity). On completion, reconcile + delete `ACTIVE-PLAN.md`
(handoff skill).

## Boundary
Reviewing is crosscheck's job; the 6-section contract is author.md's; supervising
long tasks is longrun's. This skill is the plan-execution loop that ties them
together.
