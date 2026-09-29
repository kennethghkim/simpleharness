# ARCHITECTURE — simpleharness

What the system is: a lightweight, general-purpose Claude Code harness. It is a
set of static configuration artifacts (no runtime service) that shape how
Claude Code behaves across all projects. Authored in this repo, deployed to a
Claude Code profile directory (`~/.claude/`).

Design source of truth (normative rules every artifact must follow):
`docs/SPEC.md`. This document is its descriptive counterpart — the component
map and deploy reference.

## Components

- **`CLAUDE.md`** (repo root) — the always-on core loop and protocol.
  Everything that must run every session lives here, NOT in skills (skills
  under-trigger for always-on behavior; see PROJECT-KNOWLEDGE.md). Covers:
  operating loop, world-state reconciliation, delegation protocol, verification
  iron law, coding baseline, slop blacklist, grant ledger, communication,
  repo-doc convention, tooling. Deploys to `~/.claude/CLAUDE.md`.

- **`agents/`** — subagent definitions (markdown + YAML frontmatter). Four:
  `author` (implements one scoped task; no re-delegation), `reviewer`
  (read-only verdict: APPROVE / APPROVE-WITH-MINOR-FIXES / REVISE),
  `explorer` (read-only local recon; quick web checks only), `researcher`
  (external research — version-aware docs, OSS internals, GitHub-wide
  examples, issue/PR history; evidence as commit-pinned permalinks; reaches
  two remote MCP servers — context7 / grep_app — registered at
  plugin scope in `.mcp.json` and surfaced as `mcp__plugin_simpleharness_*`).
  Frontmatter defaults for all four: `model: opus`,
  `effort: xhigh` — model overridable per dispatch, effort frontmatter-fixed
  (no per-dispatch override). Deploys to `~/.claude/agents/`.

- **`skills/`** — twelve skills, each `<name>/SKILL.md`:
  `brainstorming`, `handoff`, `crosscheck`,
  `systematic-debugging`, `blueprint`, `execute-plan`,
  `fan-out`, `tdd`, `ast-grep`,
  `insane-search` (vendored web-access fallback engine; routed to when basic
  fetch fails — see the CLAUDE.md Tooling routing rule), `longrun`
  (launch/supervise any minutes-to-hours shell command or background agent),
  `onboard` (bring an existing repo up to the 3-docs convention; additive).
  Skills carry on-demand procedure; the core loop does not depend on them
  auto-triggering. Deploys to `~/.claude/skills/`.

- **`scripts/*.ps1` + `settings/settings-fragment.json` + `hooks/hooks.json`**
  — three Claude Code hooks, all fail-open:
  - `session-start-hook.ps1` (`SessionStart`, plugin mode only) — injects the
    full operating protocol (root CLAUDE.md) into context on startup /
    `/clear` / post-compaction, because plugins cannot ship a CLAUDE.md that
    loads as context. Also best-effort GCs >7-day orphan session temp (scratch-gc.ps1) -- Claude Code never auto-cleans scratchpad.
  - `prompt-hook.ps1` (`UserPromptSubmit`) — injects a lightweight
    operating-contract reminder into every user turn so the core rules stay
    fresh across long sessions / after compaction (drift defense), plus
    IntentGate: reads the prompt from stdin (raw UTF-8) and appends at most
    one skill-pointer line (priority RESUME > DEBUG > RIGOR > PLAN > DESIGN > IMPLEMENT,
    English + Korean keywords, first match wins; fail-open to the bare
    reminder). Never blocks.
  - `stop-hook.ps1` (`Stop`) — a progress-aware plan-execution continuity gate.
    It blocks a stop ONLY when an `ACTIVE-PLAN.md` at the project root (ephemeral,
    gitignored) with unchecked `- [ ]` items and mtime within 7 days is
    *stagnant* — untouched since the previous stop — with a plan-specific reason
    (unchecked count + next item). A per-session state file
    (`<TEMP>/sh-stopgate-<session_id>.json`) tracks the plan mtime and a `nudged`
    flag: the first stop and any stop after the plan was touched (an item checked
    off) reset the streak and allow silently; a stagnant plan blocks exactly once
    per streak. It also allows immediately when `stop_hook_active` is set (loop
    guard), when `status: paused` (first 20 lines), or when a HANDOFF.md was
    checkpointed today AND on/after the plan's mtime. Any other stop (no plan /
    stale / paused / fully-checked) is allowed silently — the generic completion
    nag was removed in 1.0.2; 1.0.3 made the surviving gate progress-aware.
  Plugin mode wires all three via `hooks/hooks.json`
  (`${CLAUDE_PLUGIN_ROOT}` paths). Profile mode wires prompt/stop only:
  scripts deploy to `~/.claude/hooks/`, and the JSON fragment is merged by
  hand into `~/.claude/settings.json` (never auto-merged — too risky).

- **`.claude-plugin/`** — plugin packaging: `plugin.json` (name/version) +
  `marketplace.json` (single-plugin marketplace, `source: "./"`). Makes the
  repo installable on a new environment with two in-session commands
  (`/plugin marketplace add kennethghkim/simpleharness`, then
  `/plugin install simpleharness@simpleharness`) and updatable via
  `/plugin update`. Never combine a plugin install with a profile deploy in
  the same profile (components double up).

- **`commands/environment-setup.md`** — `/simpleharness:environment-setup`, the dependency doctor:
  checks pwsh / gh / ripgrep / ast-grep / python / node, installs only the
  missing ones (winget; brew/apt alternates), fetches the Playwright
  browser, reports a status table. Idempotent.

- **`.mcp.json`** — plugin-scoped MCP servers: two remote research
  endpoints (context7 / grep_app, http) reached by `researcher`,
  plus a bundled Playwright server (stdio, `npx -y @playwright/mcp@latest`)
  for the real-browser verification surface, plus a bundled `lsp` server
  (stdio, `npx -y lsp-mcp-server@1.1.20`) for semantic code navigation over
  Python + TS/JS via `pyright` + `typescript-language-server`
  (`/simpleharness:environment-setup` installs the two servers). Needs Node for
  Playwright and LSP; fails soft without it.

- **`tests/`** — dev-side self-tests, run before any commit:
  `harness-lint.ps1` (10 drift checks: manifest parse, hook script paths,
  version consistency, CLAUDE.md size budget, skills/agents cross-references,
  SKILL.md frontmatter, vendored LICENSE+SOURCE pairing, ASCII-only scripts,
  gitignore) plus behavior suites `prompt-hook.tests.ps1`, `gc.tests.ps1`, and
  `stop-hook.tests.ps1`. Zero session cost — never injected.

- **`docs/`** — this repo's own 3-doc convention (ARCHITECTURE /
  PROJECT-KNOWLEDGE / ROADMAP). `HANDOFF.md` at the repo root is
  ephemeral session state, overwritten each checkpoint.

## Distribution (new environments)

Plugin install, inside Claude Code (private repo OK via existing git/`gh`
credentials): `/plugin marketplace add kennethghkim/simpleharness` →
`/plugin install simpleharness@simpleharness`. Agents, skills, hooks (protocol
injection included), and the plugin-scoped remote MCP endpoints all activate from
the plugin; updates via `/plugin update simpleharness@simpleharness` after
commits are pushed.

## Deploy flow (author's local loop)

`scripts/deploy.ps1` (PowerShell 7): back up existing targets to
`~/.claude/backup-<yyyyMMdd-HHmm>/`, then copy CLAUDE.md, `agents/*`,
`skills/*`, and the two hook scripts into `~/.claude/`. Idempotent.
Only the most recent `backup-*` dir is retained; older ones are pruned each
run.
It does NOT touch `settings.json` — it prints the settings fragment and a
merge-status note (whether settings.json already references the hook).

## Deploy targets

| Repo artifact                 | Deployed to                             |
|-------------------------------|-----------------------------------------|
| `CLAUDE.md`                   | `~/.claude/CLAUDE.md`               |
| `agents/*`                    | `~/.claude/agents/`                 |
| `skills/*`                    | `~/.claude/skills/`                 |
| `scripts/stop-hook.ps1`       | `~/.claude/hooks/stop-hook.ps1`     |
| `scripts/prompt-hook.ps1`     | `~/.claude/hooks/prompt-hook.ps1`   |
| `settings/settings-fragment.json` | merged by hand into `~/.claude/settings.json` |

## Update loop

Edit an artifact here -> run `scripts/deploy.ps1` -> verify the deployed copy
(and, for hook/settings changes, merge the fragment and restart Claude Code).
