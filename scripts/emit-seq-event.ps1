<#
.SYNOPSIS
    Emits a CLEF event to Seq for a Swarm run step transition.

.DESCRIPTION
    Called by the Manager at three trigger points:
      - run-started    After creating the initial run.status.json
      - step-completed After handoff.json is written for each step
      - run-failed     When setting outcome: failed in run.status.json

    Each event carries the full input/output artifacts for the step as structured
    properties so runs can be reviewed entirely within Seq without opening the run
    directory. RunId is a property tag only and does not appear in message text.

    Reads .swarm/config/seq.json; does nothing if missing, disabled, or serverUrl empty.
    Always exits 0. Never blocks a run.

.PARAMETER RunId
    GUID of the Swarm run.

.PARAMETER EventType
    One of: run-started, step-completed, run-failed

.PARAMETER WorkspaceRoot
    Root of the project repo. Defaults to current directory.

.EXAMPLE
    emit-seq-event.ps1 -RunId "8bb366f8-903f-4423-8ca7-c1b81201802d" -EventType run-started
    emit-seq-event.ps1 -RunId "8bb366f8-903f-4423-8ca7-c1b81201802d" -EventType step-completed
    emit-seq-event.ps1 -RunId "8bb366f8-903f-4423-8ca7-c1b81201802d" -EventType run-failed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidateSet("run-started", "step-completed", "run-failed")]
    [string]$EventType,

    [string]$WorkspaceRoot = "."
)

Set-StrictMode -Off
$ErrorActionPreference = "SilentlyContinue"

# --- Helpers ---

function Read-JsonFile($path) {
    if (-not (Test-Path $path)) { return $null }
    try { return Get-Content $path -Raw | ConvertFrom-Json }
    catch { return $null }
}

function Read-TextFile($path, [int]$cap = 0) {
    if (-not (Test-Path $path)) { return $null }
    try {
        # Cast to [string] to strip PSProvider NoteProperties that Get-Content -Raw
        # attaches in PS 5.x (ReadCount, Drives, etc.) - they inflate ConvertTo-Json output
        $text = [string](Get-Content $path -Raw)
        if ($cap -gt 0 -and $text.Length -gt $cap) {
            return $text.Substring(0, $cap) + "`n[... truncated at $cap chars]"
        }
        return $text
    } catch { return $null }
}

# --- Load seq.json ---
$seqConfigPath = Join-Path $WorkspaceRoot ".swarm/config/seq.json"
if (-not (Test-Path $seqConfigPath)) { exit 0 }

$seqConfig = Read-JsonFile $seqConfigPath
if (-not $seqConfig) { Write-Host "[Swarm] Could not parse seq.json"; exit 0 }
if ($seqConfig.enabled -ne $true) { exit 0 }
if ([string]::IsNullOrWhiteSpace($seqConfig.serverUrl)) { exit 0 }

# --- Load run.status.json ---
$runDir    = Join-Path $WorkspaceRoot ".swarm/runs/$RunId"
$statusPath = Join-Path $runDir "run.status.json"
if (-not (Test-Path $statusPath)) {
    Write-Host "[Swarm] run.status.json not found: $statusPath"
    exit 0
}

$status = Read-JsonFile $statusPath
if (-not $status) { Write-Host "[Swarm] Could not parse run.status.json"; exit 0 }

# --- Resolve RunId (handle both 'runId' and 'run-id' field names) ---
$resolvedRunId = $RunId
if ($status.PSObject.Properties['run-id'] -and -not [string]::IsNullOrWhiteSpace($status.'run-id')) {
    $resolvedRunId = $status.'run-id'
} elseif ($status.PSObject.Properties['runId'] -and -not [string]::IsNullOrWhiteSpace($status.runId)) {
    $resolvedRunId = $status.runId
}

$currentStep = $status.'current-step'
$outcome     = if ($status.PSObject.Properties['outcome']) { $status.outcome } else { "in-progress" }

# --- Determine log level ---
$knownNonEscalation = @("in-progress", "completed", "paused-for-review", "failed")
$level = switch ($outcome) {
    "failed"    { "Error" }
    { $_ -notin $knownNonEscalation } { "Warning" }
    default     { "Information" }
}

# --- PipelinePhase: human-readable, filterable tag — separate from message text ---
# Computed here from current-step + sub-plan state so all event types carry it.
# Sub-plan qualifier (e.g. "1 of 2") is appended when decomposition is active.
$phaseLabels = @{
    "core-planner"          = "Planning"
    "constraint-reviewer"   = "Constraint Review"
    "plan-integrator"       = "Integration"
    "plan-decomposer"       = "Decomposition"
    "implementor"           = "Implementation"
    "reviewer"              = "Review"
    "tester"                = "Testing"
    "verifier"              = "Verification"
}
$baseLabel    = if ($phaseLabels.ContainsKey($currentStep)) { $phaseLabels[$currentStep] } else { $currentStep }
$subIdx       = if ($status.PSObject.Properties['subPlanIndex']) { $status.subPlanIndex } else { $null }
$subTotal     = if ($status.PSObject.Properties['subPlanTotal']) { $status.subPlanTotal } else { $null }
$pipelinePhase = if ($subIdx -and $subTotal) { "$baseLabel ($subIdx of $subTotal)" } else { $baseLabel }

# --- Build CLEF event ---
# RunId and PipelinePhase are property tags only — kept out of @mt so messages stay clean
$clefEvent = [ordered]@{
    "@t"            = $null
    "@mt"           = $null
    "@l"            = $level
    "@sc"           = "Swarm"
    "RunId"         = $resolvedRunId
    "PipelinePhase" = $pipelinePhase
    "CurrentStep"   = $currentStep
    "Outcome"       = $outcome
}

switch ($EventType) {

    "run-started" {
        $ts = if ($status.PSObject.Properties['created-at']) { $status.'created-at' } else { $status.'updated-at' }
        $clefEvent["@t"]        = $ts
        $clefEvent["@mt"]       = "Run started: {PipelinePhase}"
        $clefEvent["@l"]        = "Information"
        # Store as PSCustomObject (not raw string) so ConvertTo-Json -Depth 5 serializes
        # it cleanly without the {"value":"..."} wrapper that raw strings produce
        $clefEvent["RunStatus"] = $status
    }

    "run-failed" {
        $clefEvent["@t"]        = $status.'updated-at'
        $clefEvent["@mt"]       = "Run failed: {PipelinePhase}"
        $clefEvent["@l"]        = "Error"
        $clefEvent["RunStatus"] = $status
    }

    "step-completed" {
        $clefEvent["@t"] = $status.'updated-at'

        # --- handoff.json (input to the next agent) ---
        $handoff   = Read-JsonFile (Join-Path $runDir "handoff.json")
        $nextAgent = $null
        $stepNum   = $null

        if ($handoff) {
            $nextAgent = $handoff.to
            $stepNum   = $handoff.step
            $clefEvent["HandoffInput"] = $handoff
        }

        # --- {agent}.result.json (output of this step) ---
        $result = Read-JsonFile (Join-Path $runDir "$currentStep.result.json")
        if ($result) {
            $clefEvent["StepResult"] = $result

            if ($result.PSObject.Properties['filesChanged']) {
                $allFiles  = @($result.filesChanged)
                $truncated = $allFiles.Count -gt 20
                $fc        = @($allFiles | Select-Object -First 20)
                if ($truncated) { $fc += "[... truncated]" }
                $clefEvent["FilesChanged"] = $fc
            }
        }

        # --- context.pack.md (context document sent to the agent; markdown stays as string) ---
        $contextPackPath = $null
        if ($handoff -and $handoff.PSObject.Properties['artifacts'] -and
            $handoff.artifacts.PSObject.Properties['contextPackPath']) {
            $contextPackPath = $handoff.artifacts.contextPackPath
            if (-not [System.IO.Path]::IsPathRooted($contextPackPath)) {
                $contextPackPath = Join-Path $WorkspaceRoot $contextPackPath
            }
        }
        if (-not $contextPackPath) { $contextPackPath = Join-Path $runDir "context.pack.md" }
        $contextPack = Read-TextFile $contextPackPath
        if ($contextPack) { $clefEvent["ContextPack"] = $contextPack }

        # --- Step-specific output documents ---
        # Attach the primary output document(s) for plan-producing steps so the full
        # content is readable in Seq without opening the run directory.
        switch ($currentStep) {
            "core-planner" {
                $doc = Read-JsonFile (Join-Path $runDir "plan.json")
                if ($doc) { $clefEvent["Plan"] = $doc }
            }
            "plan-integrator" {
                $doc = Read-TextFile (Join-Path $runDir "integrated-plan.md")
                if ($doc) { $clefEvent["IntegratedPlan"] = $doc }
                $log = Read-JsonFile (Join-Path $runDir "integration-log.json")
                if ($log) { $clefEvent["IntegrationLog"] = $log }
            }
            "plan-decomposer" {
                $manifest = Read-JsonFile (Join-Path $runDir "subplans.manifest.json")
                if ($manifest) { $clefEvent["SubplansManifest"] = $manifest }
                # Attach each scoped plan file (scoped-plan-1.md, scoped-plan-2.md, ...)
                $scopedFiles = @(Get-ChildItem $runDir -Filter "scoped-plan-*.md" 2>$null | Sort-Object Name)
                foreach ($f in $scopedFiles) {
                    $content = Read-TextFile $f.FullName
                    $propName = ($f.BaseName -replace '-(\d+)$', '$1') -replace '-', ''
                    # e.g. scoped-plan-1 -> ScopedPlan1
                    $propName = "ScopedPlan" + ($f.BaseName -replace '.*-', '')
                    if ($content) { $clefEvent[$propName] = $content }
                }
            }
        }

        # --- PhaseKey ---
        $subPlanIndex = if ($status.PSObject.Properties['subPlanIndex']) { $status.subPlanIndex } else { $null }
        $phaseKey     = if ($subPlanIndex) { "$currentStep.subplan-$subPlanIndex" } else { $currentStep }

        $clefEvent["@mt"]       = "Step {Step}: {PipelinePhase} completed, next {NextAgent}"
        $clefEvent["NextAgent"] = $nextAgent
        $clefEvent["Step"]      = $stepNum
        $clefEvent["PhaseKey"]  = $phaseKey

        if ($subPlanIndex) {
            $clefEvent["SubPlanIndex"] = $subPlanIndex
            $clefEvent["SubPlanTotal"] = if ($status.PSObject.Properties['subPlanTotal']) { $status.subPlanTotal } else { $null }
        }

    }
}

# --- POST to Seq ---
# Uses HttpClient directly for deterministic 15-second timeout.
# Invoke-RestMethod -TimeoutSec is unreliable in PS 5.x for stalled connections.
#
# PS 5.x: System.Net.Http is not auto-loaded — must load explicitly.
# PS 5.x bug: ConvertTo-Json on any container (OrderedDictionary or PSObject) that holds
# PSCustomObject values serializes the full .NET reflection tree, inflating payloads to MBs.
# Fix: serialize each value independently (PSCustomObject piped directly = correct compact JSON)
# then assemble the CLEF event JSON by hand.
Add-Type -AssemblyName System.Net.Http -ErrorAction SilentlyContinue
try {
    $pairs = foreach ($key in $clefEvent.Keys) {
        $val = $clefEvent[$key]
        $kj  = $key | ConvertTo-Json   # safely escape any special chars in key
        if     ($null -eq $val)                               { "$kj`:null" }
        elseif ($val -is [bool])                              { "$kj`:" + $val.ToString().ToLower() }
        elseif ($val -is [int] -or $val -is [long])           { "$kj`:$val" }
        elseif ($val -is [string])                            { "$kj`:" + ($val | ConvertTo-Json) }
        elseif ($val -is [array])                             { "$kj`:" + ($val | ConvertTo-Json -Compress -Depth 3) }
        else                                                  { "$kj`:" + ($val | ConvertTo-Json -Compress -Depth 5) }
    }
    $body = '{' + ($pairs -join ',') + '}'
    $baseUrl = $seqConfig.serverUrl.TrimEnd('/')
    $uri     = "$baseUrl/ingest/clef"

    $client  = [System.Net.Http.HttpClient]::new()
    $client.Timeout = [System.TimeSpan]::FromSeconds(15)

    if (-not [string]::IsNullOrWhiteSpace($seqConfig.apiKey)) {
        $client.DefaultRequestHeaders.Add("X-Seq-ApiKey", $seqConfig.apiKey)
    }

    $content  = [System.Net.Http.StringContent]::new($body, [System.Text.Encoding]::UTF8, "application/vnd.serilog.clef")
    $response = $client.PostAsync($uri, $content).GetAwaiter().GetResult()
    $client.Dispose()

    if (-not $response.IsSuccessStatusCode) {
        $detail = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        Write-Host "[Swarm] emit failed ($EventType): HTTP $([int]$response.StatusCode) - $detail"
    }
} catch {
    Write-Host "[Swarm] emit failed ($EventType): $_"
}

exit 0
