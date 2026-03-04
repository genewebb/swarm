# Task: scenario-workflow-metadata-comments

## Goal

Add a standardized metadata comment immediately before each scenario and workflow class declaration.

- **Scenario classes**: `// [Scenario] Category: X` where X is the scenario's area (CRUD, Matching, Metadata, Connect, Utility)
- **Workflow classes**: `// [Workflow]`

Place the comment immediately before the class declaration. Do not modify any logic or add anything else.

## Allowed Files

The following glob patterns define the exact scope. No files outside these patterns may be included in the plan.

```
MyApp.Records/Scenarios/**/*.cs
MyApp.Matching/Scenarios/**/*.cs
MyApp.Metadata/Scenarios/**/*.cs
MyApp.Connect/Scenarios/**/*.cs
MyApp.Utilities/Scenarios/**/*.cs
MyApp.Web/BusinessLogic/Services/Workflow*.cs
MyApp.Web/Services/Workflow*.cs
MyApp.Web/Jobs/Workflow*.cs
MyApp.Web/Models/Workflow*.cs
```

## Out of Scope

- `MyApp.Scenarios/` — DefaultScenario and ResourceCollectionScenario do not use the standard category system
- `MyApp.Application/` — scenarios here extend GetBase, not ScenarioBase
- Base classes: ScenarioBase, ScenarioBaseCrud, ScenarioBaseMatching, ScenarioBaseMetadata, ScenarioBaseConnect, UtilityBase
- Blazor components (Workflows.razor, WorkflowBuilder.razor, etc.)
- Nested/helper classes, constant classes, interfaces
- Logic changes of any kind
