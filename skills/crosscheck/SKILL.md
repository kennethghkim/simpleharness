---
name: crosscheck
description: This skill should be used for large, risky, data, or deploy work that needs separate author and reviewer agents, multi-round revision gates, read-only review, and explicit APPROVE / APPROVE-WITH-MINOR-FIXES / REVISE verdicts before finalizing. Small well-scoped fixes go direct — skip this.
---

# Author / Reviewer Pipeline

Separate implementation from review when a mistake would be expensive. The author does the work; the reviewer stays independent and read-only; the orchestrator reconciles evidence and user decisions.

## Trigger

Use for large/risky/spec-critical work: complex refactor, generated-data change, deployment/config work, security-sensitive changes, PR preparation, or when the user asks for review or a multi-agent workflow.

Concrete escalation triggers — any ONE forces the pipeline:

- 3+ files (or ~150+ changed lines) in a single work unit.
- Destructive, data, deploy, or security-sensitive surface.
- User rigor keywords (rigorous, thorough, meticulous — or their Korean equivalents).
- 2+ failed direct-fix attempts on the same problem.

**Scale ceremony to risk.** Small well-scoped fix → direct edit + self-verify, no pipeline. This pipeline is the escalated path, not the default for every change.

## Roles

- **Orchestrator:** owns the original user request, constraints, allowed side effects (grant ledger), and final report. Relays findings; never lets the reviewer edit.
- **Author:** implements/investigates per the 6-section dispatch contract and runs the requested gates. See `agents/author.md`.
- **Reviewer:** reads the diff/state/evidence and reports issues. Read-only. See `agents/reviewer.md`.

## Verdict Schema

Reviewer must output exactly one verdict:

- `APPROVE` — ready.
- `APPROVE-WITH-MINOR-FIXES` — only minor fixes remain; apply or explicitly defer them.
- `REVISE` — author must fix and reviewer must re-check.

Severity labels:

- `BLOCKER` — unsafe, failing, or violates a hard requirement.
- `MAJOR` — likely bug, regression, missing requirement, or missing required verification.
- `MINOR` — polish, naming, docs, small robustness issue.
- `OQ` — open question, user decision needed. Never resolve an OQ by guessing.

**Approval bias:** "You are a BLOCKER-finder, not a PERFECTIONIST. When in doubt, APPROVE — a plan/impl that is 80% clear is good enough." Max 3 blocking issues per round; nitpicks only as `MINOR`. (2-stage tier overrides this for `BLOCKER`/`MAJOR` — see "Loop to unconditional approval".)

## Stage scaling (orchestrator picks by risk)

- **0 stages** — ad-hoc fix mode or trivial change: author self-verifies, no separate reviewer.
- **1 stage (standard)** — one combined review pass covering spec compliance AND code quality.
- **2 stages (large or spec-critical)** — stage 1 spec compliance, THEN stage 2 code quality. Never start the quality review before spec compliance passes.

When the risk assessment is ambiguous, default to 2 stages.

### Loop to unconditional approval (2-stage tier only)

On the 2-stage (large / spec-critical) path, the author->review->revise loop
continues until the reviewer returns `APPROVE` with ZERO open `BLOCKER` or
`MAJOR` findings. The "when in doubt, APPROVE" bias does NOT apply while a
`BLOCKER` or `MAJOR` is open — it still governs `MINOR` judgment calls. `MINOR`
stays non-blocking; `OQ` escalates to the user. **Circuit breaker:** if 3
`REVISE` rounds do not reach a clean approval, STOP — do not attempt round 4;
re-question the approach/architecture and escalate to the user with options
(per the CLAUDE.md 3-failure circuit breaker). The 0/1-stage tiers keep the
approval-biased gate unchanged.

## Verification passes (static + real-usage, each independent)
Verification is not one look at the diff -- it is one or more INDEPENDENT passes,
each a SEPARATE `reviewer` dispatch (never the author; "subagents lie"), each
returning its own verdict against captured artifacts:
- **Static pass** -- correctness, request-compliance, slop, behavior
  preservation, data-delta (read the diff + re-run the gates).
- **Real-usage / e2e pass** -- ONLY when the change has a runtime surface
  (UI / API / CLI / data): the reviewer drives the running system
  (browser / request / command) and judges the artifact adversarially ("assume
  broken until proven"). See `agents/reviewer.md` "Real-usage verification".
Run each applicable pass as its own dispatch so the verdicts stay independent. A
change is verified only when EVERY applicable pass returns `APPROVE` /
`APPROVE-WITH-MINOR-FIXES`. This folds into the stage tiers: the e2e pass is an
extra independent stage for runtime-surface changes; a change with no runtime
surface needs only the static pass.

## Procedure

1. Restate the goal and hard invariants before dispatching work.
2. Give the author complete context via the 6-section dispatch contract: `TASK / EXPECTED OUTCOME / REQUIRED TOOLS / MUST DO / MUST NOT DO / CONTEXT`. Self-contained — never "read the plan file".
3. When the author reports, handle by status vocabulary:
   - `DONE` → verify the diff/artifacts yourself before accepting ("subagents lie"), then review.
   - `DONE_WITH_CONCERNS` → read concerns; correctness/scope concerns block, observations noted.
   - `NEEDS_CONTEXT` → supply and re-dispatch the same agent (SendMessage, don't respawn).
   - `BLOCKED` → escalation ladder: more context → stronger model → split the task → ask the user.
4. Collect concrete evidence: changed files, diff summary, command outputs, artifact paths, known risks — structured by the Evidence Rubric below.
5. Run the review (1- or 2-stage) using the original request + evidence. Author and reviewer MUST be distinct agents.
6. If `REVISE`, relay only the concrete findings to an author. The reviewer never silently patches code.
7. Re-run the relevant gates and re-review. The reviewer must mark each prior-round finding **resolved / superseded / still-open**.
8. Stop when `APPROVE` (2-stage tier: `APPROVE` with zero open `BLOCKER`/`MAJOR`), or `APPROVE-WITH-MINOR-FIXES` with all minor items applied or explicitly deferred — subject to the loop + circuit-breaker rule above.
9. Escalate any `OQ` to the user (prose + labeled options A/B/C) when it changes product behavior, security posture, default output, UX, data policy, model choice, or deployment state.

## Evidence Rubric (author completion reports)

Inside the pipeline, an author `DONE` report must contain these four sections
(one line each is fine; every claim pairs a command with its artifact path):

1. **What Was Tested** — commands/scenarios actually run.
2. **What Was Observed** — concrete outputs, exit codes, artifacts.
3. **Why It Is Enough** — how the evidence covers the stated invariants.
4. **What Was Omitted** — untested paths, and why that is acceptable.

A report missing a section is incomplete — send it back for evidence, not rework.

## Reviewer Prompt Skeleton (see `agents/reviewer.md`)

```text
You are the independent read-only reviewer (agents/reviewer.md). Do not edit files.

Original request:
<request>

Hard invariants:
- <invariant>

Author summary and evidence:
<summary, diff/test commands + outputs, artifact paths>

Stage: <spec-compliance | code-quality | combined>

Rules:
- Severity labels: BLOCKER, MAJOR, MINOR, OQ.
- Exactly one verdict: APPROVE, APPROVE-WITH-MINOR-FIXES, REVISE.
- Approval-biased: max 3 blocking issues; when in doubt, APPROVE.
- Treat unapproved behavior changes as OQ or BLOCKER.
- On re-review, mark prior findings resolved / superseded / still-open.

Output:
Verdict: <...>
Findings:
- [SEVERITY] <issue>
Verification gaps:
- <gap or None>
```

## Final Report

Bottom line first (≤3 sentences), then: author path/tool, reviewer verdict, revision rounds, tests/gates actually run (with evidence), unresolved minor risks, and any user decisions (OQ). Do not dump raw agent transcripts unless asked.
