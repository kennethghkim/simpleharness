---
name: longrun
description: Use when launching, resuming, or supervising a finite job expected to run minutes to hours — a build, test suite, migration, media/model processing, batch import, audit, crawl, or a fleet of background agents — especially when the output is expensive to regenerate, partial output can corrupt a resume, or the user expects unattended progress. Makes the run restartable, inspectable, and verifiable without corrupting artifacts or spamming the user.
---

# Long-Running Jobs

Use this for any long-running but finite job. The goal: make the run restartable, inspectable, and verifiable — without corrupting artifacts or flooding the user with status noise.

## Trigger

A command or agent expected to run minutes to hours (or longer), especially when:
- the output is expensive to regenerate,
- partial output can corrupt a resume, or
- the user expects unattended progress.

Applies equally to a build, a test suite, a schema/data migration, media or model processing, a batch import, an audit, a crawl, or a dispatched fleet of background agents.

## Launch With a Tracked Handle

Prefer a background mechanism that notifies you on completion and exposes an exit code:
- **Claude Code Bash with `run_in_background`**, or
- **an Agent dispatched with `run_in_background`** — both re-invoke you when the job exits.

Avoid blind detaches — `nohup`, a trailing `&`, or PowerShell `Start-Process` — unless you have verified the process actually survives the launching session. A detached job you cannot observe is worse than a foreground one.

For remote work over SSH, prefer a foreground SSH process owned by the supervisor (this session), so completion and exit code flow back here rather than being orphaned on the remote host.

## Artifact Discipline

Keep separate, non-overlapping paths for each artifact class. Do NOT collapse them:

- **Durable output** — the expensive product. Format is whatever the job produces: a binary build, a CSV/Parquet export, a SQLite/DB file, a media directory, a `results.jsonl`, etc.
- **Progress / checkpoint** — a small sidecar recording how far the run got (`progress.json`, a checkpoint row, a cursor).
- **Logs** — the run's stdout/stderr (`run.log`).
- **Error queue** — failures set aside for retry (`errors.jsonl`, `retry.txt`).
- **Final report** — the summary you produce at the end (`summary.json`, `report.md`).

**Never write a report over the durable-output path.** Overwriting the product with a summary is unrecoverable. On Windows, put working artifacts in the session scratchpad, not `/tmp`.

## Preflight / Resume Safety

**Smoke a tiny real subset first.** Before the full run, execute a `--limit`/dry subset against the real target to confirm:
- the flags are correct,
- the auth/network path works (verify success WITHOUT printing secrets to the console),
- the output shape is what you expect (parse a sample from disk),
- a second run is idempotent (does not duplicate or clobber).

```powershell
# $scratch = the session scratchpad directory
<command> --limit 2 --out "$scratch/smoke.out" --progress "$scratch/smoke-progress.json"
```

**On resume**, do not trust the tail of an interrupted run:
1. Read the existing durable output and parse only fully-complete records.
2. Detect a torn/partial final record (a half-written line, a truncated file, an incomplete DB transaction).
3. Build the skip/resume set ONLY from validated-complete records.
4. Quarantine or truncate the corrupt tail only after confirming the path is the intended output.

## Sparse Liveness

Supervision follows CLAUDE.md "Delegation Protocol" (liveness-evidence + anti-duplication). Check at meaningful intervals, NOT continuously. Good evidence:
- the process is still alive,
- the durable-output file's size/mtime advanced,
- the complete-record count increased,
- the progress checkpoint advanced,
- the error queue is bounded (not exploding),
- disk and memory are healthy.

After any context switch or compaction, re-read the current disk artifacts before reporting counts — never report remembered state. Never redo the delegated work on the main thread while waiting. No polling spam: a check that adds no new evidence is not worth reporting.

## Completion Verification

Completion follows CLAUDE.md "Verification Iron Law" — fresh evidence before any success claim. On exit:
1. Record the exit code.
2. Tail the logs for final errors, redacting secrets.
3. Parse the output, progress, and error artifacts FROM DISK.
4. Reconcile counts (expected vs produced vs errored).
5. Run a schema/shape check on the output.
6. Run focused retries ONLY for transient failures (timeouts, rate limits) — never for deterministic ones.
7. Produce a final report with artifact paths, counts, gates passed, and any remaining retry/error queue.

**Exit 0 does not equal data success.** A job can exit clean and still produce truncated, empty, or malformed output — validate the artifact, not just the return code.

### Generic shape / count check

Count validated-complete records straight from disk (adapt the completeness test to your format):

```powershell
# Line-based output: count non-empty, parseable records
$out = "$scratch/results.out"
$n = 0
if (Test-Path $out) {
    Get-Content $out | Where-Object { $_.Trim() -ne '' } | ForEach-Object { $n++ }
}
Write-Output "$out : $n records"
```

For a binary/media job, check file count and per-file integrity instead (e.g. expected file count, non-zero sizes, a hash or a header/`ffprobe`-style probe). For a DB, run a `COUNT(*)` and a constraint check via the language-native driver.

**UTF-8 discipline:** on a CJK-locale Windows console, stdout mojibakes non-ASCII. If output or logs can contain non-ASCII, write the check result to a UTF-8 file and Read it back rather than eyeballing the terminal; set `PYTHONUTF8=1` for Python subprocesses (use `python`, not `python3`).

## Pitfalls

- Detached-process blindness — launched, cannot observe, cannot confirm exit.
- A torn final record poisoning the resume set.
- A report overwriting the durable output.
- Stale progress counts after context compaction (report from disk, not memory).
- Polling spam — frequent checks that add no evidence.
- Treating exit code 0 as data success without validating the artifact.
- Retrying deterministic failures as if they were transient.
