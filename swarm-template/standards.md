# Swarm Standards – your-project

This document indexes project standards. **Rules are loaded from the canonical registry**—agents use `activeGroupIds` and `activeRuleIds` to load only relevant rules. Do **not** fall back to loading the full `.cursor/rules/` tree.

## Authority

- **`.swarm/config/construct-registry.json`** – Single registry of all rules, commands, MCP refs
- **`.swarm/config/rule-groups.json`** – Group definitions and phase visibility
- **`.swarm/config/workflow.json`** – Canonical agent graph and fallback behavior
- **`.swarm/standards.md`** – This index; tooling guidance; group reference

## Core Invariants

These shape planning from the beginning:

1. **No guessing** – Verify before proceeding; state unknowns explicitly
2. **Only change relevant code** – No placeholders or incomplete code
3. **Clean code** – DRY, meaningful names, single responsibility, proper error handling
4. **No hard-coded domain values** – Fetch from database or configuration
5. **Newtonsoft.Json** – Use exclusively; no System.Text.Json in application code
6. **No Entity Framework** – Use IRestClient, repositories, SqlHelper per project patterns

## Rule Groups (from .swarm/config/rule-groups.json)

| Group ID | Description | Key rules |
|----------|-------------|-----------|
| **core** | True global invariants | no_guessing, only_change_relevant_code, clean_code_guidelines |
| **service-architecture** | DI, config, project structure | central_service_registration, single_secret_provider, base_structure |
| **data-access** | Data access, REST API | sql_data_access, external_api_patterns, domain_values, entity_name_constants |
| **ui-blazor** | Blazor UI | code_behind_separation, approved_icons |
| **testing** | MSTest, bUnit, test structure | testing_setup_overview, single_test_project, running_tests |
| **documentation-formatting** | XML docs, markdown, work items | class_and_code_documentation_rules, cursor_documentation_location, emoji_set |

Full rule prose lives in `.cursor/rules/`; the registry maps each rule to a group and phases. Load rules by `activeGroupIds` only.

## Context Documentation

- **`.cursor/documentation/your-project/`** – Plans, build notes, architecture. Use when a task relates to existing work.
- **Planner**: When the user provides doc paths, treat them as required input.
- **Implementor**: If the handoff references docs in `.cursor/documentation/`, read them before implementing.

## Tooling

- **Build**: `dotnet build`
- **Tests**: `dotnet test`
  - **During swarm** (tester agent): run only test files added/modified in the current sub-plan (`dotnet test --filter`). If no new test files, skip. Do NOT run the full suite.
  - **After swarm**: run the full `dotnet test` suite manually after the entire swarm run completes.
- **JSON**: Newtonsoft.Json exclusively
- **Logging**: Serilog.ILogger; structured logging; no secrets or PII

## Tech Stack

- **.NET / Blazor** – MyApp.Web, Radzen.Blazor
- **Test framework**: MSTest; bUnit for Blazor components
- **No EF** – Use IRestClient, repositories, SqlHelper per project patterns
