---
description: Dependency doctor for the simpleharness harness — checks pwsh / gh / ripgrep / ast-grep / python / node, installs only what is missing (winget on Windows), sets up the Playwright browser, and reports a status table. Idempotent.
---

# simpleharness environment-setup — dependency doctor

Check every dependency below, install ONLY what is missing, verify each
install with a fresh command, and finish with a status table. Idempotent:
re-running must be safe. Never install anything not on this list; never
upgrade or reinstall a tool that is already present.

## Procedure (per tool)

1. Check: run the version command. Present → record version, move on.
2. Missing → run the install command for this platform.
3. Re-check. A fresh install may not be on PATH in the current shell — try
   the installer's reported path or a new shell invocation before declaring
   failure.
4. Record: present / installed now / FAILED (with the actual error).

Windows installs use winget. If winget itself is missing, STOP and tell the
user to install "App Installer" from the Microsoft Store, then re-run this
command. macOS: `brew install powershell gh ripgrep ast-grep python node`.
Linux: distro package manager equivalents.

| Tool | Check | Windows install (winget) |
|---|---|---|
| PowerShell 7 | `pwsh -v` | `winget install --id Microsoft.PowerShell -e --accept-source-agreements --accept-package-agreements` |
| gh CLI | `gh --version` | `winget install --id GitHub.cli -e --accept-source-agreements --accept-package-agreements` |
| ripgrep | `rg --version` | `winget install --id BurntSushi.ripgrep.MSVC -e --accept-source-agreements --accept-package-agreements` |
| ast-grep | `sg --version` | `winget install --id ast-grep.ast-grep -e --accept-source-agreements --accept-package-agreements` — if the winget package is unavailable, fall back to the ast-grep skill's `install.ps1` (inside this plugin's `skills/ast-grep/`) |
| Python 3 | `python --version` | `winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements` |
| Node.js LTS | `node --version` | `winget install --id OpenJS.NodeJS.LTS -e --accept-source-agreements --accept-package-agreements` |

## Playwright browser

Node.js present → run `npx -y playwright install chromium` (downloads the
browser that the bundled Playwright MCP server drives). If Node was just
installed and `npx` is not yet on PATH, use the full path or tell the user a
new session is needed first. If the download fails, report it — do not retry
more than once.

## LSP language servers (Python + TS/JS)

Node.js present → install the two language servers the bundled LSP MCP drives
(idempotent — skip either that is already present):
- `npm i -g typescript-language-server typescript` — verify with
  `typescript-language-server --version`.
- `npm i -g pyright` — verify with `pyright --version`.

Both run over stdio and must be on PATH. The LSP-MCP bridge itself is fetched
by `npx` on first run (like Playwright above), so it needs no install. Other
languages are added on demand. These are npm-global installs — do NOT add them
to the winget table.

### Pin Python + TS/JS diagnostics (`~/.lsp-mcp.json`)

`lsp-mcp-server@1.1.20`'s default servers are `pylsp` (Python) and
`typescript-language-server` (TS/JS). On Windows BOTH fail out of the box: the
bridge spawns with `shell:false`, and the npm-global shims have no `.exe` (a
`.cmd` throws), so `pylsp`/`typescript-language-server` hit `ENOENT` and the
server never starts (Python here has only pyright, not pylsp). Override the
bridge via its config file `~/.lsp-mcp.json` (entries merge by server `id`),
invoking `node` on each language server's JS entrypoint. The paths are
machine-specific → generate here (after the servers are installed), preserving
any other servers already in the file:

```powershell
$path = Join-Path $HOME '.lsp-mcp.json'
$root = npm root -g
$py = [ordered]@{ id='python'; extensions=@('.py','.pyi'); languageIds=@('python'); command='node'; args=@((Join-Path $root 'pyright/langserver.index.js'),'--stdio'); rootPatterns=@('pyproject.toml','setup.py','setup.cfg','requirements.txt','Pipfile') }
$ts = [ordered]@{ id='typescript'; extensions=@('.ts','.tsx','.js','.jsx','.mjs','.cjs','.mts','.cts'); languageIds=@('typescript','typescriptreact','javascript','javascriptreact'); command='node'; args=@((Join-Path $root 'typescript-language-server/lib/cli.mjs'),'--stdio'); rootPatterns=@('tsconfig.json','jsconfig.json','package.json') }
$existing = if (Test-Path $path) { Get-Content -Raw $path | ConvertFrom-Json } else { $null }
$servers = @(); if ($existing.servers) { $servers = @($existing.servers | Where-Object { $_.id -notin 'python','typescript' }) }
$servers += $py; $servers += $ts
[ordered]@{ servers = $servers } | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 $path
```

macOS/Linux: same shape — `node <npm root -g>/pyright/langserver.index.js --stdio`
and `node <npm root -g>/typescript-language-server/lib/cli.mjs --stdio`. Note a
project-local `.lsp-mcp.json` in the launch cwd shadows this home file (first
config found wins — no cross-file merge).

## After installing

- `pwsh` was missing before this run → tell the user to RESTART Claude Code:
  the harness hooks (including the operating-protocol injection) run on pwsh
  and have been silently inactive until now.
- `gh` newly installed → `gh auth login` is interactive; the user runs it
  themselves (suggest typing `! gh auth login` in the prompt).
- Any new PATH entry needs a new terminal/session to be visible everywhere.

## Report

Finish with exactly: a table of tool → version → status (present /
installed now / FAILED + reason), then the list of user actions remaining
(restart, `gh auth login`, new session), or "none".
