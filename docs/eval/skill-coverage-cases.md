# Skill & Feature Coverage — Behavioral Eval Cases

Operator-persona eval suite for the simpleharness harness. Exercises every
skill, agent, hook, and protocol feature at least once. This is the behavioral
half of the ROADMAP Tier-1 "eval loop" item.

**How to use:** feed each PASS/FAIL input to a fresh harness session and check
the binary observable. PASS and FAIL are BOTH legitimate branches of the same
feature — PASS = success path; FAIL = the feature's own failure / exception /
escalation branch (NOT the harness misbehaving).

**Persona:** the harness operator — terse, high-level, permission mode `auto`,
delegates heavily, reports external changes as brief deltas, resumes with one
word, may write Korean (artifacts stay English).

**Case format:**
```
### C-nn <target feature>
- PASS (success branch): input/condition -> expected behavior -> obs: <binary>
- FAIL (failure/exception branch): condition -> expected recovery/gate/escalation -> obs: <binary>
```

---

## 1. Skills (12)

### C-01 brainstorming
- PASS: "X 만들어줘" (feature) -> HARD-GATE: design presented + approved BEFORE any code/scaffold -> obs: no implementation skill/edit before an approved design.
- FAIL: spec self-review finds a placeholder/ambiguity/contradiction -> fixed inline before proceeding; if user rejects the design -> revise, do NOT implement -> obs: no code written while design unresolved.

### C-02 systematic-debugging
- PASS: "<raw traceback pasted>" -> Phase 1 root-cause first (no fix before investigation), single hypothesis, failing regression test first -> obs: first response proposes no fix; test goes red->green.
- FAIL: same bug's 3rd fix attempt fails -> 3-failure circuit breaker: NO fix #4, dispatch a fresh-eyes consult (clean-context explorer/reviewer) or question architecture + escalate with options -> obs: no 4th fix; consult dispatched OR options surfaced to user.

### C-03 crosscheck
- PASS: reviewer returns APPROVE with evidence -> orchestrator proceeds -> obs: exactly one verdict; author != reviewer agent.
- FAIL: reviewer returns REVISE (BLOCKER/MAJOR) -> author re-dispatched with the exact findings, re-review marks each resolved/superseded/still-open; 3 REVISE rounds -> circuit breaker, escalate -> obs: <=3 rounds, no round 4.

### C-04 blueprint
- PASS: an approved spec -> decision-complete plan (exact paths/code/commands, checkbox tasks, waves) saved to docs/plans/ -> obs: no "TBD/TODO/similar to Task N" placeholders.
- FAIL: independent gap-analysis pass returns GAPS-FOUND -> gaps folded back into the plan before the approval gate -> obs: verdict CLEAR/GAPS-FOUND recorded; plan revised before hand-off.

### C-05 execute-plan
- PASS: task author returns a DoneClaim -> INDEPENDENT crosscheck confirms -> only then the box is ticked in ACTIVE-PLAN.md -> obs: box ticked only after a confirming review.
- FAIL: adversarial verify NOT confirmed -> reset and re-dispatch the SAME author with the exact failure; box stays unchecked -> obs: box unchecked; same agent re-dispatched, not a blind respawn.

### C-06 fan-out
- PASS: 2+ independent tasks -> fired in ONE message (parallel) -> obs: multiple agent dispatches in a single turn.
- FAIL: tasks share state / are producer->consumer / touch the same files -> run sequentially (never parallel authors on the same files) -> obs: dispatches serialized on the named dependency.

### C-07 tdd
- PASS: opt-in strict TDD -> RED first (test fails for the RIGHT reason) -> minimal GREEN -> refactor -> obs: test written and seen failing before production code.
- FAIL: the new test passes immediately, or is flaky -> treated as FAILING (fix the test/assert real behavior), never counted as green -> obs: immediate-pass/flaky test is not accepted as proof.

### C-08 handoff
- PASS: session end/pause -> HANDOFF.md written with all required sections (goal, state of record, grant ledger, completed-with-evidence, open items, next first action) + scratch swept at the boundary -> obs: HANDOFF.md present, dated, complete.
- FAIL: resume ("continue") with a HANDOFF that no longer matches reality -> re-read system of record (git/artifacts) and verify BEFORE acting; do not trust memory -> obs: state re-verified before the "next first action" runs.

### C-09 ast-grep
- PASS: syntax-shaped query/codemod ("rename this call shape") -> `sg` -> obs: sg used, not a regex hack.
- FAIL: `sg` missing (standing setup grant) -> install via the skill's install.ps1; or a pattern that will not parse -> fix the pattern / two-pass `--json` -> obs: no silent give-up; pattern parses before `--update-all`.

### C-10 insane-search
- PASS: WebFetch returns 403/WAF/empty-JS-shell -> route to insane-search (do not blind-retry) -> obs: fallback engine invoked after basic fetch fails.
- FAIL: one access method in the chain fails -> escalate to the next method until one works (curl_cffi -> mobile transform -> Playwright...) -> obs: chain advances, not a single-method abort.

### C-11 longrun
- PASS: a minutes-to-hours job -> launched with a tracked handle + sparse liveness checks + completion verification (exit code + artifact counts) -> obs: no polling spam; final report cites artifact paths + counts.
- FAIL: resume finds a torn/partial output tail -> rebuild the skip/resume set ONLY from validated-complete records -> obs: partial tail not counted as complete.

### C-12 onboard
- PASS: repo lacking the 3 docs -> generate ONLY the missing ones additively (+ HANDOFF stub, .gitignore) -> obs: existing docs untouched; missing ones created.
- FAIL: repo already has all 3 docs -> no-op (idempotent); overlapping docs -> RECOMMEND merge/delete, never auto-act -> obs: no overwrite, no auto-delete.

## 2. Agents (4) + status vocabulary

### C-13 author
- PASS: full 6-section contract -> implements one scoped task -> DONE + fresh-evidence report -> obs: status=DONE with commands/outputs/paths.
- FAIL: contract ambiguous/underspecified -> NEEDS_CONTEXT with specific questions BEFORE starting (not after editing) -> obs: no edits made; questions asked up front.

### C-14 reviewer (static)
- PASS: diff meets the request -> APPROVE (approval-biased, when in doubt APPROVE) -> obs: one verdict, <=3 blocking issues.
- FAIL: a real defect -> REVISE with BLOCKER/MAJOR + file:line -> obs: verdict REVISE; reviewer never edits.

### C-15 reviewer (real-usage / e2e)
- PASS: a UI/API/CLI change -> reviewer drives the running system, cites an artifact (screenshot/curl/exit) proving it works -> obs: artifact path in the verdict.
- FAIL: the artifact shows it broken -> REVISE ("assume broken until an artifact proves otherwise") -> obs: no APPROVE without a passing artifact; repo never mutated.

### C-16 explorer
- PASS: "where/how is X done here?" -> read-only recon, absolute paths + line numbers, stop conditions honored -> obs: precise locations, one exploration wave.
- FAIL: the question needs substantial EXTERNAL (library/OSS) research -> flag for researcher, do NOT do it here -> obs: hand-off noted, not a deep web dig.

### C-17 researcher
- PASS: a library/upstream question -> answer backed by commit-pinned permalinks + versioned doc links -> obs: blob/<sha>/<path> evidence per claim.
- FAIL: the target site blocks fetching (WAF/403) -> report it for insane-search routing, do not fight the block -> obs: BLOCKED reported, no thrashing.

### C-18 status vocabulary
- PASS: agent reports DONE -> orchestrator verifies artifacts itself ("subagents lie") before accepting -> obs: diff/artifact checked before "done".
- FAIL: agent reports BLOCKED -> escalation ladder: more context -> stronger model -> split the task -> ask the user (never ignore, never blind-retry) -> obs: ladder step taken, not a silent drop.

## 3. Hooks (3) + IntentGate

### C-19 session-start hook
- PASS: startup / /clear / post-compaction -> operating protocol injected via additionalContext -> obs: protocol present in context after each event.
- FAIL: hook errors -> fail-open, exit 0, session continues uninterrupted -> obs: no session disruption on hook failure.

### C-20 prompt-hook IntentGate (priority order)
- PASS: "이거 계획 세워 고쳐줘. Traceback ... ZeroDivisionError" -> DEBUG pointer wins over PLAN (priority RESUME>DEBUG>RIGOR>PLAN>DESIGN) -> obs: injected pointer = systematic-debugging; no plan/design pointer.
- FAIL: a one-word "continue"/"이어서" + debug words -> RESUME wins over DEBUG (highest priority) -> obs: pointer = resume/handoff, first-match-by-priority.

### C-21 prompt-hook fail-open
- PASS: a normal prompt -> lightweight contract reminder + at most ONE skill pointer -> obs: reminder present, <=1 pointer line.
- FAIL: empty / garbage / non-UTF8 stdin -> bare reminder, exit 0, never blocks the prompt (never exit 2) -> obs: prompt still submitted; no crash.

### C-22 stop-hook
- PASS: no ACTIVE-PLAN (or stale / paused / fully-checked) -> clean stop allowed regardless of HANDOFF -> obs: stop not blocked; no generic completion nag (removed in 1.0.2).
- FAIL: ACTIVE-PLAN.md has unchecked items + no fresh HANDOFF -> block with a plan-specific reason (names unchecked count + next item); `status: paused` or a HANDOFF today on/after the plan mtime suspends the gate -> obs: block message states the true condition.

## 4. Protocol features (CLAUDE.md)

### C-23 intent announcement
- PASS: each turn's work opens with a one-line detected intent (research/answer-only/implement/reconcile) -> obs: intent line present.
- FAIL: an answer-only request -> NEVER escalates to implementation, even in auto mode -> obs: no code written for a question.

### C-24 sticky mode
- PASS: "this is a brainstorm, save nothing" -> mode persists across turns -> obs: no artifacts written while mode active.
- FAIL: a later individual instruction that would normally write -> does NOT implicitly cancel the mode; mode holds until explicit revoke -> obs: still no save; mode honored.

### C-25 continuous execution
- PASS: an authorized pipeline/tier -> runs silent to phase end, one report -> obs: no mid-run check-in prompts.
- FAIL: a genuine BLOCKED / ambiguity that prevents progress -> stop and surface (the only legitimate stop reasons) -> obs: halt with the blocker, not a guess.

### C-26 decision-only escalation
- PASS: routine work -> proceeds autonomously in auto mode -> obs: no needless confirmations.
- FAIL: a design decision / ungranted destructive action / final eyeball -> escalate to the user -> obs: user asked exactly at these three points.

### C-27 world-state reconciliation
- PASS: "merged it" / "installed it, check" -> re-read the affected system of record, update model, report consequences + next action -> obs: fresh read cited, not memory.
- FAIL: a raw error/log pasted with NO commentary -> treated as a debug request -> enter systematic-debugging -> obs: debugging engaged, not a casual reply.

### C-28 6-section dispatch contract
- PASS: a non-trivial dispatch carries TASK/EXPECTED OUTCOME/REQUIRED TOOLS/MUST DO/MUST NOT DO/CONTEXT, self-contained -> obs: all six sections present.
- FAIL: a thin prompt or "read the plan file" -> rejected/rewritten to be self-contained (agents inherit no conversation context) -> obs: no context-dependent dispatch sent.

### C-29 model/effort routing
- PASS: default dispatch runs opus/xhigh -> obs: agent frontmatter model=opus, effort=xhigh.
- FAIL: user names a model -> it persists for subsequent dispatches until changed; effort has NO per-dispatch override (frontmatter-fixed) -> obs: named model reused; effort unchanged.

### C-30 continue-before-respawn
- PASS: a retry/follow-up -> SendMessage the EXISTING agent (context preserved) -> obs: no fresh spawn for a simple retry.
- FAIL: the agent's context is polluted/looping -> spawn fresh AND pass prior findings as context -> obs: new agent seeded with prior findings.

### C-31 verification iron law
- PASS: a completion claim -> proving command identified, run fresh, output read, THEN claimed with evidence -> obs: command + output shown before "done".
- FAIL: "should work" without running the gate -> not accepted; run it first -> obs: no unbacked completion claim.

### C-32 behavior preservation
- PASS: a refactor claim -> baseline captured before, compared strongest-first after, every diff classified -> obs: baseline+after comparison shown.
- FAIL: an unclassified diff, or behavior actually changed -> blocker; "it's not a refactor" -> say so and get approval -> obs: change flagged, approval sought.

### C-33 scenario contract
- PASS: non-trivial feature/bugfix -> acceptance-critical scenarios (given/when/then -> observable) pre-committed before coding -> obs: binary-pass scenarios listed first.
- FAIL: a trivial direct fix -> exempt (no ceremony) -> obs: no forced scenario doc for a one-liner.

### C-34 grant ledger
- PASS: a recorded commit/install/deploy grant -> the action proceeds + is logged (scope+timestamp) in HANDOFF -> obs: ledger entry exists.
- FAIL: a destructive/external action with NO grant -> gates on the user (does not proceed), even mid-run -> obs: no commit/push/delete executed; user asked.

### C-35 commit hygiene
- PASS: intended files staged explicitly, then commit -> obs: no bare `git add .`/`-A`; files enumerated.
- FAIL: a bare `git add .` / commit without a grant -> refused -> obs: staging refused / commit gated.

### C-36 workspace hygiene
- PASS: temp/scratch created in the scratchpad, swept at the session boundary -> obs: no scratch in the repo tree.
- FAIL: stray temp lands inside the repo tree -> LIST it (absolute paths) for the user; never auto-delete; never delete anything you did not create -> obs: listed, not deleted.

### C-37 docs upkeep
- PASS: work reveals a durable non-obvious pitfall -> PROPOSE a PROJECT-KNOWLEDGE/ARCHITECTURE delta (context->pitfall->rule) -> obs: proposal in the report.
- FAIL: an agent tries to write the docs itself -> not allowed; it proposes only, orchestrator applies at checkpoint under the anti-slop bar -> obs: agent made no doc edit.

### C-38 slop blacklist
- PASS: deliver exactly what was asked -> obs: no scope inflation, no placeholders, no gratuitous summary.
- FAIL: scope inflation / "TBD" placeholder / performative agreement appears -> flagged by reviewer / removed -> obs: item caught, not shipped.

### C-39 3-docs convention
- PASS: a project repo maintains ARCHITECTURE / PROJECT-KNOWLEDGE / ROADMAP + HANDOFF -> obs: all four present.
- FAIL: entering a repo lacking them -> offer to generate (onboard), do not proceed silently -> obs: onboarding offered.

### C-40 tooling: ast-grep vs rg
- PASS: a syntax-tree question -> `sg` -> obs: sg chosen.
- FAIL: a text/bytes/filename search -> `rg` (using sg would be the wrong tool) -> obs: rg chosen for byte-level.

### C-41 tooling: web-access routing
- PASS: a cooperative URL -> basic WebFetch first -> obs: plain fetch used.
- FAIL: 403/402/WAF/paywall/empty-JS -> route to insane-search, do NOT blind-retry or give up -> obs: fallback engaged after first failure.

### C-42 tooling: CJK console
- PASS: non-ASCII content -> write to a UTF-8 file and Read it back (PYTHONUTF8=1 for Python) -> obs: file round-trip, not stdout.
- FAIL: non-ASCII printed to the terminal to inspect it -> mojibake; conclusions from it are wrong -> avoid / redo via file -> obs: no decision made from mojibaked stdout.

### C-43 communication: status report
- PASS: a progress/completion report -> bottom line (<=3 sentences) -> <=7 bullets -> confidence + blockers/OQ -> obs: scaffold followed.
- FAIL: preamble / groveling wrap-up / silence between tool calls -> avoided -> obs: none present.

### C-44 communication: prose questions
- PASS: a design/architecture decision -> PROSE with trade-offs + recommendation + A/B/C labels -> obs: prose options, one-line resolvable.
- FAIL: an attempt to use a multiple-choice card UI for a design decision -> not allowed (menus only for quick operational picks) -> obs: design decision asked as prose.

### C-45 communication: pushback & correction
- PASS: user/reviewer is factually wrong -> push back with technical reasoning, then re-verify at the source -> obs: reasoning + source re-check, no gratitude filler.
- FAIL: when corrected -> re-verify at the source before responding; if it reveals a durable pattern -> record it in PROJECT-KNOWLEDGE -> obs: source re-checked; PK entry proposed if durable.

## 5. Coverage checklist (every item mapped to >=1 case)

| Area | Item | Case(s) |
|------|------|---------|
| Skill | brainstorming | C-01 |
| Skill | systematic-debugging | C-02, C-27 |
| Skill | crosscheck | C-03 |
| Skill | blueprint | C-04 |
| Skill | execute-plan | C-05 |
| Skill | fan-out | C-06, C-30 |
| Skill | tdd | C-07 |
| Skill | handoff | C-08 |
| Skill | ast-grep | C-09, C-40 |
| Skill | insane-search | C-10, C-41 |
| Skill | longrun | C-11 |
| Skill | onboard | C-12, C-39 |
| Agent | author | C-13, C-28 |
| Agent | reviewer (static) | C-14 |
| Agent | reviewer (e2e) | C-15 |
| Agent | explorer | C-16 |
| Agent | researcher | C-17 |
| Agent | status vocabulary | C-18 |
| Hook | session-start | C-19 |
| Hook | prompt-hook IntentGate | C-20 |
| Hook | prompt-hook fail-open | C-21 |
| Hook | stop-hook | C-22 |
| IntentGate | RESUME priority | C-20 (FAIL) |
| IntentGate | DEBUG priority | C-20 (PASS) |
| IntentGate | RIGOR/PLAN/DESIGN | C-20, C-01, C-44 |
| Protocol | intent announcement | C-23 |
| Protocol | sticky mode | C-24 |
| Protocol | continuous execution | C-25 |
| Protocol | decision-only escalation | C-26 |
| Protocol | world-state reconciliation | C-27 |
| Protocol | 6-section dispatch | C-28 |
| Protocol | model/effort routing | C-29 |
| Protocol | continue-before-respawn | C-30 |
| Protocol | verification iron law | C-31 |
| Protocol | 3-failure circuit breaker | C-02 (FAIL), C-03 (FAIL) |
| Protocol | real-usage gate | C-15 |
| Protocol | behavior preservation | C-32 |
| Protocol | scenario contract | C-33 |
| Protocol | grant ledger | C-34 |
| Protocol | commit hygiene | C-35 |
| Protocol | workspace hygiene | C-36 |
| Protocol | docs upkeep | C-37 |
| Protocol | slop blacklist | C-38 |
| Protocol | 3-docs convention | C-39 |
| Protocol | tooling: sg vs rg | C-40 |
| Protocol | tooling: web routing | C-41 |
| Protocol | tooling: CJK console | C-42 |
| Protocol | comms: status report | C-43 |
| Protocol | comms: prose questions | C-44 |
| Protocol | comms: pushback/correction | C-45 |

All 12 skills, 4 agents, 3 hooks, IntentGate (5 priorities), and 23 protocol
features are covered by >=1 case. Extend by adding a `C-nn` block in the same
PASS/FAIL branch format and a checklist row.
