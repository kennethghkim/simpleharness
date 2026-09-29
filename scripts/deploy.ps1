# deploy.ps1 -- deploy simpleharness artifacts to ~/.claude/
#
# Backs up every file it would overwrite to ~/.claude/backup-<yyyyMMdd-HHmm>/
# (mirroring relative paths), then copies:
#   CLAUDE.md               -> ~/.claude/CLAUDE.md
#   agents/*                -> ~/.claude/agents/
#   skills/*                -> ~/.claude/skills/       (whole skill dirs)
#   scripts/stop-hook.ps1   -> ~/.claude/hooks/stop-hook.ps1
#   scripts/prompt-hook.ps1 -> ~/.claude/hooks/prompt-hook.ps1
#
# It NEVER touches settings.json -- it prints merge instructions for
# settings/settings-fragment.json and shows the fragment.
#
# Idempotent: re-running with unchanged sources produces the same target state.
# Glob-based: picks up whatever exists in agents/ and skills/ at run time.
# Retention: only the most recent backup-* dir is kept; older ones are pruned.

#Requires -Version 7.0
$ErrorActionPreference = 'Stop'

$repo   = Split-Path -Parent $PSScriptRoot          # repo root (parent of scripts/)
$target = Join-Path $HOME '.claude'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmm'
$backup = Join-Path $target "backup-$stamp"

if (-not (Test-Path -LiteralPath $target)) {
    throw "Deploy target $target does not exist. Is this the right profile?"
}

# (relative-source, relative-target) pairs. Directories are copied recursively.
$plan = @(
    @{ src = 'CLAUDE.md';               dst = 'CLAUDE.md' }
    @{ src = 'scripts/stop-hook.ps1';   dst = 'hooks/stop-hook.ps1' }
    @{ src = 'scripts/prompt-hook.ps1'; dst = 'hooks/prompt-hook.ps1' }
)
foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repo 'agents') -File -Filter '*.md') {
    $plan += @{ src = "agents/$($f.Name)"; dst = "agents/$($f.Name)" }
}
foreach ($d in Get-ChildItem -LiteralPath (Join-Path $repo 'skills') -Directory) {
    foreach ($f in Get-ChildItem -LiteralPath $d.FullName -File -Recurse) {
        $rel = [IO.Path]::GetRelativePath($repo, $f.FullName) -replace '\\', '/'
        $plan += @{ src = $rel; dst = $rel }   # skills/<name>/... maps 1:1
    }
}

# Backup pass: only files that exist at the target and differ from the source.
$backedUp = 0
foreach ($item in $plan) {
    $dstPath = Join-Path $target $item.dst
    $srcPath = Join-Path $repo  $item.src
    if (Test-Path -LiteralPath $dstPath -PathType Leaf) {
        $same = (Get-FileHash -LiteralPath $dstPath).Hash -eq (Get-FileHash -LiteralPath $srcPath).Hash
        if (-not $same) {
            $bakPath = Join-Path $backup $item.dst
            New-Item -ItemType Directory -Force -Path (Split-Path -Parent $bakPath) | Out-Null
            Copy-Item -LiteralPath $dstPath -Destination $bakPath -Force
            $backedUp++
        }
    }
}

# Copy pass.
$copied = 0
foreach ($item in $plan) {
    $srcPath = Join-Path $repo  $item.src
    $dstPath = Join-Path $target $item.dst
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $dstPath) | Out-Null
    Copy-Item -LiteralPath $srcPath -Destination $dstPath -Force
    $copied++
}

Write-Host "Deployed $copied files to $target"
if ($backedUp -gt 0) { Write-Host "Backed up $backedUp changed files to $backup" }
else                 { Write-Host 'No existing files differed; no backup created.' }

# Retention: keep only the most recent backup-* dir (the stamp format sorts
# lexicographically = chronologically), prune the rest.
$backups = @(Get-ChildItem -LiteralPath $target -Directory -Filter 'backup-*' |
    Sort-Object Name -Descending)
if ($backups.Count -gt 1) {
    foreach ($old in ($backups | Select-Object -Skip 1)) {
        Remove-Item -LiteralPath $old.FullName -Recurse -Force
    }
    Write-Host "Pruned $($backups.Count - 1) older backup dir(s); kept $($backups[0].Name)"
}

# Settings fragment: manual merge only.
$fragment = Join-Path $repo 'settings/settings-fragment.json'
Write-Host ''
Write-Host '=== MANUAL STEP: settings.json hook merge ==='
Write-Host "Merge the following fragment into $target/settings.json under the top-level"
Write-Host '"hooks" key (create it if absent), then restart Claude Code:'
Write-Host ''
# The shipped fragment is generic; substitute the real home dir for this machine.
(Get-Content -LiteralPath $fragment -Raw) -replace '<home>', ($HOME -replace '\\', '/') | Write-Host
$settings = Join-Path $target 'settings.json'
if (Test-Path -LiteralPath $settings) {
    $hasHook = Select-String -LiteralPath $settings -Pattern '(stop|prompt)-hook\.ps1' -Quiet
    if ($hasHook) { Write-Host 'NOTE: settings.json already references stop-hook.ps1 - likely merged.' }
    else          { Write-Host 'NOTE: settings.json exists but has no stop-hook.ps1 reference yet.' }
}
