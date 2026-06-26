namespace MmProtect.EncoderCli;

public sealed class CliArgs
{
    public string? Command { get; private set; }
    public string ConfigPath { get; private set; } = "configs/encoder.config.json";
    public string? ProjectKey { get; private set; }
    public bool Verbose { get; private set; }

    public static CliArgs Parse(string[] args)
    {
        var result = new CliArgs();
        if (args.Length > 0)
            result.Command = args[0].Trim().ToLowerInvariant();

        for (var i = 1; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--config":
                case "-c":
                    result.ConfigPath = args[++i];
                    break;
                case "--project":
                case "-p":
                    result.ProjectKey = args[++i];
                    break;
                case "--verbose":
                case "-v":
                    result.Verbose = true;
                    break;
            }
        }

        return result;
    }

    public static void PrintUsage()
    {
        Console.WriteLine("""
        mmencoder validate --config configs/encoder.config.json [--project key]
        mmencoder encode   --config configs/encoder.config.json --project key
        mmencoder manifest --config configs/encoder.config.json --project key
        mmencoder clean    --config configs/encoder.config.json --project key
        """);
    }
}
