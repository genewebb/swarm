// <copyright file="DiscoveryResult.cs" company="Swarm">
// Output model for solution/project discovery.
// </copyright>

namespace SolutionParser;

/// <summary>
/// Result of solution and project discovery.
/// </summary>
public sealed class DiscoveryResult
{
    /// <summary>All discovered projects with dependencies and dependents.</summary>
    public required IReadOnlyList<ProjectInfo> Projects { get; init; }

    /// <summary>Dependency graph: project name -> list of projects it depends on.</summary>
    public required IReadOnlyDictionary<string, IReadOnlyList<string>> DependencyGraph { get; init; }

    /// <summary>Project names identified as "core" (shared, contracts, DI, etc.).</summary>
    public required IReadOnlyList<string> CoreProjectNames { get; init; }
}
