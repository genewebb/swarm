// <copyright file="SlnFileParser.cs" company="Swarm">
// Parses Visual Studio .sln files to extract project entries.
// </copyright>

using System.Text.RegularExpressions;

namespace SolutionParser;

/// <summary>
/// Parses .sln files to extract C# project paths.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: Solution files use a line-based format. Project entries follow
/// Project("{GUID}") = "Name", "Path\Project.csproj", "{GUID}".</para>
/// <para><b>Thread-safety</b>: Stateless; all methods are pure. Thread-safe.</para>
/// </remarks>
public static class SlnFileParser
{
    private static readonly Regex ProjectLineRegex = new(
        @"^\s*Project\s*\(\s*""\{[^}]+\}""\s*\)\s*=\s*""[^""]*""\s*,\s*""([^""]+\.csproj)""\s*,\s*""\{[^}]+\}""",
        RegexOptions.Compiled);

    /// <summary>
    /// Parses a solution file and returns all .csproj paths referenced in it.
    /// </summary>
    /// <param name="slnContent">Raw content of the .sln file.</param>
    /// <param name="slnDirectory">Directory containing the .sln file (for resolving relative paths).</param>
    /// <returns>List of absolute project file paths.</returns>
    public static IReadOnlyList<string> ParseProjectPaths(string slnContent, string slnDirectory)
    {
        if (string.IsNullOrWhiteSpace(slnContent))
            return Array.Empty<string>();

        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var line in slnContent.Split('\n', StringSplitOptions.RemoveEmptyEntries))
        {
            var match = ProjectLineRegex.Match(line.Trim());
            if (!match.Success)
                continue;

            var relativePath = match.Groups[1].Value.Replace('\\', Path.DirectorySeparatorChar);
            var fullPath = Path.GetFullPath(Path.Combine(slnDirectory, relativePath));
            if (fullPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
                paths.Add(fullPath);
        }

        return paths.ToList();
    }

    /// <summary>
    /// Derives project name from a .csproj file path (filename without extension).
    /// </summary>
    public static string GetProjectNameFromPath(string csprojPath)
    {
        var fileName = Path.GetFileName(csprojPath);
        return string.IsNullOrEmpty(fileName) ? string.Empty : Path.GetFileNameWithoutExtension(fileName);
    }
}
