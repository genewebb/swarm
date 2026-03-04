# Configuration Reference

All Swarm configuration lives in `.swarm/config/`. These files control which rules are active, how agents behave, and how the pipeline is decomposed.

---

## `standards.md`

**Location**: `.swarm/standards.md`
**Read by**: All agents (via context pack)
**Customize**: Yes — this is the most project-specific file

The project's ground truth for invariants, tooling, and rule group reference. Agents use it to understand what is non-negotiable for the project.

Required sections:

- `## Core Invariants` — numbered list of hard rules (no guessing, no EF, etc.)
- `## Rule Groups` — table mapping group IDs to descriptions and key rule IDs
- `## Tooling` — build command, test command, key libraries
- `## Tech Stack` — frameworks, patterns, constraints

---

## `policies.json`

**Location**: `.swarm/policies.json`
**Read by**: Manager
**Customize**: Yes

Controls git behavior, file access, PR creation, and loop limits.

```json
{
  "version": 1,
  "git": {
    "requireCleanWorkingTree": true,       // Block if uncommitted changes exist
    "allowUntrackedFiles": true,           // Allow untracked files at run start
    "branching": {
      "enabledByDefault": true,
      "branchPrefix": "swarm/",            // Branch names: swarm/{friendly-name}
      "worktreeNameTemplate": "{workspace}-swarm-{friendlyName}"
    },
    "commit": {
      "requireConventionalCommits": false,
      "signOff": false
    }
  },
  "loopControl": {
    "maxLoops": 3,                         // Max reviewer→implementor cycles
    "maxReplans": 2                        // Max times planner can be retried
  },
  "fileAccess": {
    "defaultPolicy": "deny",
    "allow": ["**/*"],                     // Globs agents MAY touch
    "deny": [                              // Globs agents must NEVER touch
      "**/.env", "**/.env.*",
      "**/*secret*", "**/*credentials*",
      "**/node_modules/**",
      "**/bin/**", "**/obj/**",
      "**/.git/**",
      "**/.swarm/runs/**"
    ],
    "requireAllowedFilesFromHandoff": true // Tighten scope at runtime
  },
  "commands": {
    "deny": ["rm -rf", "del /s", "sudo", "curl *| sh"],
    "allowNetwork": false
  },
  "qualityGates": {
    "requireReviewerApproval": true,
    "requireTestsPassBeforePR": true,
    "requireLintTypecheckIfConfigured": true
  },
  "pr": {
    "submitMethod": "manual",             // "manual", "gh", "glab", "bb"
    "baseBranch": "main",
    "createOnSuccess": true,
    "createDraft": false,
    "titleTemplate": "[swarm] {goal}",
    "bodyTemplate": "Goal: {goal}\n\nSummary:\n{summary}\n\nArtifacts:\n- Run folder: .swarm/runs/{runId}\n"
  }
}
```

---

## `config/construct-registry.json`

**Location**: `.swarm/config/construct-registry.json`
**Read by**: Manager (assembles context packs), Constraint Reviewer, Reviewer
**Customize**: Yes — add/remove/update rules for your project

Single source of truth for all rules, commands, MCP references, and skills. Each entry has:

```json
{
  "id": "rule.my_rule",
  "type": "rule",
  "summary": "One-sentence description shown in context packs",
  "sourcePath": ".cursor/rules/path/to/rule.mdc",
  "tags": ["architecture", "data"]
}
```

**Rule IDs** must match exactly what is referenced in `rule-groups.json`. Run `validate-swarm-config.ps1` after changes to verify consistency.

---

## `config/rule-groups.json`

**Location**: `.swarm/config/rule-groups.json`
**Read by**: Manager (determines which groups are active per task)
**Customize**: Yes — define groups and which pipeline phases can see them

```json
{
  "version": 1,
  "groups": [
    {
      "id": "core",
      "description": "Global invariants always active",
      "ruleIds": ["rule.no_guessing", "rule.clean_code_guidelines"],
      "plannerVisible": true,      // Core planner sees these
      "reviewerVisible": true,     // Constraint reviewer sees these
      "implementorVisible": true   // Implementor sees these
    },
    {
      "id": "service-architecture",
      "description": "DI, service registration, project structure",
      "ruleIds": ["rule.central_service_registration"],
      "plannerVisible": false,     // Planner does NOT see domain rules
      "reviewerVisible": true,
      "implementorVisible": true
    }
  ]
}
```

**Key principle**: The planner should only see `core`. Domain-specific groups (`service-architecture`, `data-access`, `ui-blazor`, `testing`, `documentation-formatting`) are visible to the constraint reviewer and implementor only.

**Active groups per run**: The manager derives `activeGroupIds` from the task type. Typically `["core", "documentation-formatting"]` for documentation tasks, all groups for code changes.

---

## `config/workflow.json`

**Location**: `.swarm/config/workflow.json`
**Read by**: Manager
**Customize**: Rarely — controls planner/reviewer/integrator settings

```json
{
  "version": 1,
  "planner": {
    "agent": "core-planner",
    "groupIds": ["core"]              // Planner only sees core rules
  },
  "constraintReview": {
    "agent": "constraint-reviewer",
    "parallel": false                 // Reviews run sequentially per group
  },
  "integrator": {
    "agent": "plan-integrator",
    "conflictResolutionPrecedence": [ // When groups conflict, higher = wins
      "core",
      "service-architecture",
      "data-access",
      "ui-blazor",
      "testing",
      "documentation-formatting"
    ]
  },
  "implementation": {
    "agent": "implementor",
    "ruleLoadStrategy": "task-triggered"
  },
  "fallback": {
    "collapseConstraintReviewWhenToolLacksSubagents": true
    // When true: skip constraint-reviewer chain if tool can't run subagents
  }
}
```

---

## `config/plan-decomposer.json`

**Location**: `.swarm/config/plan-decomposer.json`
**Read by**: Plan Decomposer
**Customize**: Tune decomposition thresholds

```json
{
  "version": 1,
  "decompositionStrategy": "core-then-areas",  // Primary strategy
  "fallbackStrategy": "by-lane",               // Used if primary fails
  "secondFallbackStrategy": "by-project",      // Last resort if fallback fails
  "triggerThreshold": {
    "minProjects": 5,    // Decompose if plan touches >= 5 projects
    "minSteps": 15       // Decompose if plan has >= 15 steps
  },
  "maxSubPlans": 3,                            // Hard cap; sub-plans merged to stay at or under
  "confirmDecompositionWithUser": true,        // Prompt user before decomposing
  "scope": "all-sln-in-repo",
  "checkpointing": { "mode": "batch-end" },
  "failureHandling": "halt-and-resume",
  "reviewCheckpoints": {
    "promptBetweenSubPlans": true   // Pause and ask you before each next sub-plan
  }
}
```

**Strategies** (applied in fallback order):

| Strategy | Behavior |
| --- | --- |
| `core-then-areas` | Identifies "core" projects via SolutionParser dependency graph; processes core first, then dependent areas |
| `by-lane` | One sub-plan per plan lane — the planner's natural grouping. Avoids one-sub-plan-per-project sprawl. Preferred fallback. |
| `by-project` | One sub-plan per project, in dependency order. Last resort only. |
| `by-solution` | One sub-plan per `.sln` file. |
| `by-dependency-order` | Build order; one project per sub-plan. |

**Key settings**:

- `maxSubPlans` — hard cap; if decomposition produces more sub-plans, the decomposer merges the smallest ones until at or under the cap
- `confirmDecompositionWithUser` — when `true`, the manager stops after plan validation if decomposition would trigger and presents a full prompt showing project/task/lane counts with three choices: **[1]** decompose as configured, **[2]** run as a single pass, **[3]** set a custom sub-plan cap. The manager does not proceed until you respond.
- `by-lane` fallback — uses the planner's own lane groupings as sub-plan boundaries; semantically correct and avoids sprawl

---

## `agents/manager/config.json`

**Location**: `.cursor/agents/manager/config.json`
**Read by**: Manager
**Customize**: Agent graph, branching, loop control, parallelization

```json
{
  "subagents": [...],           // Agent definitions with planPath and schemaPath
  "handoff-to": {               // Routing: which agents can follow which
    "core-planner": ["constraint-reviewer"],
    "reviewer": ["implementor", "tester"],
    ...
  },
  "loop-control": {
    "fromAgent": "reviewer",
    "toAgent": "implementor",
    "maxLoops": 3,
    "escalation-action": "needs-human"
  },
  "behavior": {
    "branching": {
      "enabled": true,
      "useCurrentBranch": true,       // true = stay on current branch
      "deferCommitToUser": true,       // true = don't auto-commit
      "worktreePathTemplate": ".swarm/worktrees/{friendly-name}"
    }
  },
  "parallelization": {
    "enabled": true,
    "rules": [{ "maxConcurrent": 4, "requireDisjointFiles": true }]
  }
}
```

---

## `config/tool-adapters/`

**Location**: `.swarm/config/tool-adapters/`
**Purpose**: Per-tool overrides

Each file is named for the tool (`cursor.json`, `vscode.json`, `claude-code.json`, `visualstudio.json`, `opencode.json`). Use `collapseConstraintReview: true` for tools that cannot run subagents — this collapses the constraint reviewer chain into a single pass.

---

## Seq Observability (Optional)

Swarm can emit structured events to [Seq](https://datalust.co/seq) for run visibility — no code changes required. Events are posted directly from the Manager using Seq's native CLEF ingestion API.

### Enable

Copy `swarm-template/config/seq.json` to `.swarm/config/seq.json` and configure:

```json
{
  "serverUrl": "http://localhost:5341",
  "apiKey": "",
  "enabled": true
}
```

| Field | Description |
| --- | --- |
| `serverUrl` | Seq base URL. Required when `enabled: true`. |
| `apiKey` | Optional. Passed as `X-Seq-ApiKey` header if non-empty. |
| `enabled` | When `false` or absent, no events are emitted. Default `false` in template. |

When the file is absent or `enabled: false`, Swarm runs exactly as it does today with no reporting.

### Events Emitted

The Manager calls `scripts/emit-seq-event.ps1` at three trigger points:

| Event type | When | `@l` level |
| --- | --- | --- |
| `run-started` | After the initial `run.status.json` is created | `Information` |
| `step-completed` | After each `handoff.json` is written | `Information` (or `Warning` for escalation outcomes) |
| `run-failed` | When `outcome: failed` is set | `Error` |

### CLEF Properties

All events include:

| Property | Value |
| --- | --- |
| `@t` | UTC timestamp from `run.status.json` |
| `@mt` | Message template (e.g. `"Swarm run {RunId} step {CurrentStep} completed, next {NextAgent}"`) |
| `@l` | `Information` / `Warning` / `Error` |
| `@sc` | `"Swarm"` (instrumentation scope) |
| `RunId` | Run GUID |
| `CurrentStep` | Agent name (e.g. `implementor`) |
| `Outcome` | `in-progress` / `completed` / `failed` / escalation |

Step-completed events additionally include:

| Property | Value |
| --- | --- |
| `NextAgent` | Target agent from `handoff.json` |
| `Step` | Handoff step number |
| `PhaseKey` | e.g. `implementor.subplan-2` |
| `SubPlanIndex` | Present when decomposition is active |
| `SubPlanTotal` | Present when decomposition is active |
| `ContextSummary` | Full `handoff.input` text (safety cap 2000 chars) |
| `FilesChanged` | Array from result file, capped at 20 items |

### Seq UI Filters

| Filter | Purpose |
| --- | --- |
| `@sc = 'Swarm'` | All Swarm events |
| `RunId = 'your-run-id'` | Single run |
| `CurrentStep = 'implementor'` | Step-specific events |
| `@l = 'Error'` | Failed runs |
| `@l = 'Warning'` | Escalated runs |

> **Note**: Use `@sc = 'Swarm'` not `SourceContext = 'Swarm'`. `@sc` is the CLEF instrumentation scope property; `SourceContext` is a Serilog library convention and will not match.

### Validation

`validate-swarm-config.ps1` validates `seq.json` when present: checks JSON syntax, and requires `serverUrl` to be non-empty and start with `http://` or `https://` when `enabled: true`.

---

## Running the Config Validator

After any changes to `construct-registry.json` or `rule-groups.json`:

```powershell
validate-swarm-config.ps1
```

After any changes to `construct-registry.json` or `rule-groups.json` that should be reflected in `CLAUDE.md` or `.github/copilot-instructions.md`:

```powershell
generate-tool-views.ps1
```
