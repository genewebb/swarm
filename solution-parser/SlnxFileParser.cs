// <copyright file="SlnxFileParser.cs" company="Swarm">
// Parses Visual Studio .slnx XML solution files to extract project entries.
// </copyright>

using System.Xml.Linq;

namespace SolutionParser;

/// <summary>
/// Parses .slnx (XML-based) solution files to extract C# project paths.
/// </summary>
/// <remarks>
/// <para><b>Context</b>: .slnx is the XML solution format introduced in VS 2022 17.x.
/// Project elements use <c>&lt;Project Path="relative/path.csproj" /&gt;</c>.</para>
/// <para><b>Thread-safety</b>: Stateless; all methods are pure. Thread-safe.</para>
/// </remarks>
public static class SlnxFileParser
{
    /// <summary>
    /// Parses a .slnx solution file and returns all .csproj paths referenced in it.
    /// </summary>
    /// <param name="slnxContent">Raw XML content of the .slnx file.</param>
    /// <param name="slnxDirectory">Directory containing the .slnx file (for resolving relative paths).</param>
    /// <returns>List of absolute project file paths.</returns>
    public static IReadOnlyList<string> ParseProjectPaths(string slnxContent, string slnxDirectory)
    {
        if (string.IsNullOrWhiteSpace(slnxContent))
            return Array.Empty<string>();

        try
        {
            var doc = XDocument.Parse(slnxContent);
            var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

            foreach (var el in doc.Descendants())
            {
                if (!string.Equals(el.Name.LocalName, "Project", StringComparison.OrdinalIgnoreCase))
                    continue;

                var pathAttr = el.Attribute("Path")?.Value;
                if (string.IsNullOrWhiteSpace(pathAttr))
                    continue;

                var normalized = pathAttr.Replace('/', Path.DirectorySeparatorChar)
                                         .Replace('\\', Path.DirectorySeparatorChar);
                var fullPath = Path.GetFullPath(Path.Combine(slnxDirectory, normalized));
                if (fullPath.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase))
                    paths.Add(fullPath);
            }

            return paths.ToList();
        }
        catch
        {
            return Array.Empty<string>();
        }
    }
}
