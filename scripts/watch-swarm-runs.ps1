<#
.SYNOPSIS
    File-watcher that automatically emits Seq events for Swarm runs.

.DESCRIPTION
    Monitors .swarm/runs by polling every 2 seconds and calls emit-seq-event.ps1
    whenever key files change. No dependency on the manager calling the script.

    Trigger points:
      - run.status.json appears in a new run folder  -> emit run-started
      - handoff.json step number increases            -> emit step-completed
      - run.status.json outcome becomes "failed"      -> emit run-failed

    On startup the watcher snapshots existing runs so it does not re-emit events
    for runs that were already in progress or completed before it started.

    Run this script in a terminal before (or during) a Swarm run. Leave it running
    in the background for the duration of your session.

.PARAMETER WorkspaceRoot
    Root of the project repo. Defaults to current directory.

.PARAMETER PollSeconds
    Polling interval in seconds. Defaults to 2.

.EXAMPLE
    watch-swarm-runs.ps1 -WorkspaceRoot "c:\devops\repos\speed-merchants"
    watch-swarm-runs.ps1   # run from workspace root
#>

[CmdletBinding()]
param(
    [string]$WorkspaceRoot = ".",
    [int]$PollSeconds      = 2
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"

$WorkspaceRoot = (Resolve-Path $WorkspaceRoot).Path
$runsDir       = Join-Path $WorkspaceRoot ".swarm/runs"

if (-not (Test-Path $runsDir)) {
    New-Item -ItemType Directory -Path $runsDir -Force | Out-Null
}

Write-Host "[SwarmWatch] WorkspaceRoot : $WorkspaceRoot"
Write-Host "[SwarmWatch] Watching      : $runsDir"
Write-Host "[SwarmWatch] Poll interval : ${PollSeconds}s"
Write-Host "[SwarmWatch] Press Ctrl+C to stop."
Write-Host ""

# --- Deduplication ---
# Keys: "{runId}:run-started", "{runId}:step-{N}", "{runId}:run-failed"
$emitted = @{}

function Read-JsonSafe($path) {
    if (-not (Test-Path $path)) { return $null }
    try { return [string](Get-Content $path -Raw) | ConvertFrom-Json } catch { return $null }
}

function Invoke-Emit($runId, $eventType) {
    Write-Host "[SwarmWatch] $(Get-Date -Format 'HH:mm:ss')  $eventType  $($runId.Substring(0,8))..."
    $out = emit-seq-event.ps1 -RunId $runId -EventType $eventType -WorkspaceRoot $WorkspaceRoot 2>&1
    if ($out) { Write-Host "[SwarmWatch]   $out" }
}

function Process-Run($runDir) {
    $runId       = $runDir.Name
    $statusPath  = Join-Path $runDir.FullName "run.status.json"
    $handoffPath = Join-Path $runDir.FullName "handoff.json"

    # --- run-started ---
    $startKey = "$runId`:run-started"
    if ((Test-Path $statusPath) -and -not $emitted[$startKey]) {
        $emitted[$startKey] = $true
        Invoke-Emit $runId "run-started"
    }

    # --- step-completed (deduplicated by handoff step number) ---
    if (Test-Path $handoffPath) {
        $handoff = Read-JsonSafe $handoffPath
        if ($handoff) {
            $stepNum = if ($handoff.PSObject.Properties['step']) { [int]$handoff.step } else { 0 }
            $stepKey = "$runId`:step-$stepNum"
            if (-not $emitted[$stepKey]) {
                $emitted[$stepKey] = $true
                Invoke-Emit $runId "step-completed"
            }
        }
    }

    # --- run-failed ---
    $failKey = "$runId`:run-failed"
    if (-not $emitted[$failKey] -and (Test-Path $statusPath)) {
        $status = Read-JsonSafe $statusPath
        if ($status -and $status.outcome -eq "failed") {
            $emitted[$failKey] = $true
            Invoke-Emit $runId "run-failed"
        }
    }
}

# --- Snapshot existing runs on startup so we don't re-emit historical events ---
$existing = @(Get-ChildItem $runsDir -Directory -ErrorAction SilentlyContinue)
foreach ($runDir in $existing) {
    $runId       = $runDir.Name
    $statusPath  = Join-Path $runDir.FullName "run.status.json"
    $handoffPath = Join-Path $runDir.FullName "handoff.json"

    # Mark run-started as done for all existing runs
    $emitted["$runId`:run-started"] = $true

    # Mark current handoff step as done
    if (Test-Path $handoffPath) {
        $h = Read-JsonSafe $handoffPath
        if ($h) {
            $stepNum = if ($h.PSObject.Properties['step']) { [int]$h.step } else { 0 }
            $emitted["$runId`:step-$stepNum"] = $true
        }
    }

    # Mark run-failed as done if already failed
    if (Test-Path $statusPath) {
        $s = Read-JsonSafe $statusPath
        if ($s -and $s.outcome -eq "failed") { $emitted["$runId`:run-failed"] = $true }
    }
}

if ($existing.Count -gt 0) {
    Write-Host "[SwarmWatch] Skipping $($existing.Count) existing run(s). Watching for new activity..."
} else {
    Write-Host "[SwarmWatch] No existing runs. Watching for new runs..."
}
Write-Host ""

# --- Poll loop ---
try {
    while ($true) {
        $runs = @(Get-ChildItem $runsDir -Directory -ErrorAction SilentlyContinue)
        foreach ($runDir in $runs) {
            Process-Run $runDir
        }
        Start-Sleep -Seconds $PollSeconds
    }
} finally {
    Write-Host ""
    Write-Host "[SwarmWatch] Stopped."
}
