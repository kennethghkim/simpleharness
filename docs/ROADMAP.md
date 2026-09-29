# ROADMAP — simpleharness

Two lists only: a Todo of things not built yet (each with its revive
condition), and open design questions awaiting a decision. Completed and
dropped work lives in git history and HANDOFF, not here.

## Todo

- **init-deep-style hierarchical context docs**: per-directory context docs (vs
  one root file) for large repos. Candidate from the OmO comparison
  (effort M, conceptual — a new skill, no runtime). Revive if a large
  multi-package repo needs it.

- **ast-grep smoke tests**: add smoke tests for the ast-grep helper if it ever
  regresses.

- **Multimodal extractor agent**: a read-only vision/PDF extractor sub-agent
  that returns only the analyzed extraction (context economy), modeled on OmO's
  Multimodal-Looker. Deferred: our `Read` is natively multimodal and
  the extended `reviewer` judges its own screenshots, so a dedicated agent is
  YAGNI now. Revive if media-heavy workloads (large image/PDF batches) appear.

- **Reactive tool-use nudge (PostToolUse hook) — REMOVED v1.0.1**: the tool-nudge hook
  (LSP + delegation rules) was DROPPED after an ablation showed the PROMPT
  layers suffice — LSP via the agent ToolSearch load-step + completion gate; delegation via
  the CLAUDE.md classify-then-route rule. Four hooks -> three. If a specific REACTIVE nudge
  is ever justified by a recurring anti-pattern, it means RE-INTRODUCING a PostToolUse hook
  (higher bar now) — prefer a prompt-layer fix first. Candidates seen but NOT built: a
  research-MCP nudge (context7/grep_app are instead handled by the researcher load-step);
  a systematic-debugging repeated-fix nudge; a crosscheck big-diff nudge. Revive only if the
  prompt layer demonstrably fails to cover it.

- **IntentGate IMPLEMENT recall (Korean "mandeulda" + RIGOR-shadowing) — MITIGATED v1.0.1**:
  the prompt-hook IMPLEMENT keyword rule has two failure modes — a MISSING keyword
  ("mandeulda"/make, the commonest Korean build verb, excluded for precision) and SHADOWING
  (first-match priority: "깊게"->RIGOR, "계획"->PLAN eat the single IMPLEMENT slot). Measured
  (ablation): when IMPLEMENT did not fire AND the hook was off, delegation fell to
  inline (0/2). Rather than chase keywords (whack-a-mole; OmO reserves keyword gates for
  explicit modes only), v1.0.1 added the CLAUDE.md classify-then-route rule (the model
  self-classifies regardless of phrasing). The IMPLEMENT keyword rule stays only as a bonus
  proactive pointer for obvious cases. Revive keyword-widening only if classify-then-route
  proves insufficient in practice.

- **Explorer-selection reinforcement (RECON IntentGate) — NOT built (deferred)**: the
  "prefer `simpleharness:*` over built-in generic agents" rule for the recon axis has NO per-turn
  reinforcement — only one buried CLAUDE.md sub-bullet injected at session start. Audited
  (transcript-wide): built-in `Explore` chosen over `simpleharness:explorer` 19:7 in the post-adoption
  window, still 3x AFTER classify-then-route, with the rule verified in-context and ignored
  (see PROJECT-KNOWLEDGE "Delegation enforcement covers WHETHER-to-delegate, not WHICH-agent"). This
  is the "prefer our agents" enforcement that omo-agent-adoptions said it deferred here
  but never actually tracked. Fix if revived: mirror the IMPLEMENT->author IntentGate pattern with a
  RECON/EXPLORE pointer naming `simpleharness:explorer` (EN + KO triggers) + a fixed-reminder line
  (investigation options A+B). Prefer the prompt layer over a reactive PostToolUse hook (per the
  v1.0.1 tool-nudge removal doctrine). Revive when the user wants to actually reduce the drift.

- **lsp-mcp-server bridge instability**: `npx lsp-mcp-server@1.1.20` intermittently
  disconnects mid-session and crashed on a Windows TS spawn (see PROJECT-KNOWLEDGE
  "bridge disconnects mid-session"). Investigate a newer version / restart-supervision
  / root cause before treating the LSP gate as a hard requirement.

- **prompt-hook IMPLEMENT-pointer test coverage**: `tests/prompt-hook.tests.ps1`
  asserts the RESUME/DEBUG/RIGOR/PLAN/DESIGN pointers but has no case for
  IntentGate rule 6 (IMPLEMENT, added v1.13.0) — the gap surfaced when
  the "plain prompt" case turned out to contain `refactor` and silently collided
  with rule 6 (fixed by rewording). Add an IMPLEMENT positive case (+ its Korean
  trigger) next time the prompt hook or its tests are touched.

## Open questions

- None currently.
