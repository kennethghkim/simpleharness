# simpleharness harness-lint: dev-side self-test for doc/config drift.
#
# Zero external dependencies (no Pester). Run from anywhere:
#   pwsh -NoProfile -File tests/harness-lint.ps1
# Exit 0 = every check passed (WARN alone still passes); exit 1 = >=1 FAIL.
# Emits one labeled result line per check; a failing check lists every
# offending item beneath it. Output is kept pure ASCII so the CJK-locale
# console cannot mojibake it.

$ErrorActionPreference = 'Stop'

# Repo root is the parent of the tests/ dir that holds this script, so the
# lint is CWD-independent.
$RepoRoot = Split-Path -Parent $PSScriptRoot

$script:Failed = $false

function Emit {
    param(
        [string]$Name,
        [string]$PassMessage,
        [string[]]$Failures = @(),
        [string[]]$Warnings = @()
    )
    if ($Failures.Count -gt 0) {
        Write-Output ("[FAIL] {0}: {1} failing item(s)" -f $Name, $Failures.Count)
        foreach ($f in $Failures) { Write-Output ("  - {0}" -f $f) }
        $script:Failed = $true
    }
    elseif ($Warnings.Count -gt 0) {
        Write-Output ("[WARN] {0}: {1}" -f $Name, ($Warnings -join '; '))
    }
    else {
        Write-Output ("[PASS] {0}: {1}" -f $Name, $PassMessage)
    }
}

# Extracts the YAML frontmatter body (text between the leading --- fences).
function Get-Frontmatter {
    param([string]$Raw)
    $m = [regex]::Match($Raw, '(?s)\A---\r?\n(.*?)\r?\n---')
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# --- Check 1: JSON manifests parse -----------------------------------------
$fail = @()
$jsonManifests = @(
    '.claude-plugin/plugin.json',
    '.claude-plugin/marketplace.json',
    'hooks/hooks.json',
    'settings/settings-fragment.json',
    '.mcp.json'
)
foreach ($rel in $jsonManifests) {
    $p = Join-Path $RepoRoot $rel
    if (-not (Test-Path -LiteralPath $p)) { $fail += "$rel (missing)"; continue }
    try { Get-Content -LiteralPath $p -Raw | ConvertFrom-Json -ErrorAction Stop | Out-Null }
    catch { $fail += ("{0} (parse error: {1})" -f $rel, $_.Exception.Message) }
}
Emit 'json' 'all 5 manifests parse' $fail

# --- Check 2: hook script paths exist --------------------------------------
$fail = @()
$hooksPath = Join-Path $RepoRoot 'hooks/hooks.json'
if (-not (Test-Path -LiteralPath $hooksPath)) {
    $fail += 'hooks/hooks.json (missing)'
}
else {
    $raw = Get-Content -LiteralPath $hooksPath -Raw
    $seen = @{}
    foreach ($m in [regex]::Matches($raw, '\$\{CLAUDE_PLUGIN_ROOT\}/([^"''\s]+)')) {
        $rel = $m.Groups[1].Value
        if ($seen.ContainsKey($rel)) { continue }
        $seen[$rel] = $true
        if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $rel))) { $fail += "$rel (missing)" }
    }
}
Emit 'hooks' 'all referenced script paths exist' $fail

# --- Check 3: plugin version appears in README -----------------------------
$fail = @()
$version = $null
$pluginPath = Join-Path $RepoRoot '.claude-plugin/plugin.json'
$readmePath = Join-Path $RepoRoot 'README.md'
if (-not (Test-Path -LiteralPath $pluginPath)) { $fail += '.claude-plugin/plugin.json (missing)' }
elseif (-not (Test-Path -LiteralPath $readmePath)) { $fail += 'README.md (missing)' }
else {
    $version = (Get-Content -LiteralPath $pluginPath -Raw | ConvertFrom-Json).version
    $readme = Get-Content -LiteralPath $readmePath -Raw
    if ([string]::IsNullOrWhiteSpace($version)) { $fail += 'plugin.json has no version field' }
    elseif ($readme -notmatch [regex]::Escape($version)) { $fail += "version '$version' not found in README.md" }
}
Emit 'version' ("plugin.json version {0} present in README.md" -f $version) $fail

# --- Check 4: CLAUDE.md size (Anthropic official target: under 200 lines) ---
# CLAUDE.md is injected at every session start, so keep it lean. Anthropic's
# official guidance is a LINE target ("target under 200 lines"; longer files
# consume more context and reduce adherence) with NO byte cap -- CLAUDE.md loads
# in full. We gate on lines only; the former ~13 KB byte budget had no official
# analog and was dropped.
$fail = @()
$lines = 0
$claudePath = Join-Path $RepoRoot 'CLAUDE.md'
if (-not (Test-Path -LiteralPath $claudePath)) {
    $fail += 'CLAUDE.md (missing)'
}
else {
    $lines = (Get-Content -LiteralPath $claudePath).Count
    if ($lines -gt 200) { $fail += "$lines lines (limit 200; Anthropic official target)" }
}
Emit 'claudemd' ("{0} lines (within the 200-line target)" -f $lines) $fail

# --- Check 5: Skills Pointer <-> skills/ cross-check (both directions) ------
$fail = @()
$bulletNames = @()
$skillDirs = @()
if (-not (Test-Path -LiteralPath $claudePath)) {
    $fail += 'CLAUDE.md (missing)'
}
else {
    $claudeText = Get-Content -LiteralPath $claudePath -Raw
    $section = [regex]::Match($claudeText, '(?ms)^##\s+Skills Pointer\s*$(.*?)(?=^##\s|\z)')
    if (-not $section.Success) {
        $fail += 'CLAUDE.md has no "## Skills Pointer" section'
    }
    else {
        $bulletNames = [regex]::Matches($section.Groups[1].Value, '(?m)^-\s+\*\*([^*]+)\*\*') |
            ForEach-Object { $_.Groups[1].Value.Trim() }
        # Direction 1: every pointer bullet maps to a skill dir with a SKILL.md.
        foreach ($n in $bulletNames) {
            if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot ("skills/{0}/SKILL.md" -f $n)))) {
                $fail += "Skills Pointer bullet '$n' has no skills/$n/SKILL.md"
            }
        }
    }
    # Direction 2: every skill dir is named somewhere in CLAUDE.md.
    if (Test-Path -LiteralPath (Join-Path $RepoRoot 'skills')) {
        $skillDirs = Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'skills') -Directory | Select-Object -ExpandProperty Name
        foreach ($d in $skillDirs) {
            if ($claudeText -notmatch [regex]::Escape($d)) { $fail += "skills/$d not named in CLAUDE.md" }
        }
    }
}
Emit 'skills-xref' ("{0} pointer bullets and {1} skill dirs reconcile" -f $bulletNames.Count, $skillDirs.Count) $fail

# --- Check 6: SKILL.md frontmatter (name/description, name == dir) ----------
$fail = @()
$skillsRoot = Join-Path $RepoRoot 'skills'
if (Test-Path -LiteralPath $skillsRoot) {
    foreach ($dir in (Get-ChildItem -LiteralPath $skillsRoot -Directory)) {
        $md = Join-Path $dir.FullName 'SKILL.md'
        if (-not (Test-Path -LiteralPath $md)) { $fail += "skills/$($dir.Name) missing SKILL.md"; continue }
        $body = Get-Frontmatter (Get-Content -LiteralPath $md -Raw)
        if ($null -eq $body) { $fail += "skills/$($dir.Name)/SKILL.md missing YAML frontmatter"; continue }
        $nameMatch = [regex]::Match($body, '(?m)^name:\s*(.+?)\s*$')
        if (-not [regex]::IsMatch($body, '(?m)^description:')) { $fail += "skills/$($dir.Name)/SKILL.md frontmatter missing description:" }
        if (-not $nameMatch.Success) {
            $fail += "skills/$($dir.Name)/SKILL.md frontmatter missing name:"
        }
        else {
            $nameVal = $nameMatch.Groups[1].Value.Trim().Trim('"').Trim("'")
            if ($nameVal -ne $dir.Name) { $fail += "skills/$($dir.Name)/SKILL.md name '$nameVal' != dir name" }
        }
    }
}
else { $fail += 'skills/ (missing)' }
Emit 'skill-frontmatter' 'every SKILL.md has name/description and name matches dir' $fail

# --- Check 7: agents present with unified model/effort routing --------------
$fail = @()
$agentsRoot = Join-Path $RepoRoot 'agents'
foreach ($a in @('author', 'explorer', 'reviewer', 'researcher')) {
    if (-not (Test-Path -LiteralPath (Join-Path $agentsRoot ("{0}.md" -f $a)))) { $fail += "agents/$a.md missing" }
}
if (Test-Path -LiteralPath $agentsRoot) {
    foreach ($am in (Get-ChildItem -LiteralPath $agentsRoot -Filter *.md -File)) {
        $body = Get-Frontmatter (Get-Content -LiteralPath $am.FullName -Raw)
        if ($null -eq $body) { $fail += "agents/$($am.Name) missing frontmatter"; continue }
        if (-not [regex]::IsMatch($body, '(?m)^model:\s*opus\s*$')) { $fail += "agents/$($am.Name) frontmatter lacks 'model: opus'" }
        if (-not [regex]::IsMatch($body, '(?m)^effort:\s*xhigh\s*$')) { $fail += "agents/$($am.Name) frontmatter lacks 'effort: xhigh'" }
    }
}
else { $fail += 'agents/ (missing)' }
Emit 'agents' 'author/explorer/reviewer/researcher present, all model=opus effort=xhigh' $fail

# --- Check 8: vendored skills pair SOURCE with a LICENSE --------------------
$fail = @()
if (Test-Path -LiteralPath $skillsRoot) {
    foreach ($dir in (Get-ChildItem -LiteralPath $skillsRoot -Directory)) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName 'SOURCE')) {
            $license = Get-ChildItem -LiteralPath $dir.FullName -Filter 'LICENSE*' -File -ErrorAction SilentlyContinue
            if (-not $license) { $fail += "skills/$($dir.Name) has SOURCE but no LICENSE* file" }
        }
    }
}
Emit 'vendored' 'every skill with a SOURCE file also ships a LICENSE*' $fail

# --- Check 9: hook scripts are pure ASCII (mojibake defense) ----------------
$fail = @()
$scriptsRoot = Join-Path $RepoRoot 'scripts'
if (Test-Path -LiteralPath $scriptsRoot) {
    foreach ($ps in (Get-ChildItem -LiteralPath $scriptsRoot -Filter *.ps1 -File)) {
        $bytes = [System.IO.File]::ReadAllBytes($ps.FullName)
        $nonAscii = 0
        foreach ($b in $bytes) { if ($b -gt 127) { $nonAscii++ } }
        if ($nonAscii -gt 0) { $fail += "scripts/$($ps.Name): $nonAscii non-ASCII byte(s)" }
    }
}
else { $fail += 'scripts/ (missing)' }
Emit 'ascii-scripts' 'all scripts/*.ps1 are pure ASCII' $fail

# --- Check 10: .gitignore ignores HANDOFF.md -------------------------------
$fail = @()
$giPath = Join-Path $RepoRoot '.gitignore'
if (-not (Test-Path -LiteralPath $giPath)) { $fail += '.gitignore (missing)' }
elseif (-not (Get-Content -LiteralPath $giPath | Where-Object { $_.Trim() -eq 'HANDOFF.md' })) {
    $fail += "no 'HANDOFF.md' line in .gitignore"
}
Emit 'gitignore' '.gitignore ignores HANDOFF.md' $fail

if ($script:Failed) { exit 1 } else { exit 0 }
