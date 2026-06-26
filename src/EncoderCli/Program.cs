using MmProtect.EncoderCli;
using MmProtect.EncoderCli.Configuration;
using MmProtect.EncoderCli.Encoding;
using MmProtect.EncoderCli.Server;

var cli = CliArgs.Parse(args);

if (cli.Command is null)
{
    CliArgs.PrintUsage();
    return 2;
}

try
{
    switch (cli.Command)
    {
        case "validate":
        {
            var config = EncoderConfigLoader.Load(cli.ConfigPath);
            var project = config.GetProject(cli.ProjectKey, allowFirst: true);
            Console.WriteLine($"Config ok. Projekte: {config.Projects.Count}. Gewählt: {project.ProjectKey}");
            return 0;
        }

        case "encode":
        {
            var config = EncoderConfigLoader.Load(cli.ConfigPath);
            var project = config.GetProject(cli.ProjectKey, allowFirst: false);

            var apiKey = config.LicenseServer.ResolveApiKey();
            using var http = new HttpClient
            {
                BaseAddress = new Uri(config.LicenseServer.BaseUrl.TrimEnd('/') + "/"),
                Timeout = TimeSpan.FromSeconds(config.LicenseServer.TimeoutSeconds <= 0 ? 30 : config.LicenseServer.TimeoutSeconds)
            };

            var client = new LicenseServerClient(http, apiKey);
            var encoder = new ProjectEncoder(client);
            await encoder.EncodeAsync(config, project, cli.Verbose);
            return 0;
        }

        case "manifest":
        {
            var config = EncoderConfigLoader.Load(cli.ConfigPath);
            var project = config.GetProject(cli.ProjectKey, allowFirst: false);
            var manifestPath = Path.Combine(project.OutputRoot, ".mmprotect", "manifest.json");
            Console.WriteLine(File.Exists(manifestPath)
                ? File.ReadAllText(manifestPath)
                : $"Manifest nicht gefunden: {manifestPath}");
            return File.Exists(manifestPath) ? 0 : 1;
        }

        case "clean":
        {
            var config = EncoderConfigLoader.Load(cli.ConfigPath);
            var project = config.GetProject(cli.ProjectKey, allowFirst: false);
            if (Directory.Exists(project.OutputRoot))
                Directory.Delete(project.OutputRoot, recursive: true);
            Console.WriteLine($"Gelöscht: {project.OutputRoot}");
            return 0;
        }

        default:
            Console.Error.WriteLine($"Unbekannter Befehl: {cli.Command}");
            CliArgs.PrintUsage();
            return 2;
    }
}
catch (Exception ex)
{
    Console.Error.WriteLine($"ERROR: {ex.Message}");
    if (cli.Verbose)
        Console.Error.WriteLine(ex);
    return 1;
}
