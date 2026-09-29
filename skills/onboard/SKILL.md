---
name: onboard
description: Use to onboard an existing repo to the harness 3-docs convention — ensure dependencies, recon the codebase (read-only), then GENERATE any missing docs/ARCHITECTURE.md / PROJECT-KNOWLEDGE.md / ROADMAP.md (+ HANDOFF stub + .gitignore) from the code, additively. Reports what the repo is/does and RECOMMENDS (never auto-does) merge/delete for existing docs that overlap the 3-doc roles. Triggers on entering a repo lacking the convention or "set up this repo for the harness / onboard this repo". Not for scaffolding a new project's code.
---

# Onboard a repo to the harness

Bring an existing repo up to the harness "3 Docs + HANDOFF" convention. ADDITIVE
and layout-agnostic: generate missing docs, never restructure code, never clobber
or auto-delete anything. Deterministic dependency install is the
`/simpleharness:environment-setup` command's job; this skill is the generative onboarding
that follows it.

## Steps
1. **Dependencies first** — run the dep doctor: `/simpleharness:environment-setup` (pwsh / gh /
   rg / sg / python / node; installs only what is missing). Skip if already satisfied.
2. **Recon (read-only)** — dispatch `explorer`: languages, entry points, build/test
   commands, directory layout, existing docs/README, notable git history. No edits.
   (Substantial external lookups are `researcher`'s job.)
3. **Detect 3-doc state + overlaps** — check which of `docs/ARCHITECTURE.md`,
   `docs/PROJECT-KNOWLEDGE.md`, `docs/ROADMAP.md`, `HANDOFF.md` exist. Also flag
   existing repo docs whose ROLE overlaps a 3-doc (a README architecture section,
   NOTES/TODO, CHANGELOG, KNOWN_ISSUES, design docs, an existing ROADMAP/BACKLOG).
4. **Generate the MISSING docs from the code (additive)** — write only the ones that
   do not already exist:
   - `docs/ARCHITECTURE.md` — what the system is (components, entry points, data flow).
   - `docs/PROJECT-KNOWLEDGE.md` — seed discoverable pitfalls/quirks as
     context -> pitfall -> rule (may start near-empty).
   - `docs/ROADMAP.md` — a Todo list seeded from code TODOs / open issues (else empty) + an Open questions section.
   - `HANDOFF.md` stub; ensure `.gitignore` ignores `HANDOFF.md` and `ACTIVE-PLAN.md`.
   NEVER overwrite an existing doc — leave it and note it.
5. **Offer before writing** — present the proposed files (each + a one-line summary)
   and get approval before writing. Do NOT auto-commit (commits need a grant).

## Run report
- **Repo explanation** — plain-language summary of what the repo is and does
  (structure + role). Doubles as the user-facing summary and the seed of ARCHITECTURE.md.
- **Generated / skipped** — which 3-docs were created vs already present.
- **Overlap recommendations (recommend, never act)** — for each existing doc that
  duplicates a 3-doc role: one recommendation `{file - overlapping 3-doc -
  suggested action: merge / delete-after-merge / keep + cross-link - why}`. Merges
  and deletes execute ONLY on the user's pick — never auto-delete (you did not
  create those files); destructive actions gate on the user.

## Boundaries
- ADDITIVE only: never move/restructure code or repo layout (the harness is
  layout-agnostic). Never overwrite an existing doc. Never auto-delete/merge —
  recommend; the user decides. Never auto-commit.
- Idempotent: a repo that already has the 3 docs -> no-op (refresh one only on request).
