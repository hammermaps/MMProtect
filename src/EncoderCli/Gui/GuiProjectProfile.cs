using System.Text.Json;
using MmProtect.EncoderCli.Configuration;
using MmProtect.EncoderCli.Encoding;

namespace MmProtect.EncoderCli.Gui;

/// <summary>Local GUI profile. It intentionally lives below the customer project and is ignored by Git.</summary>
public sealed class GuiProjectProfile
{
    public const string RelativePath = ".mmprotect/gui-project.json";
    public LicenseServerOptions LicenseServer { get; set; } = new();
    public DefaultOptions Defaults { get; set; } = new();
    public ProjectOptions Project { get; set; } = new();

    public static GuiProjectProfile Import(string configPath, string? projectKey = null)
    {
        var config = EncoderConfigLoader.Load(configPath);
        return new GuiProjectProfile
        {
            LicenseServer = config.LicenseServer,
            Defaults = config.Defaults,
            Project = config.GetProject(projectKey, allowFirst: true)
        };
    }

    public EncoderConfig ToEncoderConfig() => new()
    {
        LicenseServer = LicenseServer,
        Defaults = Defaults,
        Projects = [Project]
    };

    public static GuiProjectProfile Load(string projectRoot)
    {
        var path = Path.Combine(projectRoot, RelativePath);
        var profile = JsonSerializer.Deserialize<GuiProjectProfile>(File.ReadAllText(path), JsonOptions.Pretty);
        return profile ?? throw new InvalidOperationException("GUI-Profil konnte nicht gelesen werden.");
    }

    public void Save(string projectRoot)
    {
        var path = Path.Combine(projectRoot, RelativePath);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(this, JsonOptions.Pretty));
        ProfileSecurity.Protect(path);
        GitIgnore.EnsureIgnored(projectRoot, RelativePath);
    }

    public void ExportCliConfig(string path)
        => File.WriteAllText(path, JsonSerializer.Serialize(ToEncoderConfig(), JsonOptions.Pretty));
}

public static class GitIgnore
{
    public static void EnsureIgnored(string projectRoot, string entry)
    {
        var path = Path.Combine(projectRoot, ".gitignore");
        var normalized = entry.Replace('\\', '/');
        var lines = File.Exists(path) ? File.ReadAllLines(path).ToList() : [];
        if (lines.Any(line => string.Equals(line.Trim(), normalized, StringComparison.Ordinal))) return;
        if (lines.Count > 0 && lines[^1].Length != 0) lines.Add("");
        lines.Add("# MMProtect GUI profile contains an encoder API key. Never commit it.");
        lines.Add(normalized);
        File.WriteAllLines(path, lines);
    }
}

public static class ProfileSecurity
{
    public static void Protect(string path)
    {
        if (!OperatingSystem.IsWindows())
        {
            File.SetUnixFileMode(path, UnixFileMode.UserRead | UnixFileMode.UserWrite);
            return;
        }

        // icacls removes inherited permissions and grants access only to the current user.
        // The key is never passed as an argument or written to output.
        var user = Environment.UserName;
        using var process = System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
        {
            FileName = "icacls",
            Arguments = $"\"{path}\" /inheritance:r /grant:r \"{user}:(R,W)\"",
            UseShellExecute = false,
            CreateNoWindow = true
        });
        process?.WaitForExit();
        if (process is null || process.ExitCode != 0)
            throw new InvalidOperationException("Die Benutzer-ACL für das GUI-Profil konnte nicht gesetzt werden.");
    }
}
