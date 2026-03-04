# Reviewer Rules

## Review Principles

1. **Review only** – Never modify code. Produce only the review result.
2. **Standards-based** – Use `.swarm/standards.md` as the source of truth.
3. **Schema compliance** – Output must validate against `reviewer.schema.json`.

## Verdict

- **approved** – All changes conform to the standards; no issues found.
- **rejected** – One or more changes violate the standards; list each in `issues`.

## Issues

When rejecting, each issue should include:
- `description` – What is wrong and why
- `file` – Path to the file (optional)
- `line` – Line number (optional)
- `standard` – Which rule or standard was violated (optional)

## Scope

Review only the changes in the current branch or worktree (e.g. `git diff` against base, or staged/unstaged changes). Do not review the entire codebase.
