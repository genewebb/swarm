# Writing Task Spec Files

A **task spec file** pre-declares the scope of a task before the Swarm runs. Without one, the core-planner must infer scope from the task description — which can lead to it including files that were never intended.

Task spec files are the recommended approach for any task where file scope matters.

---

## Where They Live

```
.swarm/tasks/{friendly-name}.md
```

The `friendly-name` is the slug the Manager derives from your task description. If you run `/swarm scenario-workflow-metadata-comments`, the Manager looks for `.swarm/tasks/scenario-workflow-metadata-comments.md`.

You can also invoke the Swarm directly with the file path:

```
/swarm .swarm/tasks/my-task.md
```

---

## File Format

```markdown
# Task: {friendly-name}

## Goal

One paragraph describing what the task should accomplish.
Keep it concrete — the planner reads this to write the plan.

## Allowed Files

List glob patterns — one per line — that define the exact scope.
Only files matching these patterns may be included in the plan.

ProjectA/Scenarios/**/*.cs
ProjectB/Services/Workflow*.cs
ProjectC/Models/WorkflowItem.cs

## Out of Scope

- Item 1 — explain why it is excluded
- Item 2
- Base classes, nested/helper classes, interfaces
- Logic changes of any kind
```

---

## Example: Documentation-Only Task

```markdown
# Task: add-xml-docs-to-services

## Goal

Add XML documentation comments to all public methods in service classes
across MyApp.Web and MyApp.Records. No logic changes.

## Allowed Files

MyApp.Web/BusinessLogic/Services/*.cs
MyApp.Web/Services/*.cs
MyApp.Records/Services/*.cs

## Out of Scope

- Base classes and interfaces
- Test files
- Blazor components (.razor, .razor.cs)
- Logic changes of any kind
```

---

## Example: Feature Task With Multiple Projects

```markdown
# Task: add-export-to-csv-feature

## Goal

Add CSV export capability to the records grid. This includes a new
service method, a controller endpoint, and a Blazor button in the UI.

## Allowed Files

MyApp.Web/BusinessLogic/Services/ExportService.cs
MyApp.Web/Controllers/ExportController.cs
MyApp.Web/Components/Pages/RecordsGrid.razor
MyApp.Web/Components/Pages/RecordsGrid.razor.cs
MyApp.Web/Models/ExportRequest.cs

## Out of Scope

- Existing record service (RecordService.cs) — do not modify
- Authentication or authorization logic
- Database schema changes
```

---

## How Scope Flows Through the Pipeline

Once the Manager reads the task spec file, `allowedFiles` is propagated into every handoff:

```
Task spec file
    ↓
context.pack.md (Allowed / Forbidden section)
    ↓
handoff.context.allowedFiles
    ↓ (inherited by each agent)
core-planner      → can only include files matching these patterns
plan-integrator   → cannot add files outside this set
plan-decomposer   → groups only from this set; SolutionParser cannot expand it
implementor       → only edits files in this set
reviewer          → flags any file outside this set as a violation
```

---

## Naming Conventions

- Use kebab-case: `add-logging-to-services.md`
- Match the name you'll use when invoking the swarm: `/swarm add-logging-to-services`
- For recurring or template tasks, keep the name stable so it can be reused across runs

---

## Tips

**Be explicit with globs.** `ProjectA/Scenarios/**/*.cs` is better than `ProjectA/**/*.cs` because it narrows the scope to only scenario files, not everything in the project.

**Use the Out of Scope section — it is a hard Forbidden list.** When a task spec file is found, everything in `## Out of Scope` is written as a Forbidden entry in the context pack and enforced by scope validation after the planner runs. Any file matching a Forbidden pattern is rejected from the plan before the pipeline proceeds — the planner is forced to replan without those files.

**One task, one spec file.** Don't put multiple unrelated tasks in one spec file. Each spec file should correspond to one coherent unit of work.

**You can run the same spec file multiple times.** Task spec files are reusable. If a run fails partway through and you restart, the same scope is enforced.

---

## When You Don't Need a Task Spec File

For simple, single-project tasks where the scope is obvious from the description:

```
/swarm fix the null reference bug in WorkflowService.cs
```

The Manager will derive allowed files from the named file in the description. No spec file needed.

For multi-project tasks or any task where scope creep has been a problem, always use a spec file.
