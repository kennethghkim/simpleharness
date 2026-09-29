# Tests for scripts/prompt-hook.ps1 IntentGate.
#
# Plain pwsh assertions (no Pester). Exit 0 = all pass; exit 1 = one or more
# failures, named. Run: pwsh -NoProfile -File tests/prompt-hook.tests.ps1
#
# Korean prompts are built from code points (Kr helper) so this file stays pure
# ASCII and does not depend on its own on-disk encoding. Stdin is fed as raw
# UTF-8 bytes via the process BaseStream so Korean survives to the hook.

$ErrorActionPreference = 'Stop'

$scriptPath = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\scripts\prompt-hook.ps1'))
if (-not (Test-Path $scriptPath)) { throw "hook not found: $scriptPath" }

# Pointer strings the hook may append (must match the hook verbatim).
$RESUME_PTR = 'Resume detected -> re-read HANDOFF.md + docs/ (handoff skill) before acting.'
$DEBUG_PTR  = 'Error/debug context detected -> use the systematic-debugging skill before proposing fixes.'
$RIGOR_PTR  = 'Rigor keywords detected -> scale ceremony up: crosscheck skill.'
$PLAN_PTR   = 'Planning request detected -> use the blueprint skill.'
$DESIGN_PTR = 'Creative/design request detected -> brainstorming skill first.'

# The fixed baseline reminder (must match the hook verbatim, 7 lines).
$baselineReminder = @(
    'simpleharness operating contract (the full protocol is in your context - re-read it if unsure):',
    '- Orchestrate and delegate by default; the main thread does not implement production work.',
    '- No completion claim without fresh verification evidence; verify subagent output yourself.',
    '- Brainstorm before building features; ask design questions as prose with labeled options.',
    '- Record user grants; gate destructive/external actions that lack a grant.',
    '- Checkpoint to HANDOFF.md before stopping; keep temp in the scratchpad, not the repo tree.',
    '- Before acting, check whether a skill fits the request and invoke it first; skills under-trigger on their own (see the Skills Pointer).'
) -join "`n"

# The exact stdout payload a non-matching prompt must produce (built with the
# same serializer + key order the hook uses).
$expectedBaselineJson = ([ordered]@{
    hookSpecificOutput = [ordered]@{
        hookEventName     = 'UserPromptSubmit'
        additionalContext = $baselineReminder
    }
} | ConvertTo-Json -Compress)

function Kr { param([int[]] $Cp) return [string]::new([char[]] $Cp) }

function New-PromptBytes {
    param([string] $Prompt)
    $json = @{ session_id = 't'; prompt = $Prompt } | ConvertTo-Json -Compress
    return [System.Text.Encoding]::UTF8.GetBytes($json)
}

function Invoke-Hook {
    param([byte[]] $StdinBytes)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName  = 'pwsh'
    $psi.Arguments = "-NoProfile -File `"$scriptPath`""
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $p = [System.Diagnostics.Process]::Start($psi)
    if ($null -ne $StdinBytes -and $StdinBytes.Length -gt 0) {
        $p.StandardInput.BaseStream.Write($StdinBytes, 0, $StdinBytes.Length)
        $p.StandardInput.BaseStream.Flush()
    }
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    return [pscustomobject]@{ StdOut = $out; ExitCode = $p.ExitCode }
}

function Get-Ctx { param([string] $StdOut) return ($StdOut | ConvertFrom-Json).hookSpecificOutput.additionalContext }

$script:failures = @()
$script:total    = 0
function Check {
    param([string] $Name, [bool] $Condition, [string] $Detail = '')
    $script:total++
    if ($Condition) { Write-Host "PASS: $Name" }
    else { Write-Host "FAIL: $Name  $Detail"; $script:failures += $Name }
}

# Korean keyword tokens.
$ereo   = Kr 0xC5D0, 0xB7EC   # DEBUG keyword
$eommil = Kr 0xC5C4, 0xBC00   # RIGOR keyword

# (a) plain prompt -> byte-identical baseline output (no pointer; wording must
# not hit any IntentGate rule, incl. rule 6 IMPLEMENT: implement/refactor/...)
$a    = Invoke-Hook (New-PromptBytes 'hello please summarize this helper function for me')
$aCtx = Get-Ctx $a.StdOut
Check 'a_plain_reminder_byte_identical' ($aCtx -ceq $baselineReminder) 'additionalContext differs from baseline'
Check 'a_plain_rawjson_byte_identical'  (($a.StdOut.TrimEnd("`r", "`n")) -ceq $expectedBaselineJson) 'raw stdout differs from baseline JSON'
Check 'a_plain_exit0'                    ($a.ExitCode -eq 0) "exit=$($a.ExitCode)"

# (b) Korean 에러 -> DEBUG pointer present (proves Korean reaches the script)
$b = Invoke-Hook (New-PromptBytes $ereo)
Check 'b_korean_error_debug_pointer' ((Get-Ctx $b.StdOut).Contains($DEBUG_PTR)) 'DEBUG pointer missing'

# (c) exactly 'continue' -> RESUME pointer
$c = Invoke-Hook (New-PromptBytes 'continue')
Check 'c_continue_resume_pointer' ((Get-Ctx $c.StdOut).Contains($RESUME_PTR)) 'RESUME pointer missing'

# (d) Korean 엄밀 -> RIGOR pointer
$d = Invoke-Hook (New-PromptBytes $eommil)
Check 'd_korean_rigor_pointer' ((Get-Ctx $d.StdOut).Contains($RIGOR_PTR)) 'RIGOR pointer missing'

# (e) matches both DEBUG and PLAN -> only DEBUG (priority + at-most-one)
$e    = Invoke-Hook (New-PromptBytes 'I hit an error: please write a plan to fix it')
$eCtx = Get-Ctx $e.StdOut
Check 'e_debug_wins_present' ($eCtx.Contains($DEBUG_PTR))       'DEBUG pointer missing'
Check 'e_plan_absent'        (-not $eCtx.Contains($PLAN_PTR))   'PLAN pointer must not appear'

# (f) empty stdin -> baseline output, exit 0
$f = Invoke-Hook ([byte[]] @())
Check 'f_empty_baseline' ((Get-Ctx $f.StdOut) -ceq $baselineReminder) 'baseline reminder differs'
Check 'f_empty_exit0'    ($f.ExitCode -eq 0) "exit=$($f.ExitCode)"

# (g) garbage non-JSON stdin -> baseline output, exit 0
$g = Invoke-Hook ([System.Text.Encoding]::UTF8.GetBytes('this is not json at all {{{ <<<'))
Check 'g_garbage_baseline' ((Get-Ctx $g.StdOut) -ceq $baselineReminder) 'baseline reminder differs'
Check 'g_garbage_exit0'    ($g.ExitCode -eq 0) "exit=$($g.ExitCode)"

Write-Host ''
if ($script:failures.Count -eq 0) {
    Write-Host "ALL PASS ($($script:total) checks)"
    exit 0
} else {
    Write-Host "FAILURES ($($script:failures.Count)/$($script:total)): $($script:failures -join ', ')"
    exit 1
}
