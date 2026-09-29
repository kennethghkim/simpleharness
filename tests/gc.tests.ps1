# Tests for scripts/scratch-gc.ps1 -- Invoke-ScratchGC (orphan session-temp GC).
#
# Plain pwsh assertions (no Pester). Exit 0 = all pass; exit 1 = named failures.
# Run: pwsh -NoProfile -File tests/gc.tests.ps1
#
# Proves the safety invariant: only scratchpad/tasks/tool-results dirs older than
# the age cutoff are deleted; recent (current/active-session) dirs and non-target
# names survive; the GC is scope-locked to <Root>/<project>/<session>/<target>.

$ErrorActionPreference = 'Stop'

$gcScript = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\scratch-gc.ps1'))
if (-not (Test-Path $gcScript)) { Write-Host "FAIL: scratch-gc.ps1 not found: $gcScript"; exit 1 }
. $gcScript

$script:failures = @(); $script:total = 0
function Check {
    param([string]$Name, [bool]$Cond, [string]$Detail = '')
    $script:total++
    if ($Cond) { Write-Host "PASS: $Name" } else { Write-Host "FAIL: $Name  $Detail"; $script:failures += $Name }
}

# --- sandbox (isolated from the real Temp/claude) ---
$sb = Join-Path $env:TEMP ('gctest_' + [guid]::NewGuid().ToString('N'))
function New-Aged {
    param([string]$Dir, [int]$AgeDays)
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $Dir 'f.txt') -Value 'x'
    (Get-Item -LiteralPath $Dir).LastWriteTime = (Get-Date).AddDays(-$AgeDays)
}

$old   = Join-Path $sb 'projA\sessOld'
$new   = Join-Path $sb 'projA\sessNew'
$projB = Join-Path $sb 'projB\sessOld'
New-Aged (Join-Path $old   'scratchpad')   8   # old target  -> delete
New-Aged (Join-Path $old   'tasks')        8   # old target  -> delete
New-Aged (Join-Path $old   'tool-results') 8   # old target  -> delete
New-Aged (Join-Path $old   'keep-me')      8   # non-target  -> survive (scope)
New-Aged (Join-Path $new   'scratchpad')   0   # recent      -> survive (age)
New-Aged (Join-Path $projB 'scratchpad')   8   # other proj  -> delete

Invoke-ScratchGC -Root $sb -Days 7

Check 'old_scratchpad_deleted'    (-not (Test-Path -LiteralPath (Join-Path $old   'scratchpad')))
Check 'old_tasks_deleted'         (-not (Test-Path -LiteralPath (Join-Path $old   'tasks')))
Check 'old_toolresults_deleted'   (-not (Test-Path -LiteralPath (Join-Path $old   'tool-results')))
Check 'otherproject_old_deleted'  (-not (Test-Path -LiteralPath (Join-Path $projB 'scratchpad')))
Check 'recent_scratchpad_kept'    (Test-Path -LiteralPath (Join-Path $new 'scratchpad')) 'recent (age<cutoff) must survive'
Check 'nontarget_name_kept'       (Test-Path -LiteralPath (Join-Path $old 'keep-me')) 'non-target dir name must survive'

Remove-Item -LiteralPath $sb -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:failures.Count -eq 0) { Write-Host "ALL PASS ($($script:total) checks)"; exit 0 }
else { Write-Host "FAILURES ($($script:failures.Count)/$($script:total)): $($script:failures -join ', ')"; exit 1 }
