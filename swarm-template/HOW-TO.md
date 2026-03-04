# Swarm Setup & Usage – How To

This document explains how to set up and use the Swarm workflow after pulling this repo. It assumes you are a developer cloning the repository for the first time.

---

## What Is the Swarm?

The **Swarm** is an AI agent workflow that automates tasks end-to-end. When you run `/swarm <task>`, the Manager orchestrates a pipeline:

1. **Plan** – A planner drafts a plan; constraint reviewers apply domain rules; an integrator merges them.
2. **Implement** – An implementor writes code in isolated steps.
3. **Review** – A reviewer checks conformance to project standards.
4. **Test** – A tester runs the test suite.
5. **Verify** – A verifier confirms the work is complete and functional.

On success, the Manager can push a branch and create a PR (when configured). If you run agents directly instead of `/swarm`, work stays local and you handle git yourself.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Cursor** | The Swarm is built for Cursor and its Task/subagent tool. |
| **PowerShell** | Required for config validation and tool-view generation. |
| **Git** | Clean working tree before runs; worktrees used when branching is enabled. |

---

## Setup Steps (After You Pull)

### Step 1: Verify the `.swarm` folder exists

After cloning, confirm these exist:

```
.swarm/
├── config/
│   ├── construct-registry.json   # All rules, commands, MCP refs, skills
│   ├── rule-groups.json         # Rule groups and phase visibility
│   ├── workflow.json            # Planner/reviewer/integrator settings and precedence
│   ├── plan-decomposer.json     # Decomposition threshold and strategy
│   └── tool-adapters/           # Per-tool configs (cursor, vscode, etc.)
├── runs/                        # Run artifacts (plans, handoffs, results)
├── standards.md                 # Project invariants and rule-group index
├── policies.json                # Git, file access, PR, loop control
└── HOW-TO.md                    # This file
```

If `.swarm/` is missing, the repo was not set up for Swarm. Ask the repo owner to add it or copy from a template.

### Step 2: Ensure required files are present

The Manager will stop if these are missing:

- **`.swarm/standards.md`** – Core invariants and rule reference. Must be human-authored and actionable.
- **`.swarm/policies.json`** – Git policy, file access, PR creation, loop limits.

Both are checked when you run `/swarm`. If either is missing, the Manager will escalate and ask you to create them.

### Step 3: Run the config validator (recommended)

Validate the Swarm config before your first run:

```powershell
validate-swarm-config.ps1
```

You should see: `Swarm config validation passed.`

If validation fails, fix the reported issues (e.g. orphan rule IDs, missing source paths). See `.cursor/documentation/your-project/builds/SwarmTroubleshooting.md` for common fixes.

### Step 4: Regenerate tool views (if you change rules or groups)

If you modify `.swarm/config/construct-registry.json` or `rule-groups.json`, regenerate tool-specific instruction files:

```powershell
generate-tool-views.ps1
```

This overwrites `CLAUDE.md`, `.github/copilot-instructions.md`, and `.vscode/VSCode-GUIDELINES.md`. Do not hand-edit these—they contain a `<!-- generated from .swarm/config -->` marker.

### Step 5: SolutionParser (required on PATH)

**SolutionParser.exe** is a required dependency for the **Plan Decomposer**. It discovers C# solutions and projects, builds the dependency graph, and identifies "core" projects. Install it separately and ensure `SolutionParser.exe` is available on your `PATH` before running `/swarm`.

**Manual usage** (to inspect your repo structure or test the tool):

```powershell
# From repo root – write output to .swarm
SolutionParser.exe --root . --output .swarm\solution-structure.json

# Or from any directory
SolutionParser.exe --root c:\path\to\your\repo --output .\solution-structure.json
```

Options:
- `--root <path>` – Root directory to search (default: current directory)
- `--output <path>` or `-o` – Write JSON to file (default: stdout)
- `--verbose` or `-v` – Enable debug logging

The output JSON contains `projects`, `dependencyGraph`, and `coreProjectNames`. The Plan Decomposer reads this to split large cross-project plans into ordered sub-plans (core first, then dependents).

If `SolutionParser.exe` is missing from `PATH`, `/swarm` cannot decompose large plans and should be treated as misconfigured.

### Step 6: Make Swarm scripts available

Swarm ships helper scripts that the Manager calls during runs. `emit-seq-event.ps1` must be resolvable when the Manager calls it. Either option works:

**Option A — Add the Swarm `scripts/` folder to your system PATH** (recommended if using Swarm across multiple projects):

Add `c:\path\to\swarm\scripts` to your `PATH`. The script will resolve from PATH in any project.

**Option B — Copy into your project's `scripts/` folder**:

```powershell
# From your project root
Copy-Item "c:\path\to\swarm\scripts\emit-seq-event.ps1" ".\scripts\emit-seq-event.ps1" -Force
```

If the script is not resolvable by either method, the Manager will log `[Seq] emit failed:` and continue — Seq observability is best-effort and never blocks a run.

### Step 7: No extra configuration needed

Rules, groups, and workflow are defined in config. The Manager reads `.cursor/agents/manager/config.json` for the agent graph and handoff flow. No environment variables or API keys are required for basic Swarm operation.

---

## How It Works

### Workflow graph

```
core-planner → constraint-reviewer (per group) → plan-integrator → [plan-decomposer] → implementor → reviewer ⇄ implementor → tester → verifier
```

- **core-planner** – Creates the initial plan using core invariants.
- **constraint-reviewer** – Applies domain rules (service-architecture, data-crud, UI, testing, docs) one group at a time.
- **plan-integrator** – Merges planner and constraint outputs into one execution plan.
- **plan-decomposer** – (Optional) When plans exceed size thresholds (projects or steps), runs **SolutionParser** and splits the plan into ordered sub-plans (core projects first). Configured in `.swarm/config/plan-decomposer.json`.
- **Review checkpoints between sub-plans** – When `.swarm/config/plan-decomposer.json` sets `reviewCheckpoints.promptBetweenSubPlans` to `true`, the Manager stops after each successful sub-plan except the last with `run.status.json.outcome = "paused-for-review"` and asks whether to continue to the next segment. Resume from `resumeSubPlanIndex`.
- **implementor** – Implements tasks from the plan.
- **reviewer** – Checks conformance; may send back to implementor for fixes.
- **tester** – Runs the test suite.
- **verifier** – Final validation; last step.

### Branching and PRs

- **`useCurrentBranch: true`** – Work happens on your current branch; no worktree, no push, no PR. You commit and push yourself.
- **`useCurrentBranch: false`** – Each run gets its own worktree and branch (`swarm/<friendly-name>`). On success, the Manager pushes and can create a PR (if `pr.submitMethod` allows).
- **`deferCommitToUser: true`** – Implementor does not commit; you review and commit manually.

These live in `.cursor/agents/manager/config.json` under `behavior.branching`.

### Rules and context

- Rules come from **`.swarm/config/construct-registry.json`** and **`rule-groups.json`**.
- Agents load rules by **`activeGroupIds`** only—not the full `.cursor/rules/` tree.
- Planner sees only `core`; implementor and reviewer see the groups enabled for their phase.

---

## Areas to Customize

These are the main places to adjust behavior for your team or project.

### 1. `.swarm/standards.md`

- **Purpose**: Project invariants and rule-group reference.
- **Customize**: Add or change core invariants. Update the group table if you add rule groups.
- **When**: When onboarding new constraints or changing project-wide rules.

### 2. `.swarm/policies.json`

| Section | What to change |
|---------|----------------|
| `fileAccess.allow` / `fileAccess.deny` | Globs for files agents may or may not touch. |
| `pr.submitMethod` | `"manual"` (you create PRs), `"gh"`, `"glab"`, or `"bb"`. |
| `pr.baseBranch` | Target branch for PRs (e.g. `main`, `develop`). |
| `loopControl.maxLoops` | Max reviewer → implementor cycles before escalation. |
| `commands.deny` | Commands agents must not run. |

### 3. `.swarm/config/construct-registry.json`

- **Purpose**: Single registry of all rules, commands, MCP references, skills.
- **Customize**: Add new rules (with `sourcePath` to `.mdc` file), commands (with path to command `.md`), or skills (external references).
- **Rule**: Every `ruleId` in `rule-groups.json` must exist here. Run the validator after changes.

### 4. `.swarm/config/rule-groups.json`

- **Purpose**: Group definitions and which phases see each group.
- **Customize**: Add groups, assign rules, toggle `plannerVisible`, `reviewerVisible`, `implementorVisible`.
- **Note**: Planner usually sees only `core`; other groups drive implementor and reviewer.

### 5. `.cursor/agents/manager/config.json`

- **Purpose**: Agent graph, handoff flow, branching, loop control.
- **Customize**: Add/remove agents, change `handoff-to`, set `behavior.branching`, adjust `loop-control`, enable parallelization.
- **Important**: The workflow is driven entirely by this file.

### 6. `.swarm/config/workflow.json`

- **Purpose**: Planner agent, constraint reviewer, integrator, precedence, and fallback behavior.
- **Customize**: Change planner/constraint reviewer agent IDs; adjust `integrator.conflictResolutionPrecedence`; set `collapseConstraintReviewWhenToolLacksSubagents` for tools without subagent support.

### 7. `.swarm/config/plan-decomposer.json`

- **Purpose**: Decomposition thresholds, strategy, failure handling, and optional human review checkpoints between sub-plans.
- **Customize**: Tune `triggerThreshold`, change `decompositionStrategy`, or toggle `reviewCheckpoints.promptBetweenSubPlans`.
- **Note**: When checkpoints are enabled, the Manager pauses after each successful sub-plan except the last, asks whether to continue, and resumes paused runs from `resumeSubPlanIndex`.

### 8. `.swarm/config/tool-adapters/`

- **Purpose**: Per-tool configs (Cursor, VS Code, Visual Studio, etc.).
- **Customize**: Enable fallback mode (`collapseConstraintReview: true`) when your tool cannot run subagents.

### 9. `.cursor/rules/` (rule content)

- **Purpose**: Actual rule prose in `.mdc` files.
- **Customize**: Edit rule content; ensure `construct-registry.json` and `rule-groups.json` stay in sync.
- **Rule**: Never hard-code rule loading from the full tree—use `activeGroupIds` only.

---

## Common Commands

| Action | Command |
|--------|---------|
| Run a task | `/swarm` then describe the task (or use `/swarm <task>`) |
| Validate config | `validate-swarm-config.ps1` |
| Regenerate tool views | `generate-tool-views.ps1` |
| Generate solution structure | `SolutionParser.exe --root . --output .swarm\solution-structure.json` |
| Init only (no run) | `/swarm init` or "swarm init" – creates `.swarm/` structure, stops before running agents |

---

## Troubleshooting

- **Orphan ruleId**: Rule in `rule-groups.json` not in `construct-registry.json` → add or fix the construct ID.
- **sourcePath not found**: Rule’s `.mdc` path wrong or file moved → update `sourcePath` in registry.
- **Manager stops with "needs-human"**: Check `standards.md` and `policies.json`; fix missing or placeholder content.
- **No push/PR**: Ensure `behavior.branching.useCurrentBranch` is `false` and `pr.submitMethod` is set correctly.

Full troubleshooting guide: `.cursor/documentation/your-project/builds/SwarmTroubleshooting.md`

---

## Summary

1. **Install** `SolutionParser.exe` and ensure it is on `PATH`.
2. **Confirm** `.swarm/`, `standards.md`, and `policies.json` exist.
3. **Run** `validate-swarm-config.ps1`.
4. **Use** `/swarm <task>` to run the full workflow (plan-decomposer uses SolutionParser when plans exceed size thresholds).
5. **Customize** standards, policies, rules, groups, and manager config as needed.
