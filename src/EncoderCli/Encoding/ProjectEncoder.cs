using MmProtect.EncoderCli.Configuration;
using MmProtect.EncoderCli.Server;
using System.Text.Json;

namespace MmProtect.EncoderCli.Encoding;

public sealed class ProjectEncoder
{
    private readonly LicenseServerClient _client;

    public ProjectEncoder(LicenseServerClient client)
    {
        _client = client;
    }

    public async Task EncodeAsync(EncoderConfig config, ProjectOptions project, bool verbose)
    {
        var sourceRoot = Path.GetFullPath(project.SourceRoot);
        var outputRoot = Path.GetFullPath(project.OutputRoot);

        if (!Directory.Exists(sourceRoot))
            throw new DirectoryNotFoundException(sourceRoot);

        Directory.CreateDirectory(outputRoot);

        Console.WriteLine($"Projekt: {project.ProjectKey}");
        Console.WriteLine($"Quelle:  {sourceRoot}");
        Console.WriteLine($"Ziel:    {outputRoot}");

        var customer = await _client.UpsertCustomerAsync(new
        {
            project.Customer.ExternalCustomerRef,
            project.Customer.Name,
            project.Customer.Email,
            project.Customer.Notes
        });

        var serverProject = await _client.UpsertProjectAsync(new
        {
            projectKey = project.ProjectKey,
            name = project.Name,
            phpMinVersion = config.Defaults.PhpMinVersion,
            description = project.Name
        });

        var license = await _client.UpsertLicenseAsync(new
        {
            customerId = customer.CustomerId,
            projectId = serverProject.ProjectId,
            licenseKey = project.License.LicenseKey,
            validFrom = project.License.ValidFrom,
            validUntil = project.License.ValidUntil,
            maxActivations = project.License.MaxActivations,
            features = project.License.Features
        });

        var build = await _client.StartBuildAsync(new
        {
            projectId = serverProject.ProjectId,
            customerId = customer.CustomerId,
            licenseId = license.LicenseId,
            version = project.Version,
            sourceRevision = project.SourceRevision,
            encoderVersion = typeof(ProjectEncoder).Assembly.GetName().Version?.ToString() ?? "dev"
        });

        CopyPlainFiles(sourceRoot, outputRoot, project.CopyPlain, project.Exclude, verbose);

        var files = FileSelector.SelectFiles(sourceRoot, project.Include, project.Exclude)
            .Where(p => string.Equals(Path.GetExtension(p), ".php", StringComparison.OrdinalIgnoreCase))
            .ToList();

        var buildKey = Convert.FromBase64String(build.BuildKey);
        var manifestFiles = new List<ManifestFileDto>();

        foreach (var path in files)
        {
            var relative = Path.GetRelativePath(sourceRoot, path).Replace('\\', '/');
            var plain = await File.ReadAllBytesAsync(path);
            var fileId = "file_" + Hashing.ShortSha256(relative);
            var pathHash = "sha256:" + Hashing.Sha256Hex(relative);
            var plainHash = "sha256:" + Hashing.Sha256Hex(plain);
            var fileKey = CryptoPrimitives.HkdfSha256(buildKey, $"{build.BuildId}:{fileId}:{pathHash}", 32);

            var encrypted = MmencContainer.Create(
                plain,
                fileKey,
                new MmencHeader
                {
                    Format = "MMENC1",
                    FormatVersion = 1,
                    ProjectId = serverProject.ProjectId,
                    CustomerId = customer.CustomerId,
                    LicenseId = license.LicenseId,
                    BuildId = build.BuildId,
                    FileId = fileId,
                    RelativePath = relative,
                    PathHash = pathHash,
                    PlainHash = plainHash,
                    Algorithm = config.Defaults.Algorithm,
                    Kdf = "HKDF-SHA256",
                    KeyId = build.KeyId,
                    ManifestHash = "pending",
                    CreatedAt = DateTimeOffset.UtcNow
                },
                signingKeyFile: config.Defaults.Signing?.PrivateKeyFile);

            var outPath = Path.Combine(outputRoot, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(outPath)!);
            await File.WriteAllBytesAsync(outPath, encrypted.FileBytes);

            manifestFiles.Add(new ManifestFileDto(
                fileId,
                relative,
                pathHash,
                plainHash,
                "sha256:" + Hashing.Sha256Hex(encrypted.Ciphertext),
                config.Defaults.Algorithm,
                "HKDF-SHA256"));

            if (verbose)
                Console.WriteLine($"encoded: {relative}");
        }

        await _client.RegisterFilesAsync(build.BuildId, new
        {
            files = manifestFiles.Select(f => new
            {
                fileId = f.FileId,
                relativePath = f.RelativePath,
                pathHash = f.PathHash,
                plainHash = f.PlainHash,
                cipherHash = f.CipherHash,
                algorithm = f.Algorithm,
                kdf = f.Kdf
            }).ToArray()
        });

        var manifest = new ManifestDto(
            "MMENC-MANIFEST-1",
            serverProject.ProjectId,
            customer.CustomerId,
            license.LicenseId,
            build.BuildId,
            project.Version,
            config.Defaults.PhpMinVersion,
            config.Defaults.Algorithm,
            "HKDF-SHA256",
            manifestFiles,
            "",
            "");

        var manifestHash = "sha256:" + Hashing.Sha256Hex(JsonSerializer.SerializeToUtf8Bytes(manifest with { ManifestHash = "", Signature = "" }));
        var sign = await _client.SignManifestAsync(build.BuildId, new
        {
            manifestHash,
            fileCount = manifestFiles.Count
        });

        manifest = manifest with
        {
            ManifestHash = manifestHash,
            Signature = sign.ManifestSignature
        };

        var protectDir = Path.Combine(outputRoot, ".mmprotect");
        Directory.CreateDirectory(protectDir);

        await File.WriteAllTextAsync(Path.Combine(protectDir, "manifest.json"),
            JsonSerializer.Serialize(manifest, JsonOptions.Pretty));

        await File.WriteAllTextAsync(Path.Combine(protectDir, "license.json"),
            JsonSerializer.Serialize(new
            {
                format = "MMENC-LICENSE-1",
                licenseId = license.LicenseId,
                projectId = serverProject.ProjectId,
                customerId = customer.CustomerId,
                buildId = build.BuildId,
                licenseServer = config.LicenseServer.BaseUrl,
                features = project.License.Features
            }, JsonOptions.Pretty));

        if (config.Defaults.DevMode)
        {
            // Week-1 loader smoke-test: write buildKey so the loader can decrypt
            // without an HTTP lease call. NEVER enable in production.
            var devKeyPath = Path.Combine(protectDir, "dev-buildkey.b64");
            await File.WriteAllTextAsync(devKeyPath, build.BuildKey + "\n");
            Console.WriteLine($"[DEV] dev-buildkey.b64 geschrieben → {devKeyPath}");
        }

        Console.WriteLine($"Fertig. Geschützte Dateien: {manifestFiles.Count}");
    }

    private static void CopyPlainFiles(string sourceRoot, string outputRoot, List<string> copyPlain, List<string> exclude, bool verbose)
    {
        var files = FileSelector.SelectFiles(sourceRoot, copyPlain, exclude);
        foreach (var source in files)
        {
            var relative = Path.GetRelativePath(sourceRoot, source);
            var target = Path.Combine(outputRoot, relative);
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            File.Copy(source, target, overwrite: true);
            if (verbose)
                Console.WriteLine($"copied: {relative}");
        }
    }
}
