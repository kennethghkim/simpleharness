---
name: fan-out
description: Use when you have 2+ independent tasks that can run without shared state or a sequential dependency — fan them out to agents in ONE batch instead of serially. Covers the independence test, one-message dispatch, fleet supervision, and integrating verified results. Not for a single task, or tasks with an input/file dependency (run those sequentially).
---

# Fan-Out (dispatch parallel agents)

Fan out independent work to agents in a single batch; keep working while they
run. Implements the CLAUDE.md Delegation Protocol "parallel-by-default" rule.

## Invariants
- Fire all independent tasks in ONE message, not one at a time. Never idle-wait
  while they run — advance other work (idle-time utilization).
- Every returned result is a CLAIM until you verify it yourself (Verification
  Iron Law; "subagents lie").

## Independence test — safe to parallelize?
- Related failures (fixing one may fix the others) -> ONE agent, not many.
- Shared mutable state, or a **producer/consumer pair** -> SEQUENTIAL. Never
  parallelize a producer and its consumer (e.g. RED and GREEN of the same
  scenario; a generator and the code that reads its output).
- Never dispatch parallel authors onto the same files.
- Otherwise -> parallel.

## Dispatch
- One focused task per agent, each a self-contained 6-section contract
  (author.md).
- Require a liveness convention in the prompt: the child emits
  `WORKING: <task> - <phase>` before long passes, and `BLOCKED: <reason>` only
  when genuinely stuck.

## Supervise the fleet
- Poll in short cycles; never one long blocking wait. A wait-timeout is NO NEWS,
  not death — a running child is alive.
- Keep the parent visibly alive: report active count + names + latest phase, from
  liveness evidence (mtime/size/record count), never remembered state.
- Bound the fan-out: pick a concurrency ceiling and queue beyond it; a child that
  makes no progress past a bounded window -> abort and re-dispatch smaller.

## Fall back only when a child actually failed
Fall back if the child: completed WITHOUT the deliverable, is ack-only after a
follow-up, is explicitly `BLOCKED:`, or is no longer running. Then record the
result INCONCLUSIVE (never a pass), close it if safe, and respawn a smaller task
with the missing deliverable (BLOCKED ladder: more context -> stronger model ->
split -> ask). Retry format: `FAILED: {error}. Diagnosis: {observed}. Fix by:
{instruction}` — quote the valid options from the error into the corrected call.

## Integrate
Collect verified results only; reconcile. A failed or inconclusive shard blocks
integration until resolved.
