# Overview — How the Swarm Works

## The Pipeline

The Swarm runs a deterministic sequence of specialized agents. Each agent completes one job, writes a result artifact, and hands off to the next. The Manager orchestrates the entire sequence.

```text
core-planner
    ↓
constraint-reviewer  (once per active rule group, chained)
    ↓
plan-integrator
    ↓
plan-decomposer      (splits large plans into sub-plans)
    ↓
implementor          ←──────────────┐
    ↓                               │ (if issues found, up to 3 loops)
reviewer  ───────────────────────────┘
    ↓
tester
    ↓
verifier
```

---

## Agent Roles

### Manager

The orchestrator. Reads `manager/config.json` for the agent graph, assembles a **context pack** for each handoff, tracks run state in `run.status.json`, and routes agents in sequence. All agents communicate through JSON handoff files written to `.swarm/runs/{runId}/`.

### Core Planner

Produces the initial draft plan using **core invariants only**. Scans allowed files, organizes tasks into lanes, and writes `plan.json`. It does not apply domain-specific rules — that is the constraint reviewer's job.

### Constraint Reviewer

Applies **one rule group** per pass to the draft plan. Emits `annotate` (informational) or `modify` (required change) actions. The Manager chains passes for each active group. Only groups in `activeGroupIds` are reviewed — never the full registry.

### Plan Integrator

Merges the draft plan with all constraint-reviewer outputs into a single integrated execution plan (`integrated-plan.md`). **Scope preservation is mandatory** — it cannot add files, remove files, or restructure tasks. It only applies explicit `modify` actions from reviewers.

### Plan Decomposer

When a plan exceeds size thresholds (`minProjects` / `minSteps`), splits it into ordered sub-plans. Uses **SolutionParser** to analyze the dependency graph and group files. `context.allowedFiles` from the handoff is the authoritative file list — SolutionParser is used for grouping only, never for expanding scope.

Decomposition strategy: `core-then-areas` (primary) → `by-lane` (fallback; uses the planner's own lane groupings) → `by-project` (last resort). `maxSubPlans` caps the number of sub-plans regardless of strategy; sub-plans are merged down to stay at or under the cap.

When `confirmDecompositionWithUser: true`, the Manager stops after plan validation if decomposition would trigger and shows you this prompt:

```
⚙️ Swarm — Decomposition gate
Plan has X projects, Y tasks, and Z lanes.
With current settings this will be split into up to N sub-plans.
How would you like to proceed?

[1] Continue — decompose as configured (up to N sub-plans)
[2] Run as single pass — skip decomposition entirely
[3] Set a different sub-plan cap — reply with 3 <number>

Reply with 1, 2, or 3.
```

The Manager does not invoke plan-decomposer until you respond.

### Implementor

Executes tasks from the scoped plan. Reads each file, applies only the changes described in the plan, and writes `implementor.result.json` with `filesChanged`. When `deferCommitToUser` is true, it does **not** commit — you commit manually after reviewing.

### Reviewer

Verifies the implementor's changes against the plan and project standards. Returns `approved` (proceeds to tester) or `rejected` (loops back to implementor with specific issues). Maximum 3 loops before escalating to human.

### Tester

Runs **only test files that appear in `filesChanged`** — never the full test suite. If no new test files were added or modified, reports `skipped`. The full `dotnet test` suite is run by you after the entire swarm completes.

### Verifier

Final checkpoint. Runs `dotnet build` to confirm compilation, spot-checks that changes match the plan, and sets a `passed` or `failed` verdict. Does not run the full test suite.

---

## Run Artifacts

Every run writes artifacts to `.swarm/runs/{runId}/`:

| File | Written by | Contents |
| --- | --- | --- |
| `run.status.json` | Manager | Current stage, timestamps, outcome |
| `context.pack.md` | Manager | Goal, rules, allowed files, system map |
| `handoff.json` | Manager | Current handoff input |
| `handoff.step-N.{agent}.json` | Manager | Per-step handoff history |
| `plan.json` | Core Planner | Draft plan |
| `constraint-reviewer.{group}.result.json` | Constraint Reviewer | Per-group review result |
| `integrated-plan.md` | Plan Integrator | Final merged plan |
| `subplans.manifest.json` | Plan Decomposer | Sub-plan list and scopes |
| `scoped-plan-N.md` | Plan Decomposer | Per-sub-plan task list |
| `solution-structure.json` | Plan Decomposer | SolutionParser output |
| `implementor.result.json` | Implementor | Summary + filesChanged |
| `reviewer.result.json` | Reviewer | Verdict + issues |
| `tester.result.json` | Tester | Test status (passed/skipped/failed) |
| `verifier.result.json` | Verifier | Final verdict |

---

## Scope Control

The most important concept in the Swarm is **scope**. Agents are only allowed to touch files matching the patterns in `context.allowedFiles`. This propagates from the context pack through every handoff.

The Manager derives `allowedFiles` from the first matching source (in priority order):

1. **Task spec file** — `.swarm/tasks/{friendly-name}.md` → `## Allowed Files` section
2. **Prior handoff** — `context.allowedFiles` from a previous handoff (e.g. resuming)
3. **Input MD file** — if the task was invoked as a file path, read patterns from it
4. **Named projects in the task description** — converts to glob patterns
5. **Escalate** — if scope cannot be determined, the Manager stops and asks you

**Task spec `## Out of Scope` is a hard Forbidden list.** When a task spec file is found, any project, path, or pattern in its `## Out of Scope` section is written as a Forbidden entry in the context pack. The planner cannot include those files regardless of apparent relevance. The `## Allowed Files` patterns are copied verbatim — the Manager never adds patterns that are not explicitly listed there.

After the planner produces `plan.json`, the Manager validates every file in the plan against the Forbidden and Allowed lists. Any violation triggers an immediate replanning request — the plan is rejected before constraint-review begins.

See [04-writing-tasks.md](04-writing-tasks.md) for how to author task spec files.

---

## Branching Modes

Configured in `agents/manager/config.json` under `behavior.branching`:

| Setting | Behavior |
| --- | --- |
| `useCurrentBranch: true` | Work on your current branch. No worktree, no auto-push, no PR. You commit manually. |
| `useCurrentBranch: false` | Each run gets its own git worktree on `swarm/{friendly-name}`. Auto-push and PR on success. |
| `deferCommitToUser: true` | Implementor does not commit. You review changes and commit yourself. |

---

## Loop Control

| Situation | Behavior |
| --- | --- |
| Reviewer rejects implementor | Loops back up to `maxLoops` (default 3) times |
| Plan fails validation | Replans up to `maxReplans` (default 1) times |
| Either limit exceeded | Escalates with `needs-human` outcome |

---

## Sub-Plan Checkpoints

When a plan is split into multiple sub-plans, the Manager stops **before running any of them** and shows you this prompt:

```
⚙️ Swarm — Sub-plan review
Plan decomposed into N sub-plans: Label1, Label2, …

[Yes] Pause after each sub-plan completes so you can review before continuing
[No]  Run all sub-plans straight through without stopping

Pause between sub-plans? Reply Yes or No.
```

- **Yes** — after each sub-plan completes (except the last), the Manager stops and asks you to confirm before continuing to the next.
- **No** — all sub-plans run straight through without interruption.

This runtime answer overrides the `reviewCheckpoints.promptBetweenSubPlans` config setting for the current run.
