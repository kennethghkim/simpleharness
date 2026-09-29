# simpleharness SessionStart hook (plugin distribution only)
#
# Injects the harness operating protocol (CLAUDE.md at the plugin root) into
# session context on startup, after /clear, and after compaction (see the
# matcher in hooks/hooks.json). Plugins cannot ship a CLAUDE.md that loads as
# project context -- a documented limitation -- so this hook provides the
# equivalent: one protocol injection per session (re-)start.
#
# NOT used by the profile-deploy path (deploy.ps1): a profile CLAUDE.md loads
# natively there, and injecting on top of it would double the protocol.
#
# Contract (same output shape as prompt-hook.ps1, verified against the
# SessionStart hook docs and a working plugin):
#   - Hook input JSON arrives on stdin; drained, content unused.
#   - Inject via hookSpecificOutput.additionalContext on stdout, exit 0.
#   - Never blocks. ConvertTo-Json escapes non-ASCII to \uXXXX, so stdout is
#     pure ASCII and the CJK-locale console mojibake rule does not apply.
#
# Fail-open: on any error, exit 0 with no output (session proceeds bare).

$ErrorActionPreference = 'Stop'

try {
    [void][Console]::In.ReadToEnd()

    # Best-effort GC of orphaned session temp (own guard; never affects injection
    # or exit). Claude Code does not auto-clean scratchpad; see scratch-gc.ps1.
    try { . (Join-Path $PSScriptRoot 'scratch-gc.ps1'); Invoke-ScratchGC } catch { }

    $pluginRoot = Split-Path -Parent $PSScriptRoot
    $protocol = Get-Content -LiteralPath (Join-Path $pluginRoot 'CLAUDE.md') -Raw -Encoding utf8

    # Strip block-level HTML comments before injecting, matching native Claude
    # Code CLAUDE.md loading, so maintainer notes (<!-- ... -->) cost no context.
    $protocol = [regex]::Replace($protocol, '(?s)<!--.*?-->', '')

    $context = @(
        '<simpleharness-operating-protocol>',
        'The following is your always-on operating protocol for this session.',
        'Treat it exactly as you would project CLAUDE.md instructions.',
        '',
        $protocol,
        '</simpleharness-operating-protocol>'
    ) -join "`n"

    $out = [ordered]@{
        hookSpecificOutput = [ordered]@{
            hookEventName     = 'SessionStart'
            additionalContext = $context
        }
    }

    Write-Output ($out | ConvertTo-Json -Compress -Depth 4)
    exit 0
}
catch {
    # Fail-open: never disrupt session start because the hook errored.
    exit 0
}
