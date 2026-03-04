// <copyright file="CoreProjectDetector.cs" company="Swarm">
// Identifies core projects using hybrid heuristic: dependency graph + name patterns.
// </copyright>

namespace SolutionParser;

/// <summary>
/// Identifies "core" projects for plan decomposition ordering.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Plan Decomposer needs to order sub-plans; core projects
/// (shared, contracts, DI) should be handled first.</para>
/// <para><b>Heuristic</b>: Bottom quartile of depth (few dependencies) + top quartile
/// of dependents (many dependents). Supplement with name patterns.</para>
/// </remarks>
public static class CoreProjectDetector
{
    private static readonly string[] CoreNamePatterns = { "Shared", "Contracts", "DependencyInjection", "Infrastructure" };

    /// <summary>
    /// Detects core projects from the dependency graph.
    /// </summary>
    /// <param name="projects">All projects with dependencies and dependents.</param>
    /// <returns>Sorted list of core project names.</returns>
    public static IReadOnlyList<string> DetectCoreProjects(IReadOnlyList<ProjectInfo> projects)
    {
        if (projects.Count == 0)
            return Array.Empty<string>();

        var byName = projects.ToDictionary(p => p.Name, StringComparer.OrdinalIgnoreCase);

        // Graph-based detection requires enough projects for quartile thresholds to be meaningful.
        // With fewer than 4 projects the bottom-quartile index collapses to 0, which flags every
        // project as core. Skip graph detection for small repos and rely on name patterns only.
        var coreFromGraph = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (projects.Count >= 4)
        {
            var depths = ComputeDepths(byName);
            var dependentsCounts = projects.ToDictionary(p => p.Name, p => p.Dependents.Count, StringComparer.OrdinalIgnoreCase);

            var depthValues = depths.Values.Where(d => d >= 0).ToList();
            var depCountValues = dependentsCounts.Values.ToList();

            var depthThreshold = depthValues.Count > 0 ? GetBottomQuartileThreshold(depthValues) : int.MaxValue;
            var dependentsThreshold = depCountValues.Count > 0 ? GetTopQuartileThreshold(depCountValues) : 0;

            foreach (var p in projects)
            {
                var depth = depths.GetValueOrDefault(p.Name, -1);
                var dependents = dependentsCounts.GetValueOrDefault(p.Name, 0);
                if (depth >= 0 && depth <= depthThreshold && dependents >= dependentsThreshold)
                    coreFromGraph.Add(p.Name);
            }
        }

        var coreFromNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in projects)
        {
            if (MatchesCoreNamePattern(p.Name))
                coreFromNames.Add(p.Name);
        }

        var core = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        core.UnionWith(coreFromGraph);
        core.UnionWith(coreFromNames);

        return core.OrderBy(x => x, StringComparer.OrdinalIgnoreCase).ToList();
    }

    private static bool MatchesCoreNamePattern(string projectName)
    {
        foreach (var pattern in CoreNamePatterns)
        {
            if (projectName.EndsWith("." + pattern, StringComparison.OrdinalIgnoreCase) ||
                projectName.Equals(pattern, StringComparison.OrdinalIgnoreCase))
                return true;
        }

        return false;
    }

    private static Dictionary<string, int> ComputeDepths(IReadOnlyDictionary<string, ProjectInfo> byName)
    {
        var depths = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
        var visiting = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        int DepthOf(string name)
        {
            if (depths.TryGetValue(name, out var d))
                return d;
            if (!byName.TryGetValue(name, out var proj))
                return -1;
            if (visiting.Contains(name))
                return 0;
            if (proj.Dependencies.Count == 0)
            {
                depths[name] = 0;
                return 0;
            }

            visiting.Add(name);
            try
            {
                var maxDep = proj.Dependencies
                    .Select(DepthOf)
                    .Where(d => d >= 0)
                    .DefaultIfEmpty(-1)
                    .Max();
                var depth = maxDep < 0 ? 0 : maxDep + 1;
                depths[name] = depth;
                return depth;
            }
            finally
            {
                visiting.Remove(name);
            }
        }

        foreach (var name in byName.Keys)
            _ = DepthOf(name);

        return depths;
    }

    private static int GetBottomQuartileThreshold(IReadOnlyList<int> sorted)
    {
        var ordered = sorted.OrderBy(x => x).ToList();
        var idx = Math.Max(0, (ordered.Count * 25) / 100 - 1);
        return idx < ordered.Count ? ordered[idx] : ordered[^1];
    }

    private static int GetTopQuartileThreshold(IReadOnlyList<int> sorted)
    {
        var ordered = sorted.OrderByDescending(x => x).ToList();
        var idx = Math.Max(0, (ordered.Count * 25) / 100 - 1);
        return idx < ordered.Count ? ordered[idx] : 0;
    }
}
