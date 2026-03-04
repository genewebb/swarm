# SolutionParser

C# solution and project discovery utility for Plan Decomposer. Parses `.sln` and `.csproj` files, builds the dependency graph, and identifies core projects.

## Usage

```bash
# From SolutionParser repo root
dotnet run --project SolutionParser

# Or from build output
SolutionParser.exe
```

### Options

- `--root <path>` — Root directory to search (default: current directory)
- `--output <path>` or `-o` — Write JSON output to file (default: stdout)
- `--verbose` or `-v` — Enable debug logging

### Examples

```bash
dotnet run --project SolutionParser -- --output solution-structure.json
SolutionParser.exe --root C:\path\to\repo --output solution-structure.json
SolutionParser.exe --verbose --output solution-structure.json
```

## Output

JSON with `projects`, `dependencyGraph`, and `coreProjectNames`.

## Location

This project lives in **c:\path\to\SolutionParser**. For Plan Decomposer (e.g. in your-project), invoke from the SolutionParser repo or a published path:

```bash
# From your-project or another repo
dotnet run --project c:\path\to\SolutionParser\SolutionParser.csproj -- --root . --output solution-structure.json
```
