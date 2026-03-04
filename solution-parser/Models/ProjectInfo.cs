// <copyright file="ProjectInfo.cs" company="Swarm">
// Models a discovered project with dependencies and dependents.
// </copyright>

namespace SolutionParser;

/// <summary>
/// Represents a discovered C# project with its dependency graph context.
/// </summary>
public sealed class ProjectInfo
{
    /// <summary>Project name (from .csproj filename).</summary>
    public required string Name { get; init; }

    /// <summary>Relative or absolute path to the .csproj file.</summary>
    public required string Path { get; init; }

    /// <summary>Projects this project directly depends on.</summary>
    public required IReadOnlyList<string> Dependencies { get; init; }

    /// <summary>Projects that directly depend on this project.</summary>
    public required IReadOnlyList<string> Dependents { get; init; }
}
