<#
.SYNOPSIS
  Generates tool-specific instruction files from the canonical .swarm/config registry.

.DESCRIPTION
  Reads construct-registry.json and rule-groups.json, then emits:
  - .github/copilot-instructions.md (shared by VS Code and Visual Studio)
  - .vscode/VSCode-GUIDELINES.md
  - CLAUDE.md (Claude Code; kept under 200 lines)

.PARAMETER DryRun
  Write output to console instead of files.

.PARAMETER WorkspaceRoot
  Root of the repo that has .swarm/ (default: parent of scripts dir). Required when the script
  is not located under the repo root (e.g. running from an external scripts directory).

.EXAMPLE
  .\generate-tool-views.ps1 -WorkspaceRoot "c:\path\to\your-repo"

.EXAMPLE
  .\scripts\generate-tool-views.ps1
#>
param([switch]$DryRun, [string]$WorkspaceRoot)

$ErrorActionPreference = "Stop"
$RepoRoot = if ($WorkspaceRoot) { Resolve-Path $WorkspaceRoot } elseif ($PSScriptRoot) { Resolve-Path (Join-Path $PSScriptRoot "..") } else { Get-Location }

$registryPath = Join-Path $RepoRoot ".swarm/config/construct-registry.json"
$groupsPath = Join-Path $RepoRoot ".swarm/config/rule-groups.json"

if (-not (Test-Path $registryPath)) { throw "Registry not found: $registryPath" }
if (-not (Test-Path $groupsPath)) { throw "Groups not found: $groupsPath" }

$registry = Get-Content $registryPath -Raw | ConvertFrom-Json
$groups = Get-Content $groupsPath -Raw | ConvertFrom-Json

$ruleById = @{}
foreach ($c in $registry.constructs) {
    if ($c.type -eq "rule" -or $c.type -eq "mcp-reference") {
        $ruleById[$c.id] = $c
    }
}

$groupPrecedence = @("core", "service-architecture", "data-access", "ui-blazor", "testing", "documentation-formatting")

function Get-CoreRulesSummary {
    $coreGroup = $groups.groups | Where-Object { $_.id -eq "core" }
    if (-not $coreGroup) { return "" }
    $lines = @()
    foreach ($rid in $coreGroup.ruleIds) {
        $r = $ruleById[$rid]
        if ($r) { $lines += "- **$($r.id)**: $($r.summary)" }
    }
    return $lines -join "`n"
}

function Get-GroupSummaries {
    $lines = @()
    foreach ($gid in $groupPrecedence) {
        $g = $groups.groups | Where-Object { $_.id -eq $gid }
        if (-not $g) { continue }
        $ruleCount = ($g.ruleIds | Where-Object { $ruleById.ContainsKey($_) }).Count
        $keyRules = ($g.ruleIds | Where-Object { $ruleById.ContainsKey($_) } | Select-Object -First 5) -join ", "
        $lines += "- **$($g.id)**: $($g.description) ($ruleCount rules; key: $keyRules)"
    }
    return $lines -join "`n"
}

$header = "<!-- generated from .swarm/config -->`n"

# --- CLAUDE.md (under 200 lines) ---
$claudeCore = @"
## Core Invariants (from registry)

- **No guessing** – Verify before proceeding; state unknowns explicitly
- **Only change relevant code** – No placeholders or incomplete code
- **Clean code** – DRY, meaningful names, single responsibility, error handling
- **Domain values** – Fetch from database or config; never hard-code
- **Newtonsoft.Json** – Use exclusively; no System.Text.Json in application code
- **No Entity Framework** – Use IRestClient, repositories, SqlHelper

## Active Rule Groups

$(Get-GroupSummaries)

## Operational Policy

- **Build**: `dotnet build`
- **Tests**: `dotnet test`
- **Registry**: `.swarm/config/construct-registry.json`
- **Groups**: `.swarm/config/rule-groups.json`
"@

$claudeContent = $header + "# Claude Code Instructions`n`n" + $claudeCore
$claudeLines = ($claudeContent -split "`n").Count
if ($claudeLines -gt 200) {
    Write-Warning "CLAUDE.md exceeds 200 lines ($claudeLines); trimming informational rules"
}

# --- Copilot / VS Code instructions (full summary) ---
$copilotCore = @"
## Core Invariants

$(Get-CoreRulesSummary)

## Rule Groups (from .swarm/config)

$(Get-GroupSummaries)

## Code Style & Architecture

- Follow clean architecture; services in BusinessLogic/Services/, DTOs in Common/DTOs/
- No inline or nested classes; each class in its own file
- Use PascalCase for public members; camelCase for private fields
- Keep controllers thin; orchestration in services

## Technology Stack

### Logging
- Use **Serilog.ILogger**, NOT Microsoft.Extensions.Logging.ILogger
- Structured logging with named properties; never log secrets or PII

### JSON
- **Newtonsoft.Json exclusively**; no System.Text.Json in application code
- Convert JsonElement to JToken/JObject when needed

### Data Access
- **No Entity Framework**; use IRestClient, repositories, SqlHelper
- Follow Entity/Attribute framework patterns

### Blazor
- Use `.razor` + partial `.razor.cs` for non-trivial components
- Code-behind separation; no IRestClient in pages
- Material Symbols only (no Bootstrap icons)

### Testing
- **MSTest** with [TestClass]/[TestMethod]; **bUnit** for Blazor
- Arrange-Act-Assert; name tests: MethodName_Scenario_ExpectedBehavior

## What NOT To Do

- Do NOT use Entity Framework, System.Text.Json, or ILogger
- Do NOT create inline/nested classes or hard-code domain values
- Do NOT use async void (except event handlers)
"@

$copilotContent = $header + "# GitHub Copilot Instructions`n`nThese instructions guide GitHub Copilot when working in this repository.`n`n" + $copilotCore

# --- VSCode-GUIDELINES ---
$vscodeContent = $header + "# VS Code Workspace Guidelines`n`nThis document is generated from `.swarm/config`. It mirrors the Cursor rules for VS Code developers.`n`n" + $copilotCore

# --- Write or dry-run ---
$outputs = @(
    @{ Path = "CLAUDE.md"; Content = $claudeContent }
    @{ Path = ".github/copilot-instructions.md"; Content = $copilotContent }
    @{ Path = ".vscode/VSCode-GUIDELINES.md"; Content = $vscodeContent }
)

foreach ($o in $outputs) {
    $fullPath = Join-Path $RepoRoot $o.Path
    if ($DryRun) {
        Write-Host "`n--- $($o.Path) ---" -ForegroundColor Cyan
        Write-Host $o.Content
        Write-Host "`n(Lines: $(($o.Content -split "`n").Count))"
    } else {
        $dir = Split-Path $fullPath -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $o.Content | Set-Content -Path $fullPath -Encoding UTF8
        Write-Host "Generated: $($o.Path)" -ForegroundColor Green
    }
}

if (-not $DryRun) {
    Write-Host "`nTool view generation complete. Run validate-swarm-config.ps1 to verify." -ForegroundColor Green
}
