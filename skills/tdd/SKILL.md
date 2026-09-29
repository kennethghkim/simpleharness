---
name: tdd
description: Use for OPT-IN strict TDD when a change needs test-first rigor beyond the harness default (Light TDD) — the user asks for rigor, or the work is logic-heavy / regression-prone / high-blast-radius. Enforces the red-green-refactor loop, behavior-asserting (not text/snapshot) tests, and a floor rule. Trivial fixes stay on Light TDD (Coding Baseline).
---

# Test-Driven Development (opt-in strict)

The harness default is **Light TDD** (Coding Baseline: bugfix -> failing test
first; features test-first not mandated). Invoke THIS skill when strict
test-first is warranted: the user asks for rigor, or the change is logic-heavy /
regression-prone / high-blast-radius.

## Iron law
No production code before a failing test that demands it. Order is
RED -> GREEN -> REFACTOR, one small scenario at a time.

## RED — a test that fails for the RIGHT reason
- **Assert behavior, not text.** Assert the structural invariant AND its negative
  branch. Never a snapshot / wording pin (`toMatchSnapshot`,
  `toContain("You are...")`) that guards a diff instead of a behavior.
- Run it and READ the failure: the assertion message must prove the intended
  behavior is missing — NOT an import/syntax/typo error. A test that fails for
  the wrong reason is not a RED.
- **Async: subscribe/attach BEFORE triggering, then race an explicit timeout that
  fails with a message.** Never `sleep(N)` / `setTimeout(resolve)`.
  **FLAKY = FAILING** — 9/10 passes means broken.
- A test that mirrors the implementation (asserts mock calls, pins constants
  copied from the code) is not evidence — it passes by construction.

## GREEN — minimal code to pass
- Write the least code that makes the assertion pass; run, watch it pass.
- Self-check: if GREEN needed ~20+ lines, the test was too coarse — split the
  scenario and redo.

## REFACTOR — clean up, stay green
Only with a green bar; re-run after each change.

## No-behavior-change path (pure refactor / optimize)
Strict TDD has no failing test for a refactor. Instead write CHARACTERIZATION
tests that pin the current observable behavior (exact inputs -> observed
output/assertion), see them GREEN on the unchanged code, then refactor staying
green. This is the executable form of the Coding Baseline behavior-preservation
rule.

## Floor rule (enforceable)
Typed production code without a preceding failing test that demanded it -> STOP,
revert it, write the test, redo. Exemptions (closed list, each justified in one
line): formatting-only, comment-only, dependency version bump, pure rename.
Nothing else is exempt.

## Boundary
This skill owns the test loop. The real-usage / user-eyeball SURFACE gate is the
Verification Iron Law (CLAUDE.md) — satisfy both for UI/e2e work.
