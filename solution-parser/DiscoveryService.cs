// <copyright file="DiscoveryService.cs" company="Swarm">
// Orchestrates solution and project discovery.
// </copyright>

namespace SolutionParser;

/// <summary>
/// Discovers all solutions and projects in a root path and builds the dependency graph.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Used by Plan Decomposer to understand repo structure.</para>
/// <para><b>Thread-safety</b>: Not thread-safe; one instance per discovery run.</para>
/// </remarks>
public sealed class DiscoveryService
{
    private readonly Serilog.ILogger _logger;

    public DiscoveryService(Serilog.ILogger logger)
    {
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    /// <summary>
    /// Discovers all .sln and .csproj files from the given root and builds the graph.
    /// </summary>
    /// <param name="rootPath">Root directory to search (default: current directory).</param>
    /// <returns>Discovery result with projects, graph, and core detection.</returns>
    public DiscoveryResult Discover(string rootPath)
    {
        rootPath = Path.GetFullPath(string.IsNullOrWhiteSpace(rootPath) ? "." : rootPath);

        _logger.Information("Discovering solutions (.sln/.slnx) and projects from {RootPath}", rootPath);

        var slnPaths = Directory.GetFiles(rootPath, "*.sln", SearchOption.AllDirectories);
        var slnxPaths = Directory.GetFiles(rootPath, "*.slnx", SearchOption.AllDirectories);
        var allCsprojPaths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var slnPath in slnPaths)
        {
            var slnDir = Path.GetDirectoryName(slnPath) ?? rootPath;
            var content = File.ReadAllText(slnPath);
            var projects = SlnFileParser.ParseProjectPaths(content, slnDir);
            foreach (var p in projects)
            {
                if (File.Exists(p))
                    allCsprojPaths.Add(Path.GetFullPath(p));
            }
        }

        foreach (var slnxPath in slnxPaths)
        {
            var slnxDir = Path.GetDirectoryName(slnxPath) ?? rootPath;
            var content = File.ReadAllText(slnxPath);
            var projects = SlnxFileParser.ParseProjectPaths(content, slnxDir);
            foreach (var p in projects)
            {
                if (File.Exists(p))
                    allCsprojPaths.Add(Path.GetFullPath(p));
            }
        }

        if (allCsprojPaths.Count == 0)
        {
            var fallback = Directory.GetFiles(rootPath, "*.csproj", SearchOption.AllDirectories);
            foreach (var p in fallback)
                allCsprojPaths.Add(Path.GetFullPath(p));
        }

        _logger.Information("Found {Count} projects", allCsprojPaths.Count);

        var pathToName = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in allCsprojPaths)
            pathToName[p] = SlnFileParser.GetProjectNameFromPath(p);

        var dependenciesByProject = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var path in allCsprojPaths)
        {
            var name = pathToName[path];
            if (!dependenciesByProject.ContainsKey(name))
                dependenciesByProject[name] = new List<string>();

            var dir = Path.GetDirectoryName(path) ?? ".";
            var content = File.ReadAllText(path);
            var refs = ProjectParser.ParseProjectReferences(content, dir, pathToName);
            dependenciesByProject[name].AddRange(refs);
        }

        var dependentsByProject = new Dictionary<string, List<string>>(StringComparer.OrdinalIgnoreCase);
        foreach (var name in pathToName.Values.Distinct(StringComparer.OrdinalIgnoreCase))
            dependentsByProject[name] = new List<string>();

        foreach (var kv in dependenciesByProject)
        {
            foreach (var dep in kv.Value)
            {
                if (dependentsByProject.TryGetValue(dep, out var list))
                    list.Add(kv.Key);
            }
        }

        var nameToPath = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var kv in pathToName)
        {
            if (!nameToPath.ContainsKey(kv.Value))
                nameToPath[kv.Value] = kv.Key;
        }

        var projectInfos = nameToPath.Keys
            .Select(name =>
            {
                var path = nameToPath[name];
                var relPath = Path.GetRelativePath(rootPath, path);
                return new ProjectInfo
                {
                    Name = name,
                    Path = relPath,
                    Dependencies = dependenciesByProject.TryGetValue(name, out var d) ? d.ToList() : new List<string>(),
                    Dependents = dependentsByProject.TryGetValue(name, out var e) ? e.ToList() : new List<string>()
                };
            })
            .OrderBy(p => p.Name, StringComparer.OrdinalIgnoreCase)
            .ToList();

        var graph = projectInfos.ToDictionary(
            p => p.Name,
            p => (IReadOnlyList<string>)p.Dependencies,
            StringComparer.OrdinalIgnoreCase);

        var coreNames = CoreProjectDetector.DetectCoreProjects(projectInfos);
        _logger.Information("Identified {Count} core projects: {Names}", coreNames.Count, string.Join(", ", coreNames));

        return new DiscoveryResult
        {
            Projects = projectInfos,
            DependencyGraph = graph,
            CoreProjectNames = coreNames
        };
    }
}
