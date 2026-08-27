using MmProtect.EncoderCli.Configuration;
using MmProtect.EncoderCli.Encoding;
using MmProtect.EncoderCli.Server;

namespace MmProtect.EncoderCli.Gui;

public sealed record EncoderPreview(int EncodedPhpFiles, int PlainFiles, IReadOnlyList<string> EncodedPaths, IReadOnlyList<string> MmIgnoreFiles);

/// <summary>Single entry point used by both the desktop UI and the command-line host.</summary>
public sealed class EncoderFacade
{
    public void Validate(EncoderConfig config, ProjectOptions project)
    {
        if (string.IsNullOrWhiteSpace(config.LicenseServer.BaseUrl) || !Uri.TryCreate(config.LicenseServer.BaseUrl, UriKind.Absolute, out _))
            throw new InvalidOperationException("Eine gültige License-Server-URL ist erforderlich.");
        if (string.IsNullOrWhiteSpace(config.LicenseServer.ResolveApiKey()))
            throw new InvalidOperationException("Ein Encoder-API-Schlüssel ist erforderlich.");
        if (string.IsNullOrWhiteSpace(project.ProjectKey) || string.IsNullOrWhiteSpace(project.Name))
            throw new InvalidOperationException("Projektkennung und Projektname sind erforderlich.");
        if (string.IsNullOrWhiteSpace(project.Customer.ExternalCustomerRef) || string.IsNullOrWhiteSpace(project.Customer.Name))
            throw new InvalidOperationException("Kundenreferenz und Kundenname sind erforderlich.");
        if (string.IsNullOrWhiteSpace(project.License.LicenseKey))
            throw new InvalidOperationException("Ein Lizenzschlüssel ist erforderlich.");
        if (!Directory.Exists(project.SourceRoot)) throw new DirectoryNotFoundException(project.SourceRoot);
        var source = Path.GetFullPath(project.SourceRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        var output = Path.GetFullPath(project.OutputRoot).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);
        if (string.Equals(source, output, OperatingSystem.IsWindows() ? StringComparison.OrdinalIgnoreCase : StringComparison.Ordinal))
            throw new InvalidOperationException("Quell- und Zielordner dürfen nicht identisch sein.");
    }

    public EncoderPreview Preview(EncoderConfig config, ProjectOptions project)
    {
        Validate(config, project);
        var source = Path.GetFullPath(project.SourceRoot);
        var rules = MmIgnoreRuleSet.LoadFromSourceRoot(source, config.Defaults.MmIgnoreFile);
        var selected = rules.HasRules
            ? FileSelector.SelectFilesWithMmIgnore(source, rules, project.Include, project.Exclude, project.CopyPlain)
            : FileSelector.SelectFiles(source, project.Include, project.Exclude).Select(path => (AbsPath: path, Action: FileAction.Encode)).ToList();
        var encoded = selected.Where(x => x.Action == FileAction.Encode && Path.GetExtension(x.AbsPath).Equals(".php", StringComparison.OrdinalIgnoreCase))
            .Select(x => Path.GetRelativePath(source, x.AbsPath).Replace('\\', '/')).Order().ToList();
        if (encoded.Any(path => path.Equals("vendor", StringComparison.OrdinalIgnoreCase) || path.StartsWith("vendor/", StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("vendor/ darf nie verschlüsselt werden. Bitte als Klartext ausschließen.");
        var plain = selected.Count(x => x.Action == FileAction.CopyPlain);
        var ignores = Directory.EnumerateFiles(source, ".mmignore", SearchOption.AllDirectories)
            .Select(path => Path.GetRelativePath(source, path).Replace('\\', '/')).Order().ToList();
        return new EncoderPreview(encoded.Count, plain, encoded, ignores);
    }

    public async Task EncodeAsync(EncoderConfig config, ProjectOptions project, bool verbose, TextWriter log, CancellationToken cancellationToken, Action<int, int>? progress = null)
    {
        Validate(config, project);
        Preview(config, project); // applies the same file-selection and vendor safety rules as the GUI preview
        using var http = new HttpClient { BaseAddress = new Uri(config.LicenseServer.BaseUrl.TrimEnd('/') + "/"), Timeout = TimeSpan.FromSeconds(config.LicenseServer.TimeoutSeconds <= 0 ? 30 : config.LicenseServer.TimeoutSeconds) };
        var encoder = new ProjectEncoder(new LicenseServerClient(http, config.LicenseServer.ResolveApiKey()));
        await encoder.EncodeAsync(config, project, verbose, dryRun: false, log: log, cancellationToken: cancellationToken, progress: progress);
    }
}
