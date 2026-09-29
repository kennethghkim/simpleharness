#!/usr/bin/env pwsh
# Tests for scripts/stop-hook.ps1 (progress-aware plan Stop hook; v1.0.3+).
# The ONLY block path is a STAGNANT ACTIVE-PLAN.md: an active plan whose mtime
# has not advanced since the previous stop earns exactly ONE nudge per stagnation
# streak. A fresh session's first stop, a stop right after the plan was touched
# (an item checked off), and every stop after the single nudge all ALLOW. The
# pre-gate hatches (stop_hook_active / no plan / stale / paused / fully-checked /
# HANDOFF-today) all ALLOW as before. Plain pwsh assertions, no Pester.
# Exit 0 = all pass, 1 = any failure.
#
# Each case builds a fresh temp project dir under the OS temp path (NEVER the
# repo) and pipes stdin JSON whose `cwd` points at it. Stateful cases carry a
# UNIQUE session_id and delete their <TEMP>/sh-stopgate-<sid>.json state file in
# setup AND teardown so runs are order-independent and re-runnable. The
# garbage/empty-stdin case carries no cwd, so it drives the child via
# $env:CLAUDE_PROJECT_DIR.

$ErrorActionPreference = 'Stop'

$hookScript = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/stop-hook.ps1'
if (-not (Test-Path -LiteralPath $hookScript)) {
    Write-Output "FAIL: setup -- stop-hook.ps1 not found at $hookScript"
    exit 1
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("stop-hook-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null

$fail = 0
function Ok  ([string]$name) { Write-Output "PASS: $name" }
function Bad ([string]$name, [string]$detail) { $script:fail++; Write-Output "FAIL: $name -- $detail" }

function New-ProjDir ([string]$name) {
    $d = Join-Path $tempRoot $name
    New-Item -ItemType Directory -Path $d -Force | Out-Null
    return $d
}

function Set-Mtime ([string]$path, [datetime]$when) {
    (Get-Item -LiteralPath $path).LastWriteTime = $when
}

# The hook derives its state-file path from the session_id in stdin. Mirror that
# here so cases can seed, inspect, and clear their own state deterministically.
function State-Path  ([string]$sid) { Join-Path $env:TEMP ("sh-stopgate-" + $sid + ".json") }
function Clear-State ([string]$sid) { Remove-Item -LiteralPath (State-Path $sid) -Force -ErrorAction SilentlyContinue }
function Get-State   ([string]$sid) {
    $p = State-Path $sid
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try { return ([System.IO.File]::ReadAllText($p) | ConvertFrom-Json) } catch { return $null }
}

# Every session_id used by the suite -- cleared up front and at teardown.
$sids = @(
    'sess-a', 'sess-first', 'sess-progress', 'sess-stagnant', 'sess-restreak',
    'sess-corrupt', 'sess-otherplan', 'sess-handoff-old'
)
foreach ($s in $sids) { Clear-State $s }

# Run the hook with the given stdin string. When -ProjectDirEnv is supplied,
# set CLAUDE_PROJECT_DIR for the child and restore the parent's value after.
function Invoke-Hook {
    param([string]$StdinJson, [string]$ProjectDirEnv)
    $had  = Test-Path Env:CLAUDE_PROJECT_DIR
    $prev = if ($had) { $env:CLAUDE_PROJECT_DIR } else { $null }
    if ($PSBoundParameters.ContainsKey('ProjectDirEnv')) { $env:CLAUDE_PROJECT_DIR = $ProjectDirEnv }
    elseif ($had) { Remove-Item Env:CLAUDE_PROJECT_DIR }
    try {
        $out  = $StdinJson | & pwsh -NoProfile -ExecutionPolicy Bypass -File $hookScript 2>$null
        $code = $LASTEXITCODE
    } finally {
        if ($had) { $env:CLAUDE_PROJECT_DIR = $prev }
        elseif (Test-Path Env:CLAUDE_PROJECT_DIR) { Remove-Item Env:CLAUDE_PROJECT_DIR }
    }
    return [pscustomobject]@{ ExitCode = $code; StdOut = ($out -join "`n") }
}

function Is-Allow      ([object]$r) { $r.ExitCode -eq 0 -and [string]::IsNullOrWhiteSpace($r.StdOut) }
function Get-Decision  ([object]$r) {
    if ([string]::IsNullOrWhiteSpace($r.StdOut)) { return $null }
    try { return ($r.StdOut | ConvertFrom-Json) } catch { return $null }
}

$json = { param($h) $h | ConvertTo-Json -Compress }

# --- Pre-gate hatches (all ALLOW, unchanged by the progress gate) -----------

# (a) stop_hook_active = true -> allow, even with an active plan present
#     (free pass 1 must dominate before any state is even consulted).
$da = New-ProjDir 'a'
Set-Content -LiteralPath (Join-Path $da 'ACTIVE-PLAN.md') -Value "# Plan`n- [ ] unfinished task" -Encoding utf8
$r = Invoke-Hook (& $json @{ cwd = $da; session_id = 'sess-a'; stop_hook_active = $true; hook_event_name = 'Stop' })
if ((Is-Allow $r) -and ($null -eq (Get-State 'sess-a'))) { Ok 'a: stop_hook_active free-pass allows (no state written) despite active plan' }
else { Bad 'a' "expected allow + no state; code=$($r.ExitCode) out=$($r.StdOut) state=$(Get-State 'sess-a')" }

# (b) no plan + HANDOFF written today -> allow.
$db = New-ProjDir 'b'
Set-Content -LiteralPath (Join-Path $db 'HANDOFF.md') -Value '# HANDOFF' -Encoding utf8
$r = Invoke-Hook (& $json @{ cwd = $db; hook_event_name = 'Stop' })
if (Is-Allow $r) { Ok 'b: no plan + HANDOFF -> allow' }
else { Bad 'b' "expected allow; code=$($r.ExitCode) out=$($r.StdOut)" }

# (c) no plan + no HANDOFF -> allow (no generic completion block).
$dc = New-ProjDir 'c'
$r = Invoke-Hook (& $json @{ cwd = $dc; hook_event_name = 'Stop' })
if (Is-Allow $r) { Ok 'c: no plan + no HANDOFF -> allow (no generic block)' }
else { Bad 'c' "expected allow; code=$($r.ExitCode) out=$($r.StdOut)" }

# (e) plan unchecked + HANDOFF today AND newer than plan -> allow (HANDOFF hatch
#     fires before the state gate; no state written).
$de = New-ProjDir 'e'
Set-Content -LiteralPath (Join-Path $de 'ACTIVE-PLAN.md') -Value "# Plan`n- [ ] still open" -Encoding utf8
Set-Content -LiteralPath (Join-Path $de 'HANDOFF.md') -Value '# HANDOFF' -Encoding utf8
$now = Get-Date
Set-Mtime (Join-Path $de 'ACTIVE-PLAN.md') $now.AddMinutes(-10)
Set-Mtime (Join-Path $de 'HANDOFF.md')     $now
$r = Invoke-Hook (& $json @{ cwd = $de; hook_event_name = 'Stop' })
if (Is-Allow $r) { Ok 'e: plan unchecked + HANDOFF today newer than plan -> allow' }
else { Bad 'e' "expected allow; code=$($r.ExitCode) out=$($r.StdOut)" }

# (f) plan all [x] (0 unchecked) -> allow (no unchecked items).
$df = New-ProjDir 'f'
Set-Content -LiteralPath (Join-Path $df 'ACTIVE-PLAN.md') -Value "# Plan`n- [x] done one`n- [x] done two" -Encoding utf8
$r = Invoke-Hook (& $json @{ cwd = $df; hook_event_name = 'Stop' })
if (Is-Allow $r) { Ok 'f: plan all checked -> allow' }
else { Bad 'f' "expected allow; code=$($r.ExitCode) out=$($r.StdOut)" }

# (g) plan unchecked + status: paused -> allow (plan gate suspended).
$dg = New-ProjDir 'g'
Set-Content -LiteralPath (Join-Path $dg 'ACTIVE-PLAN.md') -Value "# Plan`nstatus: paused`n- [ ] still open" -Encoding utf8
$r = Invoke-Hook (& $json @{ cwd = $dg; hook_event_name = 'Stop' })
if (Is-Allow $r) { Ok 'g: paused plan -> allow (plan gate suspended)' }
else { Bad 'g' "expected allow; code=$($r.ExitCode) out=$($r.StdOut)" }

# (h) plan unchecked + LastWriteTime 8 days ago (stale) -> allow.
$dh = New-ProjDir 'h'
Set-Content -LiteralPath (Join-Path $dh 'ACTIVE-PLAN.md') -Value "# Plan`n- [ ] still open" -Encoding utf8
Set-Mtime (Join-Path $dh 'ACTIVE-PLAN.md') (Get-Date).AddDays(-8)
$r = Invoke-Hook (& $json @{ cwd = $dh; hook_event_name = 'Stop' })
if (Is-Allow $r) { Ok 'h: stale plan (8 days) -> allow' }
else { Bad 'h' "expected allow; code=$($r.ExitCode) out=$($r.StdOut)" }

# (i) empty/garbage stdin -> fail-open allow (exit 0, no block). No cwd in the
#     input, so drive the child via CLAUDE_PROJECT_DIR pointed at a dir with a
#     fresh HANDOFF; a parse failure must not crash or emit a spurious block.
$di = New-ProjDir 'i'
Set-Content -LiteralPath (Join-Path $di 'HANDOFF.md') -Value '# HANDOFF' -Encoding utf8
$rG = Invoke-Hook -StdinJson 'not-valid-json{{{' -ProjectDirEnv $di
$rE = Invoke-Hook -StdinJson ''                  -ProjectDirEnv $di
if ((Is-Allow $rG) -and (Is-Allow $rE)) { Ok 'i: garbage/empty stdin -> fail-open allow' }
else { Bad 'i' "expected allow for both; garbage code=$($rG.ExitCode) out=$($rG.StdOut); empty code=$($rE.ExitCode) out=$($rE.StdOut)" }

# --- Progress-aware state gate ----------------------------------------------

# (j) first stop, active plan, no state file -> ALLOW; state file created with
#     nudged=false and the current plan path + unchecked count. (This is the
#     free pass that replaces the old "active plan -> immediate block".)
$dj = New-ProjDir 'j'
$planJ = Join-Path $dj 'ACTIVE-PLAN.md'
Set-Content -LiteralPath $planJ -Value "# Plan`n- [ ] first task`n- [ ] second task" -Encoding utf8
$r = Invoke-Hook (& $json @{ cwd = $dj; session_id = 'sess-first'; hook_event_name = 'Stop' })
$st = Get-State 'sess-first'
if ((Is-Allow $r) -and $st -and ($st.planPath -eq $planJ) -and (-not $st.nudged) -and ($st.unchecked -eq 2)) {
    Ok 'j: first stop w/ active plan -> allow + state written (nudged=false, unchecked=2)'
} else { Bad 'j' "expected allow + fresh state; allow=$(Is-Allow $r) out=$($r.StdOut) state=$($st | ConvertTo-Json -Compress)" }

# (k) second stop after the plan mtime ADVANCED (item checked off) -> ALLOW,
#     state refreshed with strictly-increased ticks and nudged still false.
$dk = New-ProjDir 'k'
$planK = Join-Path $dk 'ACTIVE-PLAN.md'
Set-Content -LiteralPath $planK -Value "# Plan`n- [ ] a`n- [ ] b" -Encoding utf8
Set-Mtime $planK ((Get-Date).AddMinutes(-5))
$r1 = Invoke-Hook (& $json @{ cwd = $dk; session_id = 'sess-progress'; hook_event_name = 'Stop' })
$stBefore = Get-State 'sess-progress'
# Simulate checking an item off: rewrite the plan and push its mtime forward.
Set-Content -LiteralPath $planK -Value "# Plan`n- [x] a`n- [ ] b" -Encoding utf8
Set-Mtime $planK (Get-Date)
$r2 = Invoke-Hook (& $json @{ cwd = $dk; session_id = 'sess-progress'; hook_event_name = 'Stop' })
$stAfter = Get-State 'sess-progress'
if ((Is-Allow $r1) -and (Is-Allow $r2) -and $stBefore -and $stAfter -and
    ([long]$stAfter.mtimeTicks -gt [long]$stBefore.mtimeTicks) -and (-not $stAfter.nudged) -and ($stAfter.unchecked -eq 1)) {
    Ok 'k: plan mtime advanced between stops -> allow + state refreshed (ticks up, nudged=false)'
} else { Bad 'k' "expected both allow + advanced state; a1=$(Is-Allow $r1) a2=$(Is-Allow $r2) before=$($stBefore | ConvertTo-Json -Compress) after=$($stAfter | ConvertTo-Json -Compress)" }

# (l) stagnation streak: first stop allows, second stop (plan UNCHANGED) BLOCKS
#     once naming the count + first item and flips nudged=true, third stop
#     (still unchanged) ALLOWS silently (one nudge per streak).
$dl = New-ProjDir 'l'
$planL = Join-Path $dl 'ACTIVE-PLAN.md'
$firstItemL = 'Wire the ACTIVE-PLAN convention into skills'
Set-Content -LiteralPath $planL -Value "# Plan`n`n- [ ] $firstItemL`n- [ ] second unchecked item`n- [x] a finished item" -Encoding utf8
Set-Mtime $planL (Get-Date)
$r1 = Invoke-Hook (& $json @{ cwd = $dl; session_id = 'sess-stagnant'; hook_event_name = 'Stop' })   # free pass
$r2 = Invoke-Hook (& $json @{ cwd = $dl; session_id = 'sess-stagnant'; hook_event_name = 'Stop' })   # nudge
$d2 = Get-Decision $r2
$stAfterNudge = Get-State 'sess-stagnant'
$r3 = Invoke-Hook (& $json @{ cwd = $dl; session_id = 'sess-stagnant'; hook_event_name = 'Stop' })   # suppressed
if ((Is-Allow $r1) -and $d2 -and ($d2.decision -eq 'block') -and ($d2.reason -match 'has 2 unchecked item\(s\)') -and
    $d2.reason.Contains($firstItemL) -and $stAfterNudge -and $stAfterNudge.nudged -and (Is-Allow $r3)) {
    Ok 'l: stagnant plan -> stop1 allow, stop2 block (count+item, nudged=true), stop3 allow (suppressed)'
} else { Bad 'l' "seq mismatch; a1=$(Is-Allow $r1) block2=$($r2.StdOut) nudged=$($stAfterNudge.nudged) a3=$(Is-Allow $r3)" }

# (m) progress AFTER a nudge resets the streak: block, then advance the plan
#     mtime -> allow (nudged reset false), then a further stagnant stop -> BLOCK
#     again (a brand-new streak earns its own single nudge).
$dm = New-ProjDir 'm'
$planM = Join-Path $dm 'ACTIVE-PLAN.md'
Set-Content -LiteralPath $planM -Value "# Plan`n- [ ] x`n- [ ] y" -Encoding utf8
Set-Mtime $planM ((Get-Date).AddMinutes(-3))
$r1 = Invoke-Hook (& $json @{ cwd = $dm; session_id = 'sess-restreak'; hook_event_name = 'Stop' })   # free pass
$r2 = Invoke-Hook (& $json @{ cwd = $dm; session_id = 'sess-restreak'; hook_event_name = 'Stop' })   # nudge #1
$d2 = Get-Decision $r2
Set-Content -LiteralPath $planM -Value "# Plan`n- [x] x`n- [ ] y" -Encoding utf8                     # progress
Set-Mtime $planM (Get-Date)
$r3 = Invoke-Hook (& $json @{ cwd = $dm; session_id = 'sess-restreak'; hook_event_name = 'Stop' })   # allow (reset)
$stReset = Get-State 'sess-restreak'
$r4 = Invoke-Hook (& $json @{ cwd = $dm; session_id = 'sess-restreak'; hook_event_name = 'Stop' })   # nudge #2
$d4 = Get-Decision $r4
if ((Is-Allow $r1) -and $d2 -and ($d2.decision -eq 'block') -and (Is-Allow $r3) -and
    $stReset -and (-not $stReset.nudged) -and $d4 -and ($d4.decision -eq 'block')) {
    Ok 'm: nudge -> progress resets streak (allow, nudged=false) -> next stagnant stop blocks again'
} else { Bad 'm' "seq mismatch; a1=$(Is-Allow $r1) b2=$($d2.decision) a3=$(Is-Allow $r3) resetNudged=$($stReset.nudged) b4=$($d4.decision)" }

# (n) corrupt state file JSON -> treated as no state: ALLOW and the state file is
#     rewritten to a valid object (nudged=false, correct planPath).
$dn = New-ProjDir 'n'
$planN = Join-Path $dn 'ACTIVE-PLAN.md'
Set-Content -LiteralPath $planN -Value "# Plan`n- [ ] only task" -Encoding utf8
Set-Mtime $planN (Get-Date)
[System.IO.File]::WriteAllText((State-Path 'sess-corrupt'), 'not-json{{{ broken')
$r = Invoke-Hook (& $json @{ cwd = $dn; session_id = 'sess-corrupt'; hook_event_name = 'Stop' })
$st = Get-State 'sess-corrupt'
if ((Is-Allow $r) -and $st -and ($st.planPath -eq $planN) -and (-not $st.nudged)) {
    Ok 'n: corrupt state file -> no-state (allow + state rewritten valid, nudged=false)'
} else { Bad 'n' "expected allow + rewritten state; allow=$(Is-Allow $r) out=$($r.StdOut) state=$($st | ConvertTo-Json -Compress)" }

# (o) state file whose planPath differs from the current plan -> treated as no
#     state: even a nudged=true stale-path record does not block; ALLOW and the
#     state is rewritten for the current plan (nudged=false).
$do = New-ProjDir 'o'
$planO = Join-Path $do 'ACTIVE-PLAN.md'
Set-Content -LiteralPath $planO -Value "# Plan`n- [ ] real task" -Encoding utf8
Set-Mtime $planO (Get-Date)
$staleObj = [ordered]@{ planPath = 'C:\some\other\ACTIVE-PLAN.md'; mtimeTicks = 1; unchecked = 9; nudged = $true }
[System.IO.File]::WriteAllText((State-Path 'sess-otherplan'), ($staleObj | ConvertTo-Json -Compress))
$r = Invoke-Hook (& $json @{ cwd = $do; session_id = 'sess-otherplan'; hook_event_name = 'Stop' })
$st = Get-State 'sess-otherplan'
if ((Is-Allow $r) -and $st -and ($st.planPath -eq $planO) -and (-not $st.nudged)) {
    Ok 'o: state planPath mismatch -> no-state (allow + state rebound to current plan, nudged=false)'
} else { Bad 'o' "expected allow + rebound state; allow=$(Is-Allow $r) out=$($r.StdOut) state=$($st | ConvertTo-Json -Compress)" }

# (p) HANDOFF today but OLDER than the plan does NOT take the HANDOFF hatch: it
#     falls through to the state gate, so a first stop allows (state written) and
#     the next stagnant stop blocks -- proving the HANDOFF >= plan ordering gate.
$dp = New-ProjDir 'p'
$planP = Join-Path $dp 'ACTIVE-PLAN.md'
Set-Content -LiteralPath $planP -Value "# Plan`n- [ ] still open" -Encoding utf8
Set-Content -LiteralPath (Join-Path $dp 'HANDOFF.md') -Value '# HANDOFF' -Encoding utf8
$now = Get-Date
Set-Mtime (Join-Path $dp 'HANDOFF.md') $now.AddMinutes(-10)
Set-Mtime $planP $now
$r1 = Invoke-Hook (& $json @{ cwd = $dp; session_id = 'sess-handoff-old'; hook_event_name = 'Stop' })  # free pass (not hatched by HANDOFF)
$stP = Get-State 'sess-handoff-old'
$r2 = Invoke-Hook (& $json @{ cwd = $dp; session_id = 'sess-handoff-old'; hook_event_name = 'Stop' })  # nudge
$d2 = Get-Decision $r2
if ((Is-Allow $r1) -and $stP -and ($stP.planPath -eq $planP) -and
    $d2 -and ($d2.decision -eq 'block') -and ($d2.reason -match 'ACTIVE-PLAN\.md has')) {
    Ok 'p: HANDOFF older than plan bypasses HANDOFF hatch -> free pass then stagnation block'
} else { Bad 'p' "expected allow(state) then block; a1=$(Is-Allow $r1) state=$($stP | ConvertTo-Json -Compress) b2=$($r2.StdOut)" }

# Teardown: clear state files (both here and in setup so runs are re-runnable)
# and remove temp dirs (never inside the repo).
foreach ($s in $sids) { Clear-State $s }
Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue

if ($fail -eq 0) { Write-Output 'ALL PASS'; exit 0 }
Write-Output "FAILURES: $fail"
exit 1
