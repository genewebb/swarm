// <copyright file="ProjectParser.cs" company="Swarm">
// Parses SDK-style .csproj files for ProjectReference elements.
// </copyright>

using System.Xml.Linq;

namespace SolutionParser;

/// <summary>
/// Parses .csproj files to extract ProjectReference dependencies.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: SDK-style projects are valid XML. ProjectReference Include
/// attributes hold relative paths to referenced projects.</para>
/// <para><b>Thread-safety</b>: Stateless; all methods are pure. Thread-safe.</para>
/// </remarks>
public static class ProjectParser
{
    /// <summary>
    /// Parses a .csproj file and returns the names of directly referenced projects.
    /// </summary>
    /// <param name="csprojContent">Raw content of the .csproj file.</param>
    /// <param name="csprojDirectory">Directory containing the .csproj (for resolving relative paths).</param>
    /// <param name="knownProjectPathsByPath">Map of absolute path -> project name for resolution.</param>
    /// <returns>List of referenced project names (as used in knownProjectPathsByPath).</returns>
    public static IReadOnlyList<string> ParseProjectReferences(
        string csprojContent,
        string csprojDirectory,
        IReadOnlyDictionary<string, string> knownProjectPathsByPath)
    {
        if (string.IsNullOrWhiteSpace(csprojContent))
            return Array.Empty<string>();

        try
        {
            var doc = XDocument.Parse(csprojContent);
            var refs = doc.Descendants()
                .Where(el => el.Name.LocalName == "ProjectReference")
                .Select(el => el.Attribute("Include")?.Value)
                .Where(v => !string.IsNullOrWhiteSpace(v));

            var resolved = new List<string>();
            foreach (var include in refs!)
            {
                var normalized = include!.Replace('\\', Path.DirectorySeparatorChar);
                var fullPath = Path.GetFullPath(Path.Combine(csprojDirectory, normalized));
                if (knownProjectPathsByPath.TryGetValue(fullPath, out var name))
                    resolved.Add(name);
            }

            return resolved;
        }
        catch
        {
            return Array.Empty<string>();
        }
    }
}
