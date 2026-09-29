# simpleharness UserPromptSubmit hook
#
# Fires on every user prompt submit, before the model processes it. Injects a
# lightweight operating-contract reminder into the turn's context so the core
# rules stay fresh across long sessions and after compaction (combats drift -
# the main failure mode when CLAUDE.md gets buried deep in context).
#
# IntentGate: the hook also reads the user's prompt from stdin and, using
# priority-ordered keyword rules (first match wins), appends AT MOST ONE
# skill-pointer line to the fixed reminder. Skills under-trigger on their own
# (documented pitfall), so this is a deterministic ~1-line/turn nudge.
#
# Contract (verified against the Claude Code UserPromptSubmit hook docs):
#   - Hook input JSON arrives on stdin. We read it as raw UTF-8 (not via the
#     console codepage) so Korean keywords survive on a CJK-locale console.
#   - To inject context: print JSON with hookSpecificOutput.additionalContext to
#     stdout and exit 0. That string is added to the model's context this turn.
#   - This hook NEVER blocks a prompt (exit 2 would block). It only injects.
#
# Fail-open: empty / malformed / missing stdin or any internal error -> emit
# exactly the baseline reminder (no pointer) and exit 0. Never exit 2.
#
# The Korean keyword literals are written as .NET regex \uXXXX escapes so this
# file stays PURE ASCII (a byte-level ASCII lint runs over scripts/*.ps1). All
# emitted strings are plain ASCII English, so the CJK console mojibake rule does
# not apply to this hook's stdout.

$ErrorActionPreference = 'Stop'

function Get-IntentPointer {
    param([string] $Prompt)

    if ([string]::IsNullOrWhiteSpace($Prompt)) { return '' }
    $trimmed = $Prompt.Trim()

    # 1. RESUME - a bare resume word only (short prompt, exact match).
    #    Korean: ieoseo / gyesok / jaegae
    if ($trimmed.Length -le 20 -and (
            $trimmed -imatch '^(continue|resume|go on)$' -or
            $trimmed -match  '^(\uC774\uC5B4\uC11C|\uACC4\uC18D|\uC7AC\uAC1C)$')) {
        return 'Resume detected -> re-read HANDOFF.md + docs/ (handoff skill) before acting.'
    }

    # 2. DEBUG - error / exception / bug context.
    #    Korean: ereo / oryu / beogeu / andoem / an doem / kkaejyeot / kkaejim
    if ($Prompt -match '(?i)(exception|traceback|stack ?trace|segfault|\berrno\b|error code|\berror\b\s*:)|\uC5D0\uB7EC|\uC624\uB958|\uBC84\uADF8|\uC548\uB428|\uC548 \uB428|\uAE68\uC84C|\uAE68\uC9D0') {
        return 'Error/debug context detected -> use the systematic-debugging skill before proposing fixes.'
    }

    # 3. RIGOR - explicit demand for rigor / thoroughness.
    #    Korean: eommil / cheoljeo / kkomkkom / gipge
    if ($Prompt -match '(?i)\b(rigorous(ly)?|thorough(ly)?|ultrawork|meticulous)\b|\uC5C4\uBC00|\uCCA0\uC800|\uAF3C\uAF3C|\uAE4A\uAC8C') {
        return 'Rigor keywords detected -> scale ceremony up: crosscheck skill.'
    }

    # 4. PLAN - a planning request.
    #    Korean: gyehoek / peullaen
    if ($Prompt -match '(?i)\b(write|make|draft|create)\s+(a\s+|the\s+)?plan\b|\broadmap\b|\uACC4\uD68D|\uD50C\uB79C') {
        return 'Planning request detected -> use the blueprint skill.'
    }

    # 5. DESIGN - a creative / brainstorming request.
    #    Korean: brainstorm / idea
    if ($Prompt -match '(?i)\bbrainstorm(ing)?\b|\bdesign options\b|\uBE0C\uB808\uC778\uC2A4\uD1B0|\uC544\uC774\uB514\uC5B4') {
        return 'Creative/design request detected -> brainstorming skill first.'
    }

    # 6. IMPLEMENT - a production-code implementation request -> delegate to author.
    #    High-precision triggers only (broad add/make/fix/create excluded to avoid
    #    non-code false positives). A bonus proactive pointer for obvious cases; the
    #    CLAUDE.md classify-then-route rule is the phrasing-independent delegation floor.
    #    Korean: guhyeon / gaebal / ripaekteo
    if ($Prompt -match '(?i)\b(implement|refactor|scaffold|rewrite)\b|\uAD6C\uD604|\uAC1C\uBC1C|\uB9AC\uD329\uD130') {
        return 'Code-implementation intent detected -> delegate to an author agent with a 6-section contract; do NOT build production code inline (trivial/config/meta/doc edits exempt).'
    }

    return ''
}

try {
    $reminder = @(
        'simpleharness operating contract (the full protocol is in your context - re-read it if unsure):',
        '- Orchestrate and delegate by default; the main thread does not implement production work.',
        '- No completion claim without fresh verification evidence; verify subagent output yourself.',
        '- Brainstorm before building features; ask design questions as prose with labeled options.',
        '- Record user grants; gate destructive/external actions that lack a grant.',
        '- Checkpoint to HANDOFF.md before stopping; keep temp in the scratchpad, not the repo tree.',
        '- Before acting, check whether a skill fits the request and invoke it first; skills under-trigger on their own (see the Skills Pointer).'
    ) -join "`n"

    # Detect intent from stdin. Any failure here must not suppress the baseline
    # reminder, so it is isolated and falls through to an empty pointer.
    $pointer = ''
    try {
        $reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
        $stdin = $reader.ReadToEnd()
        $reader.Dispose()
        if (-not [string]::IsNullOrWhiteSpace($stdin)) {
            $data = $stdin | ConvertFrom-Json
            $pointer = Get-IntentPointer ([string]$data.prompt)
        }
    }
    catch {
        $pointer = ''
    }

    if ($pointer) {
        $reminder = $reminder + "`n" + $pointer
    }

    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName    = 'UserPromptSubmit'
            additionalContext = $reminder
        }
    }

    Write-Output ($out | ConvertTo-Json -Compress)
    exit 0
}
catch {
    # Fail-open: never disrupt the turn because the hook errored.
    exit 0
}
