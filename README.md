# Swarm — AI Agent Pipeline for .NET Repositories

The Swarm is a structured AI agent workflow that automates software engineering tasks end-to-end inside a .NET repository. You describe a task; the Swarm plans, implements, reviews, tests, and verifies it — using a configurable pipeline of specialized agents.

---

## What Is In This Package

```
swarm/
├── README.md                        ← You are here
├── docs/
│   ├── 01-overview.md               ← How the pipeline works
│   ├── 02-installation.md           ← Step-by-step setup guide
│   ├── 03-configuration.md          ← All configuration files explained
│   └── 04-writing-tasks.md          ← How to author task spec files
├── swarm-template/                  ← Drop into your repo as .swarm/
│   ├── standards.md                 ← Project invariants (YOU customize this)
│   ├── policies.json                ← Git, file access, PR, loop limits
│   ├── HOW-TO.md                    ← Swarm usage reference
│   ├── tasks/
│   │   └── example-task.md          ← Example task spec file
│   └── config/
│       ├── construct-registry.json  ← All rules, commands, MCP refs
│       ├── rule-groups.json         ← Rule groups and phase visibility
│       ├── workflow.json            ← Planner/reviewer/integrator settings
│       ├── plan-decomposer.json     ← Sub-plan decomposition settings
│       └── tool-adapters/           ← Per-tool configs (Cursor, VS Code, etc.)
├── agents/                          ← Drop into your repo as .cursor/agents/
│   ├── manager.md                   ← Orchestrator (reads manager/config.json)
│   ├── core-planner.md
│   ├── constraint-reviewer.md
│   ├── plan-integrator.md
│   ├── plan-decomposer.md
│   ├── implementor.md
│   ├── reviewer.md
│   ├── tester.md
│   ├── verifier.md
│   └── {agent}/                     ← Schemas and rules per agent
├── scripts/
│   ├── validate-swarm-config.ps1    ← Validates .swarm/config/ consistency
│   └── generate-tool-views.ps1      ← Regenerates CLAUDE.md / copilot-instructions.md
└── solution-parser/                 ← SolutionParser source (.NET 8)
    ├── SolutionParser.csproj
    ├── *.cs
    └── Models/
```

---

## Quick Start

1. **Copy files into your repo** — see [docs/02-installation.md](docs/02-installation.md)
2. **Edit `standards.md`** — describe your project's invariants and tooling
3. **Build and deploy SolutionParser.exe** — must be on `PATH`
4. **Run `validate-swarm-config.ps1`** — confirms config is wired correctly
5. **Run the Swarm** — `/swarm <task description>` or `/swarm .swarm/tasks/my-task.md`

---

## Documentation

| Doc | Contents |
|-----|----------|
| [01-overview.md](docs/01-overview.md) | Pipeline stages, agent roles, branching modes |
| [02-installation.md](docs/02-installation.md) | Prerequisites, copy steps, PATH setup, validation |
| [03-configuration.md](docs/03-configuration.md) | Every config file explained with all options |
| [04-writing-tasks.md](docs/04-writing-tasks.md) | Task spec file format, scope anchoring, examples |
