# simpleharness Stop hook
#
# Fires when the main agent tries to stop. The hook blocks ONLY to keep an
# in-progress plan executing, and only when that plan is STAGNANT -- normal
# step-by-step execution (checking an item off between stops) passes quietly.
# A no-work / answer-only / read-only session always stops cleanly.
#
# Allow paths, evaluated in order (each short-circuits):
#   1. stop_hook_active == true  -> we already nudged once this stop cycle;
#      blocking again would loop forever. Allow the stop.
#   2. No ACTIVE-PLAN.md at the project root -> allow.
#   3. Plan mtime older than 7 days (stale) -> allow.
#   4. "status: paused" in the plan's first 20 lines -> allow.
#   5. Zero unchecked "- [ ]" items -> allow.
#   6. HANDOFF.md written today AND on/after the plan's mtime (a checkpoint
#      taken after the latest plan activity legitimizes the stop) -> allow.
#   7. Progress-aware stateful gate (below).
#
# Progress-aware gate: when an active plan reaches the gate, a per-session
# state file records the plan's mtime and whether we already nudged this
# stagnation streak. The gate:
#   - first stop of a session (no state)      -> record + ALLOW (one free pass);
#   - plan mtime advanced since the last stop -> progress; reset + ALLOW;
#   - plan unchanged, already nudged          -> ALLOW (one nudge per streak);
#   - plan unchanged, not yet nudged          -> BLOCK once, mark nudged.
# So checking an item off (which touches the plan) always earns a quiet next
# stop; only two consecutive stops on an untouched active plan earn a nudge.
#
# State file: <TEMP>/sh-stopgate-<KEY>.json where KEY is the hook's session_id
# (or the lowercase hex MD5 of the project dir when no session_id is present).
# Fields: planPath, mtimeTicks, unchecked, nudged. Any state IO error is treated
# as "no state" and never flips an allow into a block or vice versa.
#
# (v1.0.2 removed the generic "Incomplete tasks remain" completion nag and its
# standalone HANDOFF-today free pass; v1.0.3 made the surviving plan gate
# progress-aware. The plan gate is still the only block.)
#
# Contract (verified against the Claude Code Stop hook documentation,
# code.claude.com/docs/en/hooks):
#   - Hook input JSON arrives on stdin (fields: cwd, session_id,
#     transcript_path, stop_hook_active, hook_event_name, ...).
#   - To block the stop: print {"decision":"block","reason":"..."} to stdout
#     and exit 0. "reason" is fed back to Claude. "systemMessage" is shown to
#     the user only.
#   - To allow the stop: exit 0 with no JSON on stdout.
#   - Stop hooks ignore any "matcher" field.
#
# Fail-open: any error here must NOT trap the user in a session. On any
# exception we allow the stop (exit 0, no output).
#
# Output is pure ASCII JSON, so the CJK-locale console mojibake rule
# (PROJECT-KNOWLEDGE.md) does not apply to this hook's stdout.

$ErrorActionPreference = 'Stop'

# Persist the progress-gate state as a tiny flat JSON object. Wrapped in its
# own try/catch: a write failure must never change the stop decision.
function Save-StopGateState {
    param(
        [string]$Path,
        [string]$PlanPath,
        [long]$MtimeTicks,
        [int]$Unchecked,
        [bool]$Nudged
    )
    try {
        $obj = [ordered]@{
            planPath   = $PlanPath
            mtimeTicks = $MtimeTicks
            unchecked  = $Unchecked
            nudged     = $Nudged
        }
        [System.IO.File]::WriteAllText($Path, ($obj | ConvertTo-Json -Compress))
    }
    catch {
        # Swallow: state IO is best-effort and must not affect the decision.
    }
}

try {
    $raw = [Console]::In.ReadToEnd()

    $inputObj = $null
    if (-not [string]::IsNullOrWhiteSpace($raw)) {
        try { $inputObj = $raw | ConvertFrom-Json } catch { $inputObj = $null }
    }

    # Allow path 1: already nudged once this stop cycle -> avoid an infinite
    # block/continue loop.
    if ($inputObj -and $inputObj.stop_hook_active) {
        exit 0
    }

    # Locate the project root. Prefer the hook input's cwd; fall back to the
    # env var Claude Code exports, then the actual process cwd.
    $projectDir = $null
    if ($inputObj -and $inputObj.cwd) { $projectDir = [string]$inputObj.cwd }
    if ([string]::IsNullOrWhiteSpace($projectDir)) { $projectDir = $env:CLAUDE_PROJECT_DIR }
    if ([string]::IsNullOrWhiteSpace($projectDir)) { $projectDir = (Get-Location).Path }

    # Plan-aware gate ("boulder-lite"): an ACTIVE-PLAN.md at the project root
    # with unchecked checklist items keeps the session executing. The plan is
    # ephemeral (gitignored). It gates only while recent (touched within 7 days)
    # and not deliberately paused ("status: paused" in the first 20 lines). A
    # HANDOFF.md checkpoint taken after the latest plan activity legitimizes a
    # stop. Once the plan is confirmed active, the progress-aware state gate
    # decides between a silent allow and a single stagnation nudge. When the plan
    # is absent/stale/paused or has no unchecked items, the stop is allowed.
    $planPath = Join-Path $projectDir 'ACTIVE-PLAN.md'
    if (Test-Path -LiteralPath $planPath -PathType Leaf) {
        $planItem  = Get-Item -LiteralPath $planPath
        $planMtime = $planItem.LastWriteTime
        if ($planMtime -ge (Get-Date).AddDays(-7)) {
            $planText = [string](Get-Content -LiteralPath $planPath -Raw)

            $paused = $false
            foreach ($line in (($planText -split "`n") | Select-Object -First 20)) {
                if ($line -match '(?i)^\s*status:\s*paused\b') { $paused = $true; break }
            }

            if (-not $paused) {
                $unchecked = [regex]::Matches($planText, '(?m)^[ \t]*-[ \t]+\[ \][ \t]*(.*)$')
                if ($unchecked.Count -ge 1) {
                    # Plan is active. Allow immediately if HANDOFF.md was
                    # checkpointed today AND on/after the latest plan edit.
                    $planHandoff = Join-Path $projectDir 'HANDOFF.md'
                    if (Test-Path -LiteralPath $planHandoff -PathType Leaf) {
                        $hmtime = (Get-Item -LiteralPath $planHandoff).LastWriteTime
                        if ($hmtime.Date -eq (Get-Date).Date -and $hmtime -ge $planMtime) {
                            exit 0
                        }
                    }

                    # Progress-aware gate. Key the state per session (session_id
                    # when present; else the lowercase hex MD5 of the project
                    # dir, so a session without an id still shares one file).
                    $sessionId = $null
                    if ($inputObj -and $inputObj.session_id) { $sessionId = [string]$inputObj.session_id }
                    if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
                        $key = $sessionId
                    }
                    else {
                        $md5 = [System.Security.Cryptography.MD5]::Create()
                        try { $hashBytes = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes([string]$projectDir)) }
                        finally { $md5.Dispose() }
                        $key = ([System.BitConverter]::ToString($hashBytes) -replace '-', '').ToLower()
                    }
                    $stateFile = Join-Path $env:TEMP ("sh-stopgate-" + $key + ".json")
                    $mTicks    = [long]$planMtime.Ticks

                    # Read prior state. Any read/parse error, or a state whose
                    # planPath no longer matches, is treated as no state.
                    $state = $null
                    try {
                        if (Test-Path -LiteralPath $stateFile -PathType Leaf) {
                            $stateRaw = [System.IO.File]::ReadAllText($stateFile)
                            if (-not [string]::IsNullOrWhiteSpace($stateRaw)) {
                                $parsed = $stateRaw | ConvertFrom-Json
                                if ($parsed -and ([string]$parsed.planPath -eq [string]$planPath)) {
                                    $state = $parsed
                                }
                            }
                        }
                    }
                    catch { $state = $null }

                    if ($null -eq $state) {
                        # First stop for this plan/session -> record + allow.
                        Save-StopGateState -Path $stateFile -PlanPath $planPath -MtimeTicks $mTicks -Unchecked $unchecked.Count -Nudged $false
                        exit 0
                    }

                    if ($mTicks -gt [long]$state.mtimeTicks) {
                        # Plan touched since the last stop = progress -> reset
                        # the streak and allow.
                        Save-StopGateState -Path $stateFile -PlanPath $planPath -MtimeTicks $mTicks -Unchecked $unchecked.Count -Nudged $false
                        exit 0
                    }

                    if ($state.nudged) {
                        # Already nudged this stagnation streak -> allow silently.
                        exit 0
                    }

                    # Stagnant plan, not yet nudged this streak -> block once and
                    # mark nudged (keep the recorded mtime/unchecked as-is).
                    $next = $unchecked[0].Groups[1].Value.Trim()
                    if ($next.Length -gt 120) { $next = $next.Substring(0, 120) }
                    $reason = "ACTIVE-PLAN.md has $($unchecked.Count) unchecked item(s) (next: $next). " +
                              'Continue executing the plan, or checkpoint via handoff ' +
                              '(update HANDOFF.md) if pausing is deliberate.'

                    $out = [ordered]@{
                        decision      = 'block'
                        reason        = $reason
                        systemMessage = 'simpleharness: ACTIVE-PLAN.md has unchecked items.'
                    }

                    Save-StopGateState -Path $stateFile -PlanPath $planPath -MtimeTicks ([long]$state.mtimeTicks) -Unchecked ([int]$state.unchecked) -Nudged $true
                    Write-Output ($out | ConvertTo-Json -Compress)
                    exit 0
                }
            }
        }
    }

    # No plan gate tripped -> allow the stop (no output).
    exit 0
}
catch {
    # Fail-open: never block the user because the hook itself errored.
    exit 0
}
