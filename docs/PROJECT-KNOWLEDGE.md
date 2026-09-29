# PROJECT-KNOWLEDGE — simpleharness

Accumulated pitfalls, caveats, and lessons. Append new entries at the bottom:
`context → pitfall → rule`.

## Skills under-trigger for always-on behavior
- Context: skill descriptions gate on-demand invocation; a skill fires reliably
  only for conditional, task-shaped procedures the model recognizes it needs.
- Pitfall: encoding always-on, protocol-level behavior (the session loop,
  handoff, behavior preservation) in a skill means it is invoked inconsistently
  while the behavior it encodes is needed every session.
- Rule: core-loop behavior lives in CLAUDE.md; skills carry only on-demand,
  conditional procedure.

## CJK-locale console mojibakes UTF-8
- Context: on CJK-locale Windows, `cmd`/pwsh stdout mangles non-ASCII text
  (CJK characters and other non-ASCII bytes).
- Pitfall: printing non-ASCII text to the terminal to inspect it produces
  garbage; conclusions drawn from that output are wrong.
- Rule: write non-ASCII content to a UTF-8 file and Read it back; set
  `PYTHONUTF8=1` for Python subprocesses; verify text artifacts via files,
  never stdout.

## POSIX-path drift in Windows-first artifacts
- Context: artifacts authored with POSIX idioms (`/tmp/`, `sha256sum`, `cmp`,
  bash heredocs) on a Windows-primary machine.
- Pitfall: examples that cannot be pasted into the primary shell silently
  stop being followed.
- Rule: harness artifacts are Windows-first (PowerShell 7 + scratchpad
  paths); POSIX alternates second.

## Agent-frontmatter `mcpServers` is silently ignored — register MCP at plugin scope
- Context: `researcher` was given three remote MCP endpoints (exa `websearch`,
  `context7`, `grep_app`) declared inline in the agent's `mcpServers`
  frontmatter, with access granted via bare `mcp__<server>` entries in `tools`.
- Pitfall: Claude Code does NOT read an `mcpServers` key in subagent
  frontmatter — the servers are never instantiated. Transcript audit over 6 real `researcher` dispatches: the three servers were
  never present in the agent's offered tool set and never invoked; every run
  silently fell back to native WebSearch/WebFetch/gh with no error emitted. A
  subagent's `tools:` allowlist also does not gate MCP tools — subagents
  inherit the whole plugin/global MCP registry regardless of what they list.
- Rule: register MCP servers at PLUGIN scope in the plugin-root `.mcp.json`
  (`{"mcpServers": {...}}`; `type: http` + `url` for remote). They then surface
  to every agent/session using the plugin, namespaced
  `mcp__plugin_<plugin>_<server>__<tool>` (e.g.
  `mcp__plugin_simpleharness_websearch__*`) — so `tools:` allowlist entries
  must use that full namespace, not the bare `mcp__<server>` form. Per-agent
  scoping is not achievable at runtime; accept session-wide availability.

## Plugins cannot ship CLAUDE.md — inject at SessionStart
- Context: pluginizing the harness; the operating protocol must be always-on.
- Pitfall: a CLAUDE.md at the plugin root is NOT loaded as context (documented
  limitation) — a plugin relying on it silently loses its core protocol.
- Rule: ship the protocol file inside the plugin and inject it with a
  SessionStart hook (matcher `startup|clear|compact` so it also re-injects
  after /clear and compaction; output via
  `hookSpecificOutput.additionalContext`). Plugin `hooks/hooks.json` nests
  events under a top-level `hooks` key; hook processes get
  `CLAUDE_PLUGIN_ROOT` as an env var and it expands inside command strings.

## Always-on protocol content pays per-session token cost
- Context: CLAUDE.md is injected at every session start (plugin SessionStart
  hook) and loaded natively in profile mode; compressed following
  the upstream skill library's bootstrap-compression approach.
- Pitfall: framing prose, restating structure (diagrams/tables that encode
  what prose already says), and duplicated rules silently tax every session.
  A protocol that is already rule-dense compresses little (-11% here) — the
  real win is refusing dilution up front.
- Rule: CLAUDE.md carries rules and quoted phrases only. New content must be
  a behavior-shaping rule, stated once, in its densest correct form; anything
  else belongs in skills (on-demand) or docs (not injected).

## User grants are durable
- Context: some agent conventions treat authorization as turn-local (expiring
  each message). This harness targets an operator who issues scoped blanket
  grants once and expects them to hold for the whole work stream.
- Pitfall: re-asking for granted permissions mid-loop reads as a stall;
  forgetting a grant after compaction reads as amnesia.
- Rule: record grants (scope + timestamp) in HANDOFF.md's Grant Ledger as
  they occur; ungranted destructive actions still gate.

## ASCII lint vs em-dashes in scripts
- Context: `scripts/*.ps1` must be pure ASCII (CJK mojibake defense), enforced
  byte-level by `tests/harness-lint.ps1`.
- Pitfall: U+2014 em-dashes slip into `.ps1` comments when prose is reflexively
  prettified; they fail the byte-level lint even though comments never reach
  stdout (caught in session-start-hook.ps1 and deploy.ps1 on the lint's first
  run).
- Rule: use ASCII `--` in `scripts/*.ps1`; run
  `pwsh -NoProfile -File tests/harness-lint.ps1` before commit.

## Hook stdin must be read as raw UTF-8
- Context: UserPromptSubmit hook input JSON carries the user's prompt;
  IntentGate matches Korean keywords in it.
- Pitfall: `[Console]::In.ReadToEnd()` decodes stdin via the console codepage
  on CJK-locale Windows and mangles Korean; literal Korean in the script would
  also fail the ASCII lint.
- Rule: read hook stdin via `StreamReader([Console]::OpenStandardInput(),
  UTF8)`; encode non-ASCII regex literals as `\uXXXX` escapes.

## Plugin updater skips cache refresh when the version string is unchanged
- Context: `claude plugin update` pulls the marketplace clone, then compares
  plugin.json version strings before refreshing the installed cache copy
  (`plugins/cache/<mkt>/<plugin>/<version>/`) that live sessions actually load.
- Pitfall: pushing new content without bumping the version reports "already at
  the latest version" while sessions keep running the stale cache copy
  (observed: marketplace clone at the new HEAD, cache still old).
- Rule: every content release bumps plugin.json (and the README version string
  — the lint's version check pairs them); then `claude plugin update` +
  `/reload-plugins` in live sessions (no full restart needed). Note: profiles
  that share one `plugins` directory (symlink or junction) also share this
  cache.

## Stop-hook block messages must state the true condition
- Context: the plan-aware Stop gate can block even when HANDOFF.md was written
  today (checkpoint older than the latest plan edit).
- Pitfall: reusing the generic "no HANDOFF.md checkpoint today" text for the
  plan branch would be factually wrong in that case.
- Rule: each block branch carries its own accurate reason/systemMessage; never
  reuse a message whose condition does not match the branch.

## The Stop hook blocks only for plan execution, not generic completion
- Context: through 1.0.1 the Stop hook defaulted to blocking any stop that lacked
  a same-day HANDOFF.md, injecting a generic "Incomplete tasks remain" re-check.
- Pitfall: it had no signal for "this session did no checkpoint-worthy work", so
  it false-positived on every answer-only / read-only session, and fired
  repeatedly when the `stop_hook_active` loop guard did not persist across turns.
- Rule (1.0.2+): the Stop hook blocks ONLY when an active ACTIVE-PLAN.md has
  unchecked items; every other stop is allowed silently. Do not reintroduce a
  work-agnostic completion block -- checkpoint discipline is carried by the
  handoff skill + the protocol, not by nagging on stop.
- Addendum (1.0.3): a stateless "unchecked items -> block" gate
  cannot tell forward progress from stagnation, so it punished exactly the
  workflow it exists to support -- measured: a user checking one item off per
  turn was still blocked at every turn end for the remaining items (30
  blocks/day, 9 repeats at the same count). The gate is now progress-aware via
  a per-session state file (`<TEMP>/sh-stopgate-<KEY>.json`, KEY = hook
  session_id else lowercase MD5 of the project dir; fields planPath /
  mtimeTicks / unchecked / nudged): first stop of a session = free pass; plan
  mtime advanced since the last stop (an item checked off) = progress -> silent
  allow + streak reset; only a stagnant plan (two consecutive stops with the
  plan untouched) earns exactly ONE nudge per streak (`nudged` latched). State
  IO is fail-open and never flips an allow into a block.

## insane-search is vendored from fivetaku, not from oh-my-openagent
- Context: `skills/insane-search` is vendored from `fivetaku/insane-search@v0.9.1`
  (SOURCE pin 2714e72, MIT). The OmO comparison found oh-my-openagent
  ships a divergent copy of the SAME engine as its `ultimate-browsing` skill —
  its ATTRIBUTION.md names it "the insane-search Tier-1 fetch engine".
- Pitfall: assuming OmO is our upstream (or that our copy is original) is wrong —
  the two have already fork-drifted (OmO added curl_probe / referers /
  result_schema / summary; ours added learning / phase0 / transport / safety /
  content_safety). Syncing from OmO would import the wrong divergence.
- Rule: sync insane-search ONLY from `fivetaku/insane-search`, re-applying the
  local adaptations recorded in `skills/insane-search/SOURCE`; never from OmO.

## Claude Code never auto-cleans the session scratchpad
- Context: the per-session temp scratchpad lives at `%LOCALAPPDATA%\Temp\claude\<project>\<session>\{scratchpad,tasks,tool-results}` and is shared across a session's subagents.
- Pitfall: Claude Code does NOT clean it on graceful exit OR force-close (confirmed via docs + GitHub #17990/#11963, and directly observed: a force-closed session still held 6215 files incl. a 113MB clone the next day). Windows Temp is not purged on process exit, so orphans accumulate indefinitely.
- Rule: never rely on scratchpad auto-clean. Keep scratch through the session (mid-run artifacts may be re-referenced); clean at session boundaries ONLY -- `handoff` sweeps this session at checkpoint, and the SessionStart hook (`scripts/scratch-gc.ps1`, age>7d, scope-locked to scratchpad/tasks/tool-results, fail-open) GCs orphans at next start. Never touch Claude Code state (projects/ transcripts, sessions, cache, backups). Delete large clones explicitly once their consuming stream ends.

## Subagent tool lists (`tools:` / `disallowedTools:`) ARE runtime-enforced -- reconciled
- Context: an earlier probe concluded `tools:` was NOT enforced -- a
  `reviewer`/`researcher` allegedly held the FULL parent toolset (Agent/Edit/Write/
  MCP) regardless of their allowlist. Re-tested during the shakedown with disk
  ground-truth after the v1.11.1 denylist switch.
- Pitfall: that earlier conclusion was WRONG -- it rested on agents SELF-REPORTING
  their toolset, which is unreliable (agents also falsely claimed MCP tools they did
  not have; see the subagent-MCP entry). Verified this session: (a) a `tools:`
  allowlist ZEROED OUT MCP for 6 subagents; (b) the fixed `reviewer`'s
  `disallowedTools: Write, Edit, NotebookEdit` removed those three ENTIRELY from its
  runtime toolset (absent from base tools AND the deferred registry) and it could not
  create a probe file (disk-confirmed: file never appeared). The harness strips
  denied/unlisted tools BEFORE dispatch (they never reach the agent), not by
  intercepting calls.
- Rule: `tools:`/`disallowedTools:` ARE a real runtime boundary here -- rely on them.
  v1.11.1 uses denylists (reviewer/explorer/researcher deny Write/Edit/NotebookEdit;
  author denies Agent). Still assert the read-only / no-delegation contract in each
  agent PROMPT as defense-in-depth, and NEVER trust an agent's self-report of its own
  toolset over a disk/behavior check ("subagents lie" applies to capability claims too).
- Corollary (MCP naming): running INSIDE the repo, a project `.mcp.json` in cwd
  registers the servers at PROJECT scope, surfacing them flat as `mcp__<server>__*`
  (e.g. `mcp__websearch__*`), which SHADOWS the plugin-scope
  `mcp__plugin_simpleharness_<server>__*` names a plugin consumer sees. Grant/
  expect the name matching the target environment.

## Harness coverage-test convention (operator persona; PASS=success, FAIL=failure branch)
- Context: the operator periodically asks to "test all skills/features" for
  coverage. The first attempt mis-modeled FAIL as a negative test
  (behavior that must NOT happen) and was corrected.
- Pitfall: modeling FAIL as "the harness misbehaves" yields contrived, low-value
  cases and never exercises the harness's real failure-handling paths (circuit
  breakers, escalation ladders, gates, fail-open).
- Rule: a coverage test uses OPERATOR-PERSONA scenarios (terse, auto-mode,
  delegation-heavy, brief deltas, one-word resumes; Korean OK, artifacts English)
  and, per feature, exercises BOTH branches with a binary observable each --
  PASS = the success path; FAIL = the feature's OWN failure/exception branch
  (e.g. debugging fails 3x -> fresh-eyes consult / 3-failure circuit breaker;
  reviewer REVISE -> re-dispatch loop; ungranted destructive action -> user gate;
  blocked site -> insane-search; torn resume tail -> validated-only resume; hook
  error -> fail-open). Cover every skill + agent + hook + IntentGate priority +
  protocol feature >=1x and prove it with a coverage checklist. Canonical suite
  and exact output format: `docs/eval/skill-coverage-cases.md` -- regenerate or
  extend in THAT format on the next coverage request.

## Pyright resolves imports against the project's interpreter/venv
- Context: the bundled `lsp` MCP drives `pyright` for Python diagnostics. Pyright
  resolves third-party imports against the project's configured Python
  interpreter / virtualenv, not a global one.
- Pitfall: without the right interpreter selected, pyright flags installed
  third-party imports as "unresolved import" -- false diagnostics that look like
  real errors when using LSP diagnostics on a Python project.
- Rule: point pyright at the project's venv/interpreter (via the project's
  `pyrightconfig.json` / venv, or expect false unresolved-import diagnostics)
  before trusting LSP diagnostics on a Python project.

## lsp-mcp-server@1.1.20 hardcodes `pylsp` for Python -- pin pyright via `~/.lsp-mcp.json`
- Context: the bundled `lsp` MCP is `lsp-mcp-server@1.1.20`. Source-audited
  at published SHA `86b0598` (== the tarball `npx` runs): it holds
  ONE hardcoded server entry per language (`constants.ts DEFAULT_SERVERS`); for
  `.py` it is literally `command:"pylsp", args:[]`. `getClientForFile` picks the
  first entry whose extensions match -- there is NO priority list, NO PATH probe,
  NO fallback. `pyright-langserver` is never a candidate.
- Pitfall: (a) The earlier belief that the bridge "prefers pylsp when both are on
  PATH" was WRONG -- pyright was never considered; pylsp only appeared to win
  because it is the sole default and happened to be installed on the dev machine.
  (b) On any machine WITHOUT pylsp (every consumer -- `environment-setup` installs
  pyright + typescript-language-server, not pylsp) the bridge spawns `pylsp` ->
  ENOENT -> 3 restart attempts -> SERVER_START_FAILED: Python diagnostics are
  entirely dead, not merely un-typed. (c) The documented `LSP_CONFIG_PATH` env var
  and any CLI `--config` flag are NOT implemented in 1.1.20 (dead constant / no
  argv parsing) -- the ONLY override channel is a config file. (d) On Windows the
  override cannot name `command:"pyright-langserver"`: the bridge spawns with
  `shell:false`, and npm-global pyright ships no `.exe` (bare shim -> ENOENT;
  `.cmd` -> EINVAL post-CVE-2024-27980).
- Rule: pin Python to pyright with a config file whose `servers[]` entry merges
  over the builtin by `id`. Discovery order (first file that PARSES wins -- no
  cross-file merge, so a project-local `.lsp-mcp.json` in the launch cwd SHADOWS
  the home pin): `$cwd/.lsp-mcp.json`, `$cwd/lsp-mcp.json`,
  `$XDG_CONFIG_HOME|~/.config/lsp-mcp/config.json`, `~/.lsp-mcp.json`.
  `environment-setup` writes `~/.lsp-mcp.json` = `{"servers":[{"id":"python",
  "extensions":[".py",".pyi"],"languageIds":["python"],"command":"node",
  "args":["<npm root -g>/pyright/langserver.index.js","--stdio"],"rootPatterns":[...]}]}`.
  The langserver path is machine-specific -> generate it where pyright is
  installed, never a static committed literal. Verify the active backend with a
  deliberate type-error file (`x: int = "hello"`): open it with `lsp_index_files`,
  then read `lsp_workspace_diagnostics` -- pyright emits `reportAssignmentType`
  (pylsp/pyflakes does not). Per-file `lsp_diagnostics` returns empty on Windows
  (next entry).
- TS/JS SAME failure on Windows: the bridge's default `typescript` entry runs the
  `typescript-language-server` shim (no `.exe`), so it also ENOENTs under
  `shell:false` (server crash -> ZERO TS/JS diagnostics). `environment-setup`
  therefore ALSO writes an `id:"typescript"` entry =
  `node <npm root -g>/typescript-language-server/lib/cli.mjs --stdio` (exts
  `.ts/.tsx/.js/.jsx/.mjs/.cjs/.mts/.cts`). Verified: TS went from
  SERVER_START_FAILED to real tsserver diagnostics (codes 2322/2552).

## per-file `lsp_diagnostics` misses pyright diagnostics on Windows -- use `lsp_workspace_diagnostics`
- Context: verifying the v1.10.1 pyright pin via the bridge's debug
  log. pyright pushes `publishDiagnostics` under a normalized URI
  `file:///c%3A/...` (LOWERCASE drive, percent-encoded colon) and the bridge
  caches under that key; `lsp-mcp-server@1.1.20` is the latest (no upstream fix).
- Pitfall: `lsp_diagnostics(file_path)` derives its lookup key from the caller's
  path (`C:\...` -> `file:///C:/...`, uppercase) and MISSES the lowercase-drive
  cache key -> returns empty `diagnostics: []` even though pyright found the
  errors (confirmed: pyright's cache held 2 errors, per-file query returned 0).
  Passing a lowercase-drive path does NOT help -- the bridge keys servers by
  `(id, root)` and just spawns a SECOND python server for the new-looking root.
  pylsp did not trip this (no lowercase URI normalization), which is why the
  earlier pylsp dogfood saw a diagnostic.
- Rule: on Windows, read diagnostics via `lsp_index_files [file]` (open) then
  `lsp_workspace_diagnostics` (dumps all opened-file diagnostics, keyed
  correctly) -- NOT per-file `lsp_diagnostics`. Verified:
  workspace_diagnostics returned pyright's `reportAssignmentType` +
  `reportUndefinedVariable`; per-file returned empty for the same file/session.

## Subagent `tools:` allowlist zeroes out MCP tools -- use `disallowedTools:` (config, not a platform limit)
- Context: shakedown. 6 dispatched subagents (author x3, reviewer, explorer,
  researcher) had NO callable MCP tool (no `lsp`; context7/websearch/grep_app injected only
  their INSTRUCTION text, no callable `mcp__*` functions; researcher fell back to native).
  Root-caused via CC docs (code.claude.com sub-agents/mcp/plugins-reference, current
  v2.1.200), an UNRESTRICTED-subagent probe, and OmO's `librarian` agent.
- Root cause (CONFIRMED -- config, NOT platform, NOT orchestrator-only): subagents inherit MCP
  by DEFAULT; a `tools:` ALLOWLIST overrides that and grants ONLY listed tools resolved against
  the runtime pool. A `general-purpose` subagent with NO `tools:` restriction received ALL 81
  session MCP tools in the SAME session -> MCP-to-subagent works. Our 4 agents use a `tools:`
  allowlist listing PLUGIN-scope names (`mcp__plugin_simpleharness_<server>`); running INSIDE
  the repo the servers register at PROJECT scope under BARE names (`mcp__websearch__*` etc., no
  `plugin_simpleharness_` infix) and `lsp` was not registered at all -> the allowlist matched
  nothing -> zero MCP. (In a real plugin CONSUMER the names would be
  `mcp__plugin_simpleharness_<server>__*` and MAY match -- so the dev-repo failure is partly an
  artifact -- BUT the allowlists also omit `ToolSearch`, which deferred MCP tools need to
  invoke, so consumers are NOT proven safe either.) Earlier same-session claims that subagents
  "inherit the whole MCP registry" were unreliable self-report (conflating injected
  server-instructions with callable tools) -- this corrects the two entries above.
- Rule: for limited subagents use `disallowedTools:` (denylist -- deny Write/Edit for read-only
  roles, Agent for no-delegation roles) so they INHERIT all MCP + ToolSearch, instead of a
  `tools:` allowlist of MCP names (mirrors OmO's `librarian`, which uses a denylist so MCP
  flows by inheritance). Plugin-shipped agents SILENTLY IGNORE `mcpServers:`/`hooks:`/
  `permissionMode:` frontmatter (documented) -> NOT a fix path. Verify any fix with a real MCP
  tool CALL, not instruction-text presence.
- Fixed (v1.11.0): the 4 agents switched from a `tools:` allowlist to a
  `disallowedTools:` denylist (author denies `Agent`; reviewer/explorer/researcher
  deny `Write, Edit, NotebookEdit`) so MCP + ToolSearch are inherited. Mechanism
  proven and CONFIRMED end-to-end: after `plugin update` to 1.11.0, a fresh
  session dispatched the fixed `reviewer`, which held the full
  `mcp__plugin_simpleharness_lsp__*` set (29 tools) + websearch/context7/grep_app/
  playwright and successfully CALLED `lsp_index_files` + `lsp_workspace_diagnostics`,
  returning real Pyright diagnostics (was ZERO MCP before the fix). MCP arrives DEFERRED
  (ToolSearch-then-call), which the denylist inherits.

## Autonomous LSP use needs mandated loading + a completion gate + a nudge hook
- Context: we want author/reviewer/explorer to use the `lsp` MCP autonomously without a
  per-task "use LSP" instruction. Measured (goal-only autonomy dogfood, transcript
  ground-truth): the agent auto-fired the `brainstorming` skill but made ZERO LSP/ToolSearch
  calls -- MCP being DEFERRED (reachable only after a ToolSearch step the model does not
  spontaneously run) makes soft "prefer LSP" nudges invisible.
- Pitfall: a DEFERRED capability + suggestion-strength directives = zero adoption. Per-server
  `alwaysLoad: true` makes tools eager but our lsp server has ~29 tools (CC docs: "small number
  only") -- heavy. A PostToolUse hook CAN inject `additionalContext` (probed + confirmed: the
  caller reads it), BUT models REFUSE injected IMPERATIVE instructions as prompt-injection --
  a nudge must be ADVISORY, never "you must run X".
- Rule (v1.12.0, LSP-first, generic-extensible): for a capability meant to be used
  autonomously -- (1) name the tool + when-to-use + a "load it first" step in the always-on
  agent prompt (mandate a `ToolSearch`-load rather than pay alwaysLoad's 29-tool context cost);
  (2) tie it to the completion gate ("not done until `lsp_workspace_diagnostics` clean on
  changed files"); (3) back it with a stateful, capped (<=3), self-suppressing PostToolUse
  reminder firing on the anti-pattern (grep-for-symbol / edit-without-lsp), ADVISORY wording
  (`scripts/tool-nudge-hook.ps1`). Verify adoption by re-running the goal-only dogfood and
  counting LSP calls in the transcript (target 0 -> >=1).
- RESULT (v1.12.0): the AUTHOR/delegated path PASSED -- a session run as the
  `author` on a bare code task autonomously did `ToolSearch` x2 + 12 lsp calls (functional,
  no explicit prompt; before 0 -> after 12). The goal-only INLINE path is still 0 (a bare
  goal builds inline, no delegation -> agent prompts never apply, advisory nudge ignored)
  -- a separate auto-delegation gap, see ROADMAP.

## lsp-mcp-server bridge disconnects mid-session (intermittent)
- Context: the bundled `lsp` MCP is `npx lsp-mcp-server@1.1.20`. Observed: in one
  `claude -p` dispatch the server DISCONNECTED mid-run ("the following deferred tools are no
  longer available ... LSP"); earlier the same bridge CRASHED on a Windows TS spawn
  (`ERR_STREAM_DESTROYED` after the `typescript-language-server` ENOENT). A clean re-run was
  stable with 12 successful lsp calls -- so it is INTERMITTENT.
- Pitfall: LSP availability is not guaranteed within a session -- a mid-task disconnect makes
  the `lsp_workspace_diagnostics` completion gate un-satisfiable for that run and makes an
  autonomous-LSP test inconclusive (cannot tell "agent skipped lsp" from "lsp was down").
- Rule: treat LSP as best-effort (agents fall back to rg/sg on drop -- already in prompts);
  do not make the LSP gate a HARD blocker until the bridge is stabilized. Investigate the
  crash (logs / newer lsp-mcp-server / restart-supervision). Tracked in ROADMAP.

## insane-search engine false-positives on a Cloudflare "One moment, please..." challenge
- Context: shakedown routed a crunchbase 403 to `python -m engine <url>`.
- Pitfall: the engine returned `ok=True verdict=weak_ok` on a page that was actually a
  Cloudflare interstitial ("One moment, please...", `_cf_chl_opt`,
  `/cdn-cgi/challenge-platform/`, "Enable JavaScript and cookies to continue"). That variant's
  markers are not in the validator's challenge-marker list, so the 4-layer validation passed
  an UNSOLVED challenge as success -- the real page was never retrieved.
- Rule: add the "One moment, please..." / `_cf_chl_opt` / `/cdn-cgi/challenge-platform/`
  markers to the engine validator's challenge set (engine/validators.py). Until then, treat a
  `weak_ok` on a known-WAF host with suspicion and inspect the body for challenge markers.

## ast-grep skill install.ps1 (winget) leaves `sg` off PATH on Windows
- Context: shakedown -- `sg`/`ast-grep` absent; ran the skill's install.ps1.
- Pitfall: install.ps1 -> `winget install ast-grep.ast-grep` succeeds but places `sg.exe`/
  `ast-grep.exe` only under `%LOCALAPPDATA%\Microsoft\WinGet\Packages\ast-grep.ast-grep_.../`
  with NO WinGet Links shim, so `sg` is NOT on PATH -- every `sg ...` call fails with "not
  recognized" until PATH is fixed (or the full package path is used).
- Rule: install.ps1 should, after the winget install, resolve the package exe dir and add it
  to the user PATH (or symlink `sg.exe` into a dir already on PATH), then verify `sg --version`
  in a fresh shell. Meanwhile call ast-grep via its full Packages-dir path.

## Auto-delegation gap: bare goals build inline, bypassing the agent-only enforcement stack -- fixed v1.13.0
- Context: the v1.12.0 autonomous-LSP apparatus (ToolSearch load-step + LSP completion
  gate + tool-nudge advisory) lives ENTIRELY in the agent prompts (author/reviewer). The
  main thread carries only the soft CLAUDE.md rules + the advisory nudge.
- Pitfall: a bare production-code goal to the main session is rationalized as "trivial
  single-file work" (the old CLAUDE.md delegation exception was SIZE-based) and built
  INLINE -- no author dispatch, so the agent prompts never apply and the advisory nudge is
  ignored (no backing gate on the main thread). Measured (transcript
  ground-truth): goal-only inline = 0 lsp calls; author-delegated = 12. The enforcement
  never reaches the common bare-goal path.
- Rule (v1.13.0, 3 reinforcing layers, mirrors the v1.12.0 LSP layering, complementary
  precision/recall): (1) CLAUDE.md delegation boundary is KIND-based not size-based --
  production code (feature/bugfix/refactor, ANY size) MUST delegate to an author; only
  meta/config/memory/harness files, trivial edits (one-liner/version/typo/doc), or a
  declared ad-hoc fix mode stay inline ("it's just a small function" is explicitly NOT an
  exception). (2) UserPromptSubmit IntentGate rule 6 (HIGH-PRECISION: implement/refactor/
  scaffold/rewrite + KO guhyeon/gaebal/ripaekteo; broad add/make/fix/create excluded)
  injects a delegate pointer BEFORE the model acts. (3) tool-nudge-hook delegation rule
  (HIGH-RECALL safety net): the main thread (no agent_id/agent_type) editing code without a
  dispatch this session -> advisory, cap 3, self-suppress once an Agent/Task dispatch is
  seen; a subagent is exempt (an author is supposed to edit). Verify by re-running the
  goal-only dogfood: PRIMARY = an author dispatch appears (bridge-independent); SECONDARY =
  lsp fires on the author path.

## IntentGate IMPLEMENT rule misses the most common Korean build verb ("만들다")
- Context: v1.13.0 added prompt-hook IntentGate rule 6 (IMPLEMENT) to steer code-implementation
  prompts toward author delegation. Triggers are HIGH-PRECISION only (implement/refactor/scaffold/
  rewrite + KO guhyeon/gaebal/ripaekteo); broad verbs (make/add/create/fix) were deliberately
  excluded to avoid non-code false positives.
- Pitfall: measured (dogfood #2, goal "...CLI todo manager mandeureojwo [make]"): the
  IMPLEMENT pointer did NOT fire (Layer2=0) because "mandeulda/mandeureo" (make/build) is in the
  excluded-verb set -- yet it is the MOST COMMON Korean phrasing for "build me a program."
  Delegation STILL happened (via the CLAUDE.md kind-based backbone + an autonomous brainstorming
  skill), so defense-in-depth held, but the PROACTIVE pointer has low recall on the natural phrasing.
- Rule: the multi-layer stack tolerates a single-layer miss (backbone caught it), so this is a
  TUNING item, not a break. If proactively nudging Korean build-requests matters, add the "mandeul"
  stem (and EN "build" / "create ... app|cli|module|service|endpoint") to rule 6 -- but re-check
  precision (make/create fire in non-code contexts; the exclusion was deliberate). Phase-2 candidate.

## Subagent transcripts live in a SEPARATE, sometimes deeply-nested dir; tool-nudge state is shared main+sub by session_id
- Context: measuring autonomous tool-invocation stats from nested `claude --plugin-dir` dogfoods. Inspections scanned only the project-dir transcript (`projects/<proj>/<sid>.jsonl`)
  and/or a hardcoded `projects/subagents/` path, and reported subagent LSP/MCP calls as 0.
- Pitfall: that UNDERCOUNTS -- a dispatched subagent's turns are NOT in the caller's project-dir
  jsonl (that holds only the caller's own tool_use: the Agent dispatch + main-thread work). They are
  written to a SEPARATE `agent-<id>.jsonl`, but the parent dir VARIES: dogfood #1/#2 put it at
  `projects/subagents/`, while a `--plugin-dir` + `--resume` run put it DEEPLY nested under a
  cwd-derived project key (`projects/<long-cwd-name>/<sid>/subagents/agent-*.jsonl`). A hardcoded
  path misses it -> false "0 MCP/LSP". Also: the PostToolUse tool-nudge STATE file
  (`sh-nudge-<sid>.json`) is keyed by the MAIN session_id and SHARED by the subagent's hook events
  (the author's lsp calls set lspUsed=true; its pre-lsp grep/edit fired the lsp advisory).
- Rule: to measure a delegated run, RECURSIVELY find `agent-*.jsonl` under `projects/` filtered by
  mtime in the run window (never a hardcoded subdir), plus the project-dir main jsonl; corroborate
  with the sh-nudge state file (lspUsed/delegated/counts). Never conclude "the subagent did not use
  X" from the caller transcript or a hardcoded path alone ("subagents lie" extends to naive
  transcript inspection -- verified twice: the naive summary said MCP=0 when LSP=4 was in the nested
  subagent files).

## Remote research MCPs (context7/grep_app/websearch) lose to native WebFetch without active enforcement
- Context: dogfood #3 (complex project, multi-turn). Turn 4 was a terse "research the
  latest GitHub release-API pagination / rate-limit handling and apply it" -> dispatched `researcher`.
- Pitfall: the researcher did the research via native WebFetch (5 calls) and made ZERO calls to the
  bundled research MCPs (context7 / grep_app / websearch), though they were available by inheritance.
  Measured across all transcripts: MCP calls = LSP only (4); other MCP = 0. Confirms the v1.12.0
  asymmetry -- only LSP is actively use-enforced (prompt load-step + gate + nudge); the remote MCPs
  have no gate/nudge, so the model reaches for the native fallback it already knows.
- Rule: do not assume a bundled MCP is used just because it is available + soft-routed in a prompt.
  If a specific MCP (e.g. context7 for version-accurate library docs) must actually fire, it needs
  the same active enforcement LSP got (deferred-load step + a completion/anti-pattern nudge), not
  mere availability. This is the measured evidence behind the Phase-2 context7-nudge candidate (ROADMAP).
- Applied (prompt layer, no version bump): websearch (exa) REMOVED from `.mcp.json`
  (native WebSearch sufficient); context7 + grep_app got a researcher `ToolSearch` load-step at
  research start -- the root cause was the MISSING load-step (they were routed in the prompt but,
  being DEFERRED, never loaded, so the always-available WebFetch fallback won). A PostToolUse
  research nudge stays DEFERRED pending a re-measure dogfood. NOTE: keeping the version at 1.0.0
  means `claude plugin update` will NOT propagate the `.mcp.json` removal to consumers (unchanged
  version -> cache-refresh skipped) -- a real redistribute needs reinstall.

## Ablation: the PostToolUse tool-nudge hook was REMOVABLE -- prompt layers suffice (dropped v1.0.1)
- Context: the 3-layer autonomous-enforcement stack (agent-prompt load-step + completion gate
  + PostToolUse tool-nudge hook) was suspected over-built. Ran an ablation (hook
  OFF via a hooks.json toggle, `claude --plugin-dir` single-turn probes, 2 samples/condition).
- Findings (fresh): (a) LSP 2/2 fired with the hook OFF -- the agent ToolSearch load-step +
  completion gate alone drive autonomous LSP (matches the research-MCP result: a prompt
  load-step flipped context7/grep_app 0->10 with no hook). (b) Delegation: with the hook OFF,
  a bare code goal delegated 2/2 IFF the IntentGate IMPLEMENT pointer fired; when it did NOT
  (probe wording "깊게" hit the higher-priority RIGOR rule and shadowed IMPLEMENT), delegation
  fell to INLINE (0/2). The CLAUDE.md kind-based backbone is a soft floor that does NOT by
  itself stop inline building -- a PROACTIVE per-turn driver is required.
- Rule (v1.0.1): DROPPED the PostToolUse tool-nudge hook (deleted `scripts/tool-nudge-hook.ps1`
  + its hooks.json entry; four hooks -> three). The reactive net is NOT needed IF the proactive
  layer is reliable. LSP keeps prompt load-step + completion gate; delegation gets a new
  CLAUDE.md "classify-then-route" rule (model self-classifies each request; production code ->
  delegate, regardless of phrasing) -- the IMPLEMENT keyword pointer stays only as a bonus.
- OmO corroboration (`code-yeongyu/oh-my-openagent` @ `c8ee6fa`, verified): OmO independently
  ships a proactive keyword IntentGate but reserves it for EXPLICIT opt-in mode tokens
  (ultrawork/team-mode/hyperplan) and delegates broad implicit-intent classification to the
  MODEL via a prompt-enforced "verbalize intent first" rule -- NOT keyword matching. Its
  reactive layer is a file-glob rule-doc injector, not a tool-name nudge. So keyword
  intent-inference is the fragile part (two failure modes: missing keyword + first-match
  shadowing); prefer model self-classification for implicit intent, reserve keyword gates for
  explicit triggers. Cheap keyword-gate hardening OmO uses (adopt if we widen ours): strip code
  fences before matching, word-boundary + false-positive guards, skip slash/synthetic/subagent
  turns, dedup already-injected pointers.

## harness-lint does not check hook/component COUNT prose -- count drift is unguarded
- Context: dropping the PostToolUse hook (v1.0.1) required syncing "four hooks -> three" across
  README / SPEC / ARCHITECTURE. A dead-code audit (explorer) found SPEC.md still said
  "four hooks" (L5) and "4 hooks" (L53) after the sync -- the §6 body + README + ARCHITECTURE were
  correct, so SPEC self-contradicted.
- Pitfall: `tests/harness-lint.ps1` verifies hook script PATHS exist (Check 2) and the plugin
  version pairs README<->plugin.json (Check 3), but it never checks the "N hooks / N skills /
  N agents / N MCP" SUMMARY COUNTS in prose. So adding/removing a component silently drifts those
  count lines and no test catches it (the multi-line four->three edit missed two SPEC lines).
- Rule: when adding/removing a hook/skill/agent/MCP, grep-sweep the counts by hand across `docs/`
  + `README.md` (e.g. `grep -nE "four hooks|4 hooks|three hooks|3 hooks"`) and reconcile EVERY
  occurrence -- the lint will not.
- Automation ATTEMPTED + REVERTED: a Check 11 that regex-matched "N (hook|skill|agent)"
  in README/SPEC/ARCHITECTURE and compared to the real hooks.json/skill-dir/agent counts produced
  5 FALSE POSITIVES on a correct repo -- "N noun" is pervasive in NON-total contexts the regex
  cannot distinguish: a section number ("3.11 Skills" -> "11 skills"), a per-task count ("route
  related failures to one agent"), a compound ("one skill-pointer line"), and a legitimate SUBSET
  ("the two hook scripts" copied in profile mode, vs 3 total). Distinguishing total-summary counts
  from contextual counts needs NLP, not a regex; a linter that cries wolf on a correct repo is
  worse than none. Rule stands: reconcile counts by MANUAL grep-sweep on component add/remove.

## Version DOWNGRADE + stale cache version dirs -> plugin intermittently DISABLES (prune the cache) [SUPERSEDED]
- SUPERSEDED: this was a MISDIAGNOSIS. The real recurring cause is the profile-sync
  clobbering `settings.json` -- see "Plugin keeps DISABLING across sessions" at the bottom.
  The cache-prune below is harmless hygiene but did NOT fix the recurrence.
- Context: this session reset the plugin version 1.13.0 -> 1.0.0 -> 1.0.1 ("graduate to v1.0.0").
  `claude plugin update` refreshes the cache but does NOT prune old version dirs, so
  `plugins/cache/simpleharness/simpleharness/` accumulated 12 dirs (1.4.1 .. 1.13.0 + 1.0.0/1.0.1).
- Pitfall: 1.13.0 is semver-HIGHER than the now-current 1.0.1. On `/reload-plugins` (marketplace
  `autoUpdate:true`), Claude Code re-resolves the plugin against the cache; the declared-1.0.1 vs
  stale-1.13.0 inconsistency intermittently flags the plugin DISABLED -- its agents + lsp MCP
  vanish while skills/CLAUDE.md may still load (masking it). `claude plugin enable` + reload fixes it
  transiently but it RECURS every reload. Co-factor: the profile's `plugins` directory was a
  JUNCTION to another profile's (profile cloned from it; shared cache) -- a known path fragility.
  Ruled out: blocklist.json (not listed); dual-config (`.claude.json` has no enabledPlugins; only
  `settings.json` does, and it read true after enable).
- Rule: a version DECREASE is hazardous with this cache. After any downward reset, PRUNE the stale
  higher-version dirs under `plugins/cache/<mkt>/<plugin>/` (keep only the current) so the cache's
  MAX version == the declared version; then reloads stay enabled. Going forward keep versions
  monotonically increasing (1.0.2, 1.0.3, ...). Diagnose a "keeps disabling" plugin via: `claude
  plugin list` (status), `plugins/blocklist.json`, `settings.json` enabledPlugins, and the cache
  version-dir list (`plugins/cache/<mkt>/<plugin>/`).

## Plugin keeps DISABLING across sessions -> a profile-sync clobbers settings.json (real cause; supersedes the cache-prune entry)
- Context: simpleharness kept reverting to DISABLED on every new session, even
  after the cache-prune fix above -- the cache held a SINGLE clean `1.0.1` dir yet its agents +
  MCP were gone again.
- Pitfall: a local launcher script mirrored another Claude Code profile over the harness profile
  on every launch. Plugin enablement lives ONLY in `settings.json` (the `enabledPlugins` map;
  `.claude.json` has no such key), and the mirror did not exclude `settings.json`. The source
  profile never enabled simpleharness, so each sync overwrote the harness profile's
  `settings.json` and wiped the enable -> DISABLED on next launch. robocopy's DEFAULT copies
  differing files regardless of newer/older (needs `/XO` to skip older), so making the target
  copy newer does not help. PROOF: the two settings.json were byte-identical (mirror preserves
  source mtime) and a robocopy `/L` dry-run listed the source copy as a would-copy ("Older").
  The cache-prune entry above only ever "worked" because each session's manual
  `claude plugin enable` held until the next sync.
- Rule: config that must DIFFER per profile (enabledPlugins, model/effort tuning) MUST NOT be
  overwritten by a profile-mirroring sync -- else the shared source silently reverts it every
  launch. Resolution: re-enabled the plugin in the harness profile's `settings.json`
  and removed the mirror step from the launcher entirely (excluding `settings.json` from the
  mirror also works, but full removal kills the whole clobber class). Caveats: a launcher edit
  needs a FRESH shell to take effect (a running shell holds the old in-memory function); the live
  session needs `/reload-plugins`. When a "keeps disabling" plugin recurs despite a clean cache,
  look for a launcher/sync that rewrites `settings.json` BEFORE blaming the cache -- diff the
  profile's settings.json against its sync source.

## Delegation enforcement covers WHETHER-to-delegate, not WHICH-agent -> built-in `Explore` drifts over `simpleharness:explorer`
- Context: the harness has two orthogonal delegation axes. Axis 1 (inline-build vs delegate) is
  reinforced THREE ways: the per-turn UserPromptSubmit reminder line ("delegate by default"), the
  CLAUDE.md classify-then-route rule, and the IntentGate IMPLEMENT->author pointer. Axis 2 (once
  delegating, WHICH agent -- our `simpleharness:*` vs a built-in `Explore`/`Plan`/`general-purpose`)
  has NO per-turn reinforcement. Audited across the profile's whole `projects/`
  transcript set (recursively incl. nested `subagents/agent-*.jsonl`).
- Pitfall: built-in `Explore` was dispatched 50x vs `simpleharness:explorer` 7x profile-wide;
  in the true drift window (after explorer existed) 19 Explore vs 7 explorer
  (~2.7:1); STILL 3 built-in Explore dispatches AFTER the classify-then-route change
  landed. All 50 were read-only recon/map/inventory/audit tasks that explorer fits exactly.
  DECISIVE: in a later session the "Prefer our own agents" rule was verified in-context (protocol
  injected, per-turn reminder fired 10x) and the orchestrator picked built-in `Explore` 3x anyway
  -- so session-start injection of a preference rule does NOT prevent per-turn agent-selection
  drift (exactly parallel to why Axis 1 needed active reinforcement, not just prose). The only
  orchestrator-reaching statement of the rule is ONE buried CLAUDE.md sub-bullet injected once at
  session start (SPEC.md is not context-loaded; the copies in `agents/*.md` govern only those
  agents' own sub-delegation). The built-in agent being literally named `Explore` (= the action
  verb) out-salinces a passive rule. (Nested/subagent Explore hits were OLD sub-orchestrators that
  still held the Agent tool and fanned out to built-in Explore -- a vector now CLOSED by
  `disallowedTools: Agent` on our 4 agents, so remaining drift is MAIN-THREAD.) Verified
  independently of the recon subagent: `rg '"subagent_type":\s*"Explore"'` = 50, `"...:explorer"`
  = 7 over `projects/**/*.jsonl`; `scripts/prompt-hook.ps1` has an IMPLEMENT->author IntentGate
  rule but NO RECON/EXPLORE rule, and the fixed reminder never names our agents.
- Rule: to actually shift agent SELECTION, reinforce Axis 2 the same way Axis 1 was -- mirror the
  proven IMPLEMENT->author pattern with a per-turn RECON/EXPLORE IntentGate pointer naming
  `simpleharness:explorer` (EN + KO triggers) PLUS a fixed-reminder line; passive CLAUDE.md prose
  alone is measurably insufficient. NOT built as of (user chose document-only); tracked
  in ROADMAP. When measuring agent-selection drift, grep BOTH `subagent_type` strings recursively
  (main + nested `subagents/agent-*.jsonl`) and exclude prose mentions (count only real tool_use
  dispatches).
