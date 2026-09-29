---
name: handoff
description: This skill should be used when ending, pausing, compacting, or handing off a long-running coding/ops session, and when resuming one (a one-word restart such as "continue" or "resume"), so the next agent resumes from concrete state on disk rather than stale memory or vague progress notes.
---

# Session Handoff Checkpoint

Use this skill to (a) checkpoint before pausing, compacting, handing off, or ending a session with unfinished work, and (b) resume a prior session from concrete state. The checkpoint target is `HANDOFF.md` at the repo root. It makes the next first action obvious and verifiable; durable knowledge does NOT live here — it routes to the 3 docs (see step 3).

## Trigger

- **Checkpoint** when the session involved multiple steps, background processes, PRs, generated artifacts, remote hosts, grants, or unresolved decisions. Skip for a simple completed one-shot task.
- **Resume** on a one-word restart (e.g. "continue" / "resume") or any pointer back to prior work.

---

## Running notepad (during work)

On a multi-step / delegation-heavy / long run, keep a running notepad so a
mid-task compaction does not erase in-progress state. This is distinct from
`HANDOFF.md`: the notepad is a continuous step-log DURING the work; `HANDOFF.md`
is the checkpoint snapshot. The notepad FEEDS the checkpoint.

- **File:** append-only `scratchpad/NOTEPAD-<yyyymmdd-topic>.md`. Never overwrite.
- **What to log:** each decision made and the next action, as you go — plus
  blockers and grants. Anti-slop: decisions and next-action only; do not restate
  code or narrate tool calls. Keep it terse.
- **Resume:** on restart, re-read the notepad alongside `HANDOFF.md` to recover
  step-level state before acting.
- **Skip** for trivial single-shot tasks (same bar as skipping a checkpoint).

## Part A — Checkpoint (session end / pause / compact)

### 1. Re-read concrete state

Do not rely on memory. Check current facts from the system of record (Windows-first):

```powershell
git status --branch --short
git rev-parse --abbrev-ref HEAD; git rev-parse --short HEAD
Get-ChildItem <artifact-dir> | Select-Object Name, Length, LastWriteTime
```
- active PR number/URL/head SHA if relevant (`gh pr view`)
- background process handles, job IDs, CI runs
- latest test/gate results and unresolved reviewer findings

POSIX equivalent: `git status -sb`, `ls -la <artifact-dir>`.

### 2. Classify work state

Use clear labels:

- **Completed-with-evidence** — include the proving command + output.
- **In-progress** — include current handle/path and the safe next command.
- **Blocked** — include the blocker and the needed decision/action.
- **Deferred** — intentional, routed to `docs/ROADMAP.md`, not forgotten.
- **Stale/superseded** — do not continue unless the user reopens it.

### 3. Route durable knowledge OUT of the handoff

`HANDOFF.md` is ephemeral session state. Durable knowledge goes to the 3 docs, reusable procedures go to skills:

- Accumulated pitfalls / caveats / correction-derived lessons → `docs/PROJECT-KNOWLEDGE.md` (context → pitfall → rule).
- Structural/architecture facts → `docs/ARCHITECTURE.md`.
- Deferred items and open design questions → `docs/ROADMAP.md`.
- Reusable procedures → a skill.
- Do NOT store raw progress logs, PR numbers, temporary counts, or soon-stale artifacts as durable knowledge. Never store secrets or credential values anywhere.
- **APPLY the doc deltas agents PROPOSED** in their completion reports: fold each into `docs/PROJECT-KNOWLEDGE.md` (context → pitfall → rule) or `docs/ARCHITECTURE.md`, respecting the anti-slop bar — only correction-derived or non-obvious entries, no doc bloat. Agents propose; the checkpoint is where proposals are written (under commit hygiene).

### 4. Write / overwrite `HANDOFF.md`

Overwrite the repo-root `HANDOFF.md` each checkpoint using the template below. Include the **Grant Ledger**: every explicit user grant this session with its scope + timestamp (grants survive compaction and gate destructive/external actions).

### 5. Clean up the workspace

- Sweep this unit's scratch from the scratchpad — but KEEP resume-state that a still-running long-running job needs (progress/checkpoint/partial output; see the longrun skill), and KEEP an in-progress running notepad (it is resume-state while the run is live); sweep the notepad once the run is checkpointed/complete. Force-closed sessions never reach here -- the SessionStart hook (scratch-gc.ps1) GCs their >7-day orphan scratchpad/tasks/tool-results at next start.
- If stray temp files landed inside the repo tree, LIST them (absolute paths) for the user instead of deleting them. Never auto-delete anything inside the project tree.

### 6. Verify before claiming done

If the session is meant to be complete, run the final gate fresh or explicitly state why it could not run. If a background process remains, report its handle and how completion will be detected. No completion claim without fresh verification evidence.

### 7. Reconcile ACTIVE-PLAN.md (if the session mirrored a plan)

If a plan was mirrored to `ACTIVE-PLAN.md` at the project root (see blueprint), reconcile it here: tick finished items, and carry any still-open items into the Open items of `HANDOFF.md`. On completion or abandonment of the work, delete `ACTIVE-PLAN.md`. A deliberate mid-plan pause is a checkpoint taken AFTER the last plan edit — a fresh (same-day) `HANDOFF.md` newer than the plan unblocks the Stop-hook continuation gate — or set a `status: paused` line in the plan's first 20 lines.

## Handoff Template (`HANDOFF.md`, repo root)

```markdown
# HANDOFF — <project> — <YYYY-MM-DD HH:MM>

## Active goal
<one line>

## Current state of record
- Repo/host/path:
- Branch / HEAD:
- PR / CI / background process handles:
- Key artifacts (path — size/mtime):

## Grant Ledger
- <scope of grant> — granted <YYYY-MM-DD HH:MM> (e.g. "commit+push to feature branch", "install deps")
- (none) if the user has granted nothing

## Completed with evidence
- <item> — proving command + result

## Open items
- In-progress: <handle/path + safe next command>
- Blocked: <blocker + decision needed>
- Deferred → ROADMAP.md: <item>

## Next first action
1. <exact command or inspection step>
```

---

## Part B — Resume (session start / one-word restart)

Do not trust your memory of prior turns — re-read the plan.

1. **Read** `HANDOFF.md`, the running notepad (`scratchpad/NOTEPAD-*.md`, if any), + the 3 docs (`ARCHITECTURE.md`, `PROJECT-KNOWLEDGE.md`, `ROADMAP.md`).
2. **Verify state of record still matches** what the handoff claims — re-run `git status -sb`, check branch/HEAD, artifact mtimes/sizes, PR/CI status, background handles. Reconcile any drift (the user may have merged/installed/deleted between sessions).
3. **Reload the Grant Ledger** — grants recorded there remain in force if the resume continues the same work.
4. **Then act.** The recorded "next first action" executes ONLY after verification confirms the state. If reality diverged from the handoff, re-plan from the verified state, not from the stale note.

---

## Pitfalls

- Continuing from stale compaction summaries or a stale `HANDOFF.md` without re-verifying disk/git/process state.
- Recording soon-stale PR numbers or progress counts as durable knowledge (they belong only in the ephemeral handoff).
- Putting durable lessons in `HANDOFF.md` instead of `docs/PROJECT-KNOWLEDGE.md` — they get overwritten next checkpoint.
- Saying "done" when tests/artifact verification were not actually run fresh.
- Losing background process handles, or dropping a user grant so a later action re-gates unnecessarily.
- Mixing secret values into handoff notes.
- Printing non-ASCII artifact content to the console to inspect it (mojibake) — write to a UTF-8 file and Read it back.
