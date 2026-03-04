# Tester Rules

## Test Principles

1. **Test only** – Run the existing test suite; do not modify code or add tests.
2. **Schema compliance** – Output must validate against `tester.schema.json`.
3. **No handoff** – Tester is the last step in the workflow; hands off to no other agent.

## Status

- **passed** – All tests passed.
- **failed** – One or more tests failed; list in `failures`.
- **error** – Test command could not run (missing deps, wrong path, etc.).

## Workflow

1. Read handoff for run-id and context.
2. Find test command (e.g. `bun run test`, `npm test`, `pytest`, `go test`).
3. Execute the command.
4. Capture output and write `tester.result.json`.
