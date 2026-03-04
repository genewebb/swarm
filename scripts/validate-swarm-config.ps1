<#
.SYNOPSIS
  Validates all .swarm/config files before manager startup or CI merge.

.DESCRIPTION
  Ensures construct-registry, rule-groups, workflow, tool-adapters, and policies
  conform to the canonical schema. Run on CI when .swarm/** changes.

.PARAMETER DryRun
  Report errors without exiting non-zero. For local development only.

.PARAMETER WarnOnly
  Downgrade generated-file and CLAUDE.md checks to warnings (use during migration before Step 9).

.PARAMETER WorkspaceRoot
  Root of a repo that has .swarm/ (default: parent of scripts dir). Use to validate a different repo.

.EXAMPLE
  .\scripts\validate-swarm-config.ps1 -WarnOnly

.EXAMPLE
  .\scripts\validate-swarm-config.ps1 -WorkspaceRoot "c:\path\to\your-repo"
#>
param([switch]$DryRun, [switch]$WarnOnly, [string]$WorkspaceRoot)

$ErrorCount = 0
$RepoRoot   = if ($WorkspaceRoot) { Resolve-Path $WorkspaceRoot } elseif ($PSScriptRoot) { Resolve-Path (Join-Path $PSScriptRoot "..") } else { Get-Location }

function Fail([string]$msg) {
    Write-Error "VALIDATION FAIL: $msg"
    $script:ErrorCount++
}

function Get-RequiredFile([string]$rel) {
    $path = Join-Path $RepoRoot $rel
    if (-not (Test-Path $path)) {
        Fail "Required file missing: $rel"
        return $null
    }
    return $path
}

# --- construct-registry.json ---
$registryPath = Get-RequiredFile ".swarm/config/construct-registry.json"
$allIds = @{}
if ($registryPath) {
    try {
        $registry = Get-Content $registryPath -Raw | ConvertFrom-Json
    } catch {
        Fail "construct-registry.json: invalid JSON - $_"
    }
    if ($registry) {
        if ($null -eq $registry.version)    { Fail "construct-registry.json: missing version" }
        if ($null -eq $registry.constructs) { Fail "construct-registry.json: missing constructs array" }
        foreach ($c in $registry.constructs) {
            if ($allIds.ContainsKey($c.id)) { Fail "construct-registry.json: duplicate id '$($c.id)'" }
            $allIds[$c.id] = $c
            if ($c.type -in @("rule","mcp-reference") -and $c.sourcePath) {
                $srcPath = Join-Path $RepoRoot $c.sourcePath
                if (-not (Test-Path $srcPath)) {
                    Fail "construct-registry.json: sourcePath not found for '$($c.id)': $($c.sourcePath)"
                }
            }
            $validScopes = @("core","domain","operator","meta")
            if ($c.scope -and $c.scope -notin $validScopes) {
                Fail "construct-registry.json: invalid scope '$($c.scope)' on '$($c.id)'"
            }
            $validTypes = @("rule","policy","command","skill","agent-prompt","meta","mcp-reference")
            if ($c.type -notin $validTypes) {
                Fail "construct-registry.json: invalid type '$($c.type)' on '$($c.id)'"
            }
            if ($c.type -in @("rule","mcp-reference")) {
                if (-not $c.phases -or $c.phases.Count -eq 0) {
                    Fail "construct-registry.json: phases array must be non-empty for '$($c.id)'"
                } else {
                    $validPhases = @("planning","implementation","review","verify","invoke")
                    foreach ($p in $c.phases) {
                        if ($p -notin $validPhases) {
                            Fail "construct-registry.json: invalid phase '$p' on '$($c.id)'"
                        }
                    }
                }
            }
        }
    }
}

# --- rule-groups.json ---
$groupsPath = Get-RequiredFile ".swarm/config/rule-groups.json"
$coreGroupCount = 0
if ($groupsPath) {
    try {
        $groups = Get-Content $groupsPath -Raw | ConvertFrom-Json
    } catch {
        Fail "rule-groups.json: invalid JSON - $_"
    }
    if ($groups -and $groups.groups) {
        foreach ($g in $groups.groups) {
            if ($g.id -eq "core") { $coreGroupCount++ }
            if ($g.ruleIds) {
                foreach ($rid in $g.ruleIds) {
                    if ($allIds.Count -gt 0 -and -not $allIds.ContainsKey($rid)) {
                        Fail "rule-groups.json: orphan ruleId '$rid' in group '$($g.id)'"
                    }
                }
            }
            $visible = $g.plannerVisible -or $g.reviewerVisible -or $g.implementorVisible
            if (-not $visible) { Fail "rule-groups.json: group '$($g.id)' is never visible (all visibility flags false)" }
        }
        if ($coreGroupCount -ne 1) { Fail "rule-groups.json: exactly one group must have id 'core' (found $coreGroupCount)" }
    }
}

# --- workflow.json ---
$workflowPath = Get-RequiredFile ".swarm/config/workflow.json"
if ($workflowPath) {
    try {
        $workflow = Get-Content $workflowPath -Raw | ConvertFrom-Json
    } catch {
        Fail "workflow.json: invalid JSON - $_"
    }
    if ($workflow) {
        foreach ($field in @("planner","constraintReview","integrator","implementation","fallback")) {
            if ($null -eq $workflow.PSObject.Properties[$field]) { Fail "workflow.json: missing required section '$field'" }
        }
        if ($workflow.planner -and "core" -notin $workflow.planner.groupIds) {
            Fail "workflow.json: planner.groupIds must include 'core'"
        }
        if ($workflow.constraintReview -and $workflow.constraintReview.parallel -eq $true) {
            Write-Warning "workflow.json: constraintReview.parallel is true; this is a v-next feature. Use false for Phase 1."
        }
    }
}

# --- tool adapters ---
$adaptersPath = Join-Path $RepoRoot ".swarm/config/tool-adapters"
if (Test-Path $adaptersPath) {
    $validTools = @("cursor","vscode","visualstudio","opencode","claude-code")
    Get-ChildItem (Join-Path $adaptersPath "*.json") -ErrorAction SilentlyContinue | ForEach-Object {
        try {
            $adapter = Get-Content $_.FullName -Raw | ConvertFrom-Json
        } catch {
            Fail "$($_.Name): invalid JSON - $_"
            return
        }
        if ($adapter.tool -notin $validTools) { Fail "$($_.Name): unknown tool '$($adapter.tool)'" }
        if ($adapter.tool -eq "cursor" -and $adapter.managerConfigPath) {
            $mgrPath = Join-Path $RepoRoot $adapter.managerConfigPath
            if (-not (Test-Path $mgrPath)) {
                Fail "$($_.Name): managerConfigPath not found: $($adapter.managerConfigPath)"
            }
        }
        if ($adapter.tool -eq "claude-code") {
            if ($adapter.instructionSurface -ne "CLAUDE.md") {
                Fail "$($_.Name): instructionSurface must be 'CLAUDE.md'"
            }
            $claudePath = Join-Path $RepoRoot "CLAUDE.md"
            if (-not (Test-Path $claudePath)) {
                if ($WarnOnly) {
                    Write-Warning "$($_.Name): CLAUDE.md not found at repo root (expected during migration; create in Step 9)"
                } else {
                    Fail "$($_.Name): CLAUDE.md not found at repo root"
                }
            }
        }
    }
} else {
    Fail "Tool adapters directory missing: .swarm/config/tool-adapters/"
}

# --- policies.json ---
$policiesPath = Get-RequiredFile ".swarm/policies.json"
if ($policiesPath) {
    try {
        $policies = Get-Content $policiesPath -Raw | ConvertFrom-Json
    } catch {
        Fail "policies.json: invalid JSON - $_"
    }
    if ($policies) {
        if ($null -eq $policies.version) { Fail "policies.json: missing version" }
        if ($policies.standards -and $policies.standards.path) {
            $stdPath = Join-Path $RepoRoot $policies.standards.path
            if (-not (Test-Path $stdPath)) {
                Fail "policies.json: standards.path not found: $($policies.standards.path)"
            }
        }
    }
}

# --- plan-decomposer.json (Step 11+; optional until Phase 2) ---
$decomposerPath = Join-Path $RepoRoot ".swarm/config/plan-decomposer.json"
if (Test-Path $decomposerPath) {
    try {
        $decomposer = Get-Content $decomposerPath -Raw | ConvertFrom-Json
    } catch {
        Fail "plan-decomposer.json: invalid JSON - $_"
    }
    if ($decomposer) {
        if ($null -eq $decomposer.version)  { Fail "plan-decomposer.json: missing version" }
        $validStrategies = @("core-then-areas", "by-lane", "by-project", "by-solution", "by-dependency-order")
        if ($decomposer.decompositionStrategy -notin $validStrategies) {
            Fail "plan-decomposer.json: invalid decompositionStrategy '$($decomposer.decompositionStrategy)'"
        }
        if ($null -ne $decomposer.fallbackStrategy -and $decomposer.fallbackStrategy -notin $validStrategies) {
            Fail "plan-decomposer.json: invalid fallbackStrategy '$($decomposer.fallbackStrategy)'"
        }
        if ($null -eq $decomposer.triggerThreshold -or $decomposer.triggerThreshold.minProjects -le 0 -or $decomposer.triggerThreshold.minSteps -le 0) {
            Fail "plan-decomposer.json: triggerThreshold.minProjects and triggerThreshold.minSteps must be positive integers"
        }
        $validScopes = @("all-sln-in-repo", "single-sln", "explicit-projects")
        if ($decomposer.scope -and $decomposer.scope -notin $validScopes) {
            Fail "plan-decomposer.json: invalid scope '$($decomposer.scope)'"
        }
        $validCheckpointModes = @("batch-end", "per-subplan", "none")
        if ($decomposer.checkpointing -is [string]) {
            Fail "plan-decomposer.json: 'checkpointing' must be an object { ""mode"": ""batch-end"" }, not a bare string"
        } elseif ($decomposer.checkpointing -and $decomposer.checkpointing.mode -notin $validCheckpointModes) {
            Fail "plan-decomposer.json: invalid checkpointing.mode '$($decomposer.checkpointing.mode)'"
        }
    }
} elseif ($WarnOnly) {
    Write-Warning "plan-decomposer.json not found - expected before Step 11 (plan decomposer not yet implemented)"
}

# --- seq.json (optional - only validate if present) ---
$seqPath = Join-Path $RepoRoot ".swarm/config/seq.json"
if (Test-Path $seqPath) {
    try {
        $seq = Get-Content $seqPath -Raw | ConvertFrom-Json
    } catch {
        Fail "seq.json: invalid JSON - $_"
        $seq = $null
    }
    if ($seq) {
        if ($seq.enabled -eq $true -and [string]::IsNullOrWhiteSpace($seq.serverUrl)) {
            Fail "seq.json: 'enabled' is true but 'serverUrl' is empty"
        }
        if ($seq.PSObject.Properties['serverUrl'] -and
            -not [string]::IsNullOrWhiteSpace($seq.serverUrl) -and
            $seq.serverUrl -notmatch '^https?://') {
            Fail "seq.json: 'serverUrl' must start with http:// or https://"
        }
    }
}

# --- generated files staleness (WarnOnly during migration) ---
if (-not $WarnOnly) {
    foreach ($gen in @(
        @{ Path = ".github/copilot-instructions.md"; Marker = "<!-- generated from .swarm/config -->" }
        @{ Path = ".vscode/VSCode-GUIDELINES.md"; Marker = "<!-- generated from .swarm/config -->" }
        @{ Path = "CLAUDE.md"; Marker = "<!-- generated from .swarm/config -->"; MaxLines = 200 }
    )) {
        $fp = Join-Path $RepoRoot $gen.Path
        if (Test-Path $fp) {
            $content = Get-Content $fp -Raw
            if ($content -notmatch [regex]::Escape($gen.Marker)) {
                Fail "$($gen.Path): missing generated marker; file may be stale or hand-edited"
            }
            if ($gen.MaxLines) {
                $lines = (Get-Content $fp).Count
                if ($lines -gt $gen.MaxLines) {
                    Fail "$($gen.Path): exceeds $($gen.MaxLines) lines (found $lines)"
                }
            }
        }
    }
} else {
    $claudePath = Join-Path $RepoRoot "CLAUDE.md"
    if (-not (Test-Path $claudePath)) {
        Write-Warning "CLAUDE.md not found - expected during migration; create in Step 9"
    }
}

# --- result ---
if ($ErrorCount -gt 0 -and -not $DryRun) {
    Write-Error "$ErrorCount validation error(s). Fix before proceeding."
    exit 1
} elseif ($ErrorCount -gt 0) {
    Write-Warning "$ErrorCount validation error(s) found (dry-run; not failing)."
} else {
    Write-Host "Swarm config validation passed." -ForegroundColor Green
}
