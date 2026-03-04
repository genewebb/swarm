// <copyright file="Program.cs" company="Swarm">
// Entry point for SolutionParser.
// </copyright>

using Newtonsoft.Json;
using Serilog;

namespace SolutionParser;

internal static class Program
{
    private static int Main(string[] args)
    {
        var rootPath = ".";
        string? outputPath = null;
        var verbose = false;

        for (var i = 0; i < args.Length; i++)
        {
            if (args[i] == "--root" && i + 1 < args.Length)
            {
                rootPath = args[++i];
            }
            else if ((args[i] == "--output" || args[i] == "-o") && i + 1 < args.Length)
            {
                outputPath = args[++i];
            }
            else if (args[i] == "--verbose" || args[i] == "-v")
            {
                verbose = true;
            }
        }

        var logLevel = verbose ? Serilog.Events.LogEventLevel.Debug : Serilog.Events.LogEventLevel.Information;
        Log.Logger = new LoggerConfiguration()
            .MinimumLevel.Is(logLevel)
            .WriteTo.Console()
            .CreateLogger();

        try
        {
            var discovery = new DiscoveryService(Log.Logger);
            var result = discovery.Discover(rootPath);

            var json = JsonConvert.SerializeObject(new
            {
                projects = result.Projects.Select(p => new
                {
                    p.Name,
                    p.Path,
                    dependencies = p.Dependencies,
                    dependents = p.Dependents
                }).ToList(),
                dependencyGraph = result.DependencyGraph,
                coreProjectNames = result.CoreProjectNames
            }, Formatting.Indented);

            if (!string.IsNullOrEmpty(outputPath))
            {
                var dir = Path.GetDirectoryName(outputPath);
                if (!string.IsNullOrEmpty(dir))
                    Directory.CreateDirectory(dir);
                File.WriteAllText(outputPath, json);
                Log.Information("Wrote output to {Path}", Path.GetFullPath(outputPath));
            }
            else
            {
                Console.Out.WriteLine(json);
            }

            return 0;
        }
        catch (Exception ex)
        {
            Log.Fatal(ex, "Discovery failed");
            return 1;
        }
        finally
        {
            Log.CloseAndFlush();
        }
    }
}
