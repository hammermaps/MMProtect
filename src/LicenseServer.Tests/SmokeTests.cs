using Xunit;
using Dapper;
using Microsoft.Data.Sqlite;
using MmProtect.LicenseServer.Data;
using System.Data.Common;
using System.Net.Http.Json;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.DependencyInjection.Extensions;
using Microsoft.Extensions.Configuration;

namespace MmProtect.LicenseServer.Tests;

// Minimal E2E tests that spin up the ASP.NET Core server in-process against SQLite.
// Each test gets a fresh empty database so tests are isolated.
public sealed class SmokeTests : IDisposable
{
    private readonly WebApplicationFactory<Program> _factory;
    private readonly HttpClient _client;
    private readonly string _dbPath;

    public SmokeTests()
    {
        _dbPath = Path.Combine(Path.GetTempPath(), $"mmtest_{Guid.NewGuid():N}.db");

        // Apply the SQLite schema
        using var conn = new SqliteConnection($"Data Source={_dbPath}");
        conn.Open();
        var schema = File.ReadAllText(
            Path.Combine(AppContext.BaseDirectory, "..", "..", "..", "..", "..", "database", "sqlite", "schema.sql"));
        // SQLite pragma commands can't run in a multi-statement batch via Dapper — split on ';'
        foreach (var stmt in schema.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            if (!string.IsNullOrWhiteSpace(stmt))
                conn.Execute(stmt);
        }

        SqlMapper.AddTypeHandler(new DateTimeHandler());

        _factory = new WebApplicationFactory<Program>()
            .WithWebHostBuilder(builder =>
            {
                builder.UseSetting("DatabaseProvider", "sqlite");
                builder.UseSetting("ConnectionStrings:Sqlite", $"Data Source={_dbPath}");
                builder.UseSetting("Security:EncoderApiKeys:0", "test-api-key");
                builder.UseSetting("Security:LeaseTtlMinutes", "60");
                builder.UseSetting("Security:GracePeriodDays", "7");
            });

        _client = _factory.CreateClient();
        _client.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", "test-api-key");
    }

    [Fact]
    public async Task Health_Returns_Ok()
    {
        var resp = await _client.GetAsync("/health");
        resp.EnsureSuccessStatusCode();
        var body = await resp.Content.ReadAsStringAsync();
        Assert.Contains("ok", body);
    }

    [Fact]
    public async Task CustomerUpsert_CreatesAndDeduplicates()
    {
        // First upsert → created=true
        var r1 = await UpsertCustomerAsync("cref-001", "Test GmbH");
        Assert.True(r1.Created);
        var id1 = r1.CustomerId;

        // Second upsert with same ref → created=false, same ID
        var r2 = await UpsertCustomerAsync("cref-001", "Test GmbH Updated");
        Assert.False(r2.Created);
        Assert.Equal(id1, r2.CustomerId);
    }

    [Fact]
    public async Task ProjectUpsert_CreatesProject()
    {
        var r = await PostJsonAsync<ProjectUpsertDto>("/api/v1/encoder/projects/upsert", new
        {
            projectKey = "proj-smoke-001",
            name = "Smoke Test Project",
            phpMinVersion = "8.4",
            description = "test"
        });

        Assert.True(r.Created);
        Assert.StartsWith("proj_", r.ProjectId);
    }

    [Fact]
    public async Task FullEncoderFlow_CustomerProjectLicenseBuild()
    {
        var customer = await UpsertCustomerAsync("cref-flow-001", "Flow Customer");
        var project = await PostJsonAsync<ProjectUpsertDto>("/api/v1/encoder/projects/upsert", new
        {
            projectKey = "proj-flow-001",
            name = "Flow Project",
            phpMinVersion = "8.4",
            description = ""
        });
        var license = await PostJsonAsync<LicenseUpsertDto>("/api/v1/encoder/licenses/upsert", new
        {
            customerId = customer.CustomerId,
            projectId = project.ProjectId,
            licenseKey = "MM-FLOW-0001",
            validFrom = "2026-01-01T00:00:00Z",
            validUntil = "2028-01-01T00:00:00Z",
            maxActivations = 3,
            features = new[] { "base" }
        });

        Assert.True(license.Created);
        Assert.StartsWith("lic_", license.LicenseId);

        var build = await PostJsonAsync<BuildStartDto>("/api/v1/encoder/builds/start", new
        {
            projectId = project.ProjectId,
            customerId = customer.CustomerId,
            licenseId = license.LicenseId,
            version = "1.0.0",
            sourceRevision = "abc123",
            encoderVersion = "test"
        });

        Assert.StartsWith("build_", build.BuildId);
        Assert.False(string.IsNullOrEmpty(build.BuildKey));

        // Register a file
        var fileResp = await _client.PostAsJsonAsync(
            $"/api/v1/encoder/builds/{build.BuildId}/files", new
            {
                files = new[]
                {
                    new
                    {
                        fileId = "file_abc001",
                        relativePath = "src/App/Application.php",
                        pathHash = "sha256:aabbcc",
                        plainHash = "sha256:112233",
                        cipherHash = "sha256:445566",
                        algorithm = "AES-256-GCM",
                        kdf = "HKDF-SHA256"
                    }
                }
            });
        fileResp.EnsureSuccessStatusCode();

        // Sign manifest
        var manifestHash = "sha256:" + Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(new byte[] { 1, 2, 3 })).ToLowerInvariant();
        var signResp = await PostJsonAsync<ManifestSignDto>(
            $"/api/v1/encoder/builds/{build.BuildId}/manifest/sign", new
            {
                manifestHash,
                fileCount = 1
            });

        Assert.False(string.IsNullOrEmpty(signResp.ManifestSignature));
    }

    [Fact]
    public async Task RuntimeLease_GrantedForValidLicense()
    {
        // Set up the full build pipeline first
        var customer = await UpsertCustomerAsync("cref-lease-001", "Lease Customer");
        var project = await PostJsonAsync<ProjectUpsertDto>("/api/v1/encoder/projects/upsert", new
        {
            projectKey = "proj-lease-001",
            name = "Lease Project",
            phpMinVersion = "8.4",
            description = ""
        });
        var license = await PostJsonAsync<LicenseUpsertDto>("/api/v1/encoder/licenses/upsert", new
        {
            customerId = customer.CustomerId,
            projectId = project.ProjectId,
            licenseKey = "MM-LEASE-0001",
            validFrom = "2026-01-01T00:00:00Z",
            validUntil = "2028-01-01T00:00:00Z",
            maxActivations = 3,
            features = Array.Empty<string>()
        });
        var build = await PostJsonAsync<BuildStartDto>("/api/v1/encoder/builds/start", new
        {
            projectId = project.ProjectId,
            customerId = customer.CustomerId,
            licenseId = license.LicenseId,
            version = "1.0.0",
            sourceRevision = "HEAD",
            encoderVersion = "test"
        });

        var manifestHash = "sha256:" + Convert.ToHexString(
            System.Security.Cryptography.SHA256.HashData(
                System.Text.Encoding.UTF8.GetBytes("test-manifest-content"))).ToLowerInvariant();

        await _client.PostAsJsonAsync($"/api/v1/encoder/builds/{build.BuildId}/manifest/sign", new
        {
            manifestHash,
            fileCount = 0
        });

        // Now request a runtime lease (no API key auth for this endpoint)
        var leaseClient = _factory.CreateClient();
        var leaseResp = await leaseClient.PostAsJsonAsync("/api/v1/runtime/lease", new
        {
            projectId = project.ProjectId,
            customerId = customer.CustomerId,
            licenseId = license.LicenseId,
            buildId = build.BuildId,
            manifestHash,
            machineFingerprint = "sha256:" + new string('a', 64),
            nonce = Convert.ToBase64String(System.Security.Cryptography.RandomNumberGenerator.GetBytes(16))
        });

        leaseResp.EnsureSuccessStatusCode();
        var leaseBody = await leaseResp.Content.ReadAsStringAsync();
        Assert.Contains("MMENC-LEASE-1", leaseBody);
        Assert.Contains("runtimeKey", leaseBody);
    }

    // ---- Helpers ----

    private async Task<CustomerUpsertDto> UpsertCustomerAsync(string extRef, string name)
    {
        return await PostJsonAsync<CustomerUpsertDto>("/api/v1/encoder/customers/upsert", new
        {
            externalCustomerRef = extRef,
            name,
            email = "test@example.com",
            notes = ""
        });
    }

    private async Task<T> PostJsonAsync<T>(string url, object body)
    {
        var resp = await _client.PostAsJsonAsync(url, body);
        resp.EnsureSuccessStatusCode();
        var text = await resp.Content.ReadAsStringAsync();
        return JsonSerializer.Deserialize<T>(text, new JsonSerializerOptions { PropertyNameCaseInsensitive = true })!;
    }

    public void Dispose()
    {
        _client.Dispose();
        _factory.Dispose();
        if (File.Exists(_dbPath))
            File.Delete(_dbPath);
    }
}

// Dapper DateTime handler (same as in server Program.cs, duplicated here for test isolation)
internal sealed class DateTimeHandler : SqlMapper.TypeHandler<DateTime>
{
    public override void SetValue(System.Data.IDbDataParameter p, DateTime v) => p.Value = v.ToString("yyyy-MM-dd HH:mm:ss");
    public override DateTime Parse(object v) => DateTime.Parse(v.ToString()!, null, System.Globalization.DateTimeStyles.AssumeUniversal | System.Globalization.DateTimeStyles.AdjustToUniversal);
}

// Minimal DTO types for response deserialization (field names match server response JSON)
internal sealed record CustomerUpsertDto(string CustomerId, bool Created);
internal sealed record ProjectUpsertDto(string ProjectId, bool Created);
internal sealed record LicenseUpsertDto(string LicenseId, bool Created);
internal sealed record BuildStartDto(string BuildId, string KeyId, string BuildKey, string ManifestSalt);
internal sealed record ManifestSignDto(string ManifestSignature, string VendorPublicKeyId, DateTimeOffset ServerTimeUtc);
