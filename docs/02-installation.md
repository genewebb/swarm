# Installation Guide

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| **Cursor or VS Code** | Swarm is built for AI-assisted editors with subagent support |
| **PowerShell** | Required for `validate-swarm-config.ps1` and `generate-tool-views.ps1` |
| **Git** | Clean working tree before running. Worktrees used when branching is enabled. |
| **.NET 8 SDK** | Required to build SolutionParser |

---

## Step 1 — Copy the Swarm Template Into Your Repo

From this package, copy `swarm-template/` into your repo root as `.swarm/`:

```powershell
# From this package root
Copy-Item -Recurse swarm-template "C:\path\to\your-repo\.swarm"
```

Copy `agents/` into your repo as `.cursor/agents/`:

```powershell
Copy-Item -Recurse agents "C:\path\to\your-repo\.cursor\agents"
```

After copying, your repo should have:

```
your-repo/
├── .swarm/
│   ├── standards.md
│   ├── policies.json
│   ├── HOW-TO.md
│   ├── tasks/
│   └── config/
│       ├── construct-registry.json
│       ├── rule-groups.json
│       ├── workflow.json
│       ├── plan-decomposer.json
│       └── tool-adapters/
└── .cursor/
    └── agents/
        ├── manager.md
        ├── manager/config.json
        ├── core-planner.md
        └── ... (all other agents)
```

---

## Step 2 — Edit `standards.md`

This is the most important customization step. Open `.swarm/standards.md` and update it for your project:

- **Core Invariants** — add your project's non-negotiable rules (e.g. "Use Newtonsoft.Json", "No Entity Framework")
- **Rule Groups** — update the table to match the groups in `construct-registry.json`
- **Tooling** — set correct build and test commands for your stack
- **Tech Stack** — describe your frameworks, patterns, and constraints

The file included in this package is the `your-project` project's `standards.md` — use it as a reference but replace everything project-specific.

---

## Step 3 — Edit `policies.json`

Review and update key settings:

```json
{
  "git": {
    "branching": {
      "enabledByDefault": true
    }
  }
}
```

Key settings to review:

| Setting | Default | Description |
|---------|---------|-------------|
| `git.requireCleanWorkingTree` | `true` | Swarm won't start with uncommitted changes |
| `git.branching.enabledByDefault` | `true` | Whether to create a new branch per run |
| `git.commit.requireConventionalCommits` | `false` | Enforce conventional commit format |
| `pr.submitMethod` | `"manual"` | `"manual"` = you create PR; `"gh"` = GitHub CLI |
| `pr.baseBranch` | `"main"` | Target branch for PRs |
| `loopControl.maxLoops` | `3` | Max reviewer→implementor fix cycles |
| `fileAccess.deny` | (list) | Paths agents must never touch |

---

## Step 4 — Build and Install SolutionParser

SolutionParser is required for the plan-decomposer to analyze your solution structure.

**Build from source** (in this package's `solution-parser/` folder):

```powershell
cd C:\path\to\swarm\solution-parser
dotnet build -c Release
```

The built executable will be at:
```
solution-parser\bin\Release\net8.0\SolutionParser.exe
```

**Add to PATH** — copy `SolutionParser.exe` and its companion DLLs to a directory on your `PATH`, or add the build output directory to your PATH:

```powershell
# Option A: copy to an existing scripts directory
Copy-Item solution-parser\bin\Release\net8.0\*.* C:\your-scripts-dir\

# Option B: add build output to PATH (add to your PowerShell profile)
$env:PATH += ";C:\path\to\swarm\solution-parser\bin\Release\net8.0"
```

**Verify installation:**
```powershell
SolutionParser.exe --root C:\path\to\your-repo --output .\solution-structure.json
```

You should see a JSON file with `projects`, `dependencyGraph`, and `coreProjectNames`.

---

## Step 5 — Copy the PowerShell Scripts

Copy the swarm scripts to a directory on your PATH:

```powershell
Copy-Item scripts\validate-swarm-config.ps1 C:\your-scripts-dir\
Copy-Item scripts\generate-tool-views.ps1 C:\your-scripts-dir\
```

---

## Step 6 — Validate the Configuration

From your repo root:

```powershell
validate-swarm-config.ps1
```

Expected output: `Swarm config validation passed.`

If validation fails, it will report:
- **Orphan ruleId** — a rule in `rule-groups.json` not found in `construct-registry.json`
- **Missing sourcePath** — a rule's `.mdc` file path is wrong or file was moved
- **Missing standards.md or policies.json** — required files not found

---

## Step 7 — Write Your Rules

The `construct-registry.json` references rule files in `.cursor/rules/` as `.mdc` files. The included registry points to the `your-project` rules. You need to:

1. Replace the rule content in `.cursor/rules/` with your project's actual rules
2. Update `sourcePath` entries in `construct-registry.json` to match your rule file paths
3. Re-run `validate-swarm-config.ps1`

If you don't have existing rules, start with just the `core` group (3 rules) and add groups incrementally.

---

## Step 8 — Run the Swarm

```
/swarm add logging to all service classes
```

Or with a task spec file (recommended for scope-sensitive tasks):

```
/swarm .swarm/tasks/my-task.md
```

---

## Directory Layout Reference (After Installation)

```
your-repo/
├── .swarm/
│   ├── standards.md          ← Edit this for your project
│   ├── policies.json         ← Edit this for your project
│   ├── HOW-TO.md
│   ├── runs/                 ← Created at runtime; one folder per run
│   ├── tasks/                ← Your task spec files go here
│   └── config/               ← Usually leave as-is after initial setup
├── .cursor/
│   ├── agents/               ← Agent definitions (copied from this package)
│   └── rules/                ← Your project rules as .mdc files
```
