# simpleharness scratch GC -- Invoke-ScratchGC
#
# Best-effort garbage collection of ORPHANED per-session temp under the Claude
# Code temp root. Claude Code never auto-cleans the session scratchpad (not on
# graceful exit, not on force-close; Windows Temp is not purged on exit), so a
# force-closed session leaves its temp behind forever. This runs at the NEXT
# session start (dot-sourced + called by session-start-hook.ps1) to sweep old
# orphans -- the only point that catches a session which never checkpointed.
#
# SAFETY (invariant proven by tests/gc.tests.ps1):
#   - Deletes ONLY dirs named scratchpad / tasks / tool-results, and ONLY at
#     depth <Root>/<project>/<session>/<target> -- scope-locked.
#   - Deletes ONLY when the target dir's LastWriteTime is older than -Days. The
#     current session and any recently-active session have recent mtime, so they
#     NEVER match (no session-id lookup needed).
#   - NEVER touches Claude Code state (projects/ transcripts, sessions/, history,
#     cache/, backups/) -- those live outside the target names.
#   - Fully fail-open: every op is -ErrorAction SilentlyContinue; the caller wraps
#     this in its own try/catch and ignores failures.
#
# This file only DEFINES the function (no execution), so it is safe to dot-source
# from the hook and from tests.

function Invoke-ScratchGC {
    param(
        [string] $Root = (Join-Path $env:LOCALAPPDATA 'Temp\claude'),
        [int]    $Days = 7
    )
    if (-not (Test-Path -LiteralPath $Root)) { return }
    $cutoff  = (Get-Date).AddDays(-$Days)
    $targets = @('scratchpad', 'tasks', 'tool-results')
    foreach ($proj in (Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)) {
        foreach ($sess in (Get-ChildItem -LiteralPath $proj.FullName -Directory -ErrorAction SilentlyContinue)) {
            foreach ($t in $targets) {
                $p = Join-Path $sess.FullName $t
                if (Test-Path -LiteralPath $p) {
                    $item = Get-Item -LiteralPath $p -ErrorAction SilentlyContinue
                    if ($null -ne $item -and $item.LastWriteTime -lt $cutoff) {
                        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
                    }
                }
            }
        }
    }
}
