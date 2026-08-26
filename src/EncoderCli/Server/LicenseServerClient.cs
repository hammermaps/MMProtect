using System.Net.Http.Json;
using System.IO.Compression;
using System.Net.Http.Headers;
using System.Text.Json;

namespace MmProtect.EncoderCli.Server;

public sealed class LicenseServerClient
{
    // Keeps large registration batches and manifests below reverse-proxy body limits.
    // The server accepts both plain JSON and gzip-compressed JSON for backwards
    // compatibility with older encoders.
    private const int GzipThresholdBytes = 8 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
    private readonly HttpClient _http;

    public LicenseServerClient(HttpClient http, string apiKey)
    {
        _http = http;
        _http.DefaultRequestHeaders.Authorization =
            new System.Net.Http.Headers.AuthenticationHeaderValue("Bearer", apiKey);
    }

    public async Task<CustomerUpsertResponse> UpsertCustomerAsync(object request)
        => await PostAsync<CustomerUpsertResponse>("api/v1/encoder/customers/upsert", request);

    public async Task<ProjectUpsertResponse> UpsertProjectAsync(object request)
        => await PostAsync<ProjectUpsertResponse>("api/v1/encoder/projects/upsert", request);

    public async Task<LicenseUpsertResponse> UpsertLicenseAsync(object request)
        => await PostAsync<LicenseUpsertResponse>("api/v1/encoder/licenses/upsert", request);

    public async Task<BuildStartResponse> StartBuildAsync(object request)
        => await PostAsync<BuildStartResponse>("api/v1/encoder/builds/start", request);

    public async Task RegisterFilesAsync(string buildId, IReadOnlyCollection<FileRegistrationDto> files)
        => await PostAsync<JsonElement>($"api/v1/encoder/builds/{Uri.EscapeDataString(buildId)}/files", new { files });

    public async Task<ManifestSignResponse> SignManifestAsync(string buildId, object request)
        => await PostAsync<ManifestSignResponse>($"api/v1/encoder/builds/{Uri.EscapeDataString(buildId)}/manifest/sign", request);

    /// <summary>
    /// Fire-and-forget telemetry event. Never throws — telemetry failure must not break the build.
    /// </summary>
    public async Task SendTelemetryAsync(string eventType, string? buildId, string? projectId,
        string? licenseId, Dictionary<string, string>? data = null, string? endpointUrl = null)
    {
        try
        {
            var url = string.IsNullOrEmpty(endpointUrl) ? "api/v1/encoder/telemetry" : endpointUrl;
            var payload = new
            {
                source     = "encoder",
                eventType,
                licenseId,
                buildId,
                projectId,
                occurredAt = DateTimeOffset.UtcNow,
                data
            };
            using var content = CreateJsonContent(payload);
            using var response = await _http.PostAsync(url, content);
            // ignore status — telemetry is best-effort
        }
        catch { /* telemetry errors must never propagate */ }
    }

    private async Task<T> PostAsync<T>(string url, object body)
    {
        using var content = CreateJsonContent(body);
        using var response = await _http.PostAsync(url, content);
        var text = await response.Content.ReadAsStringAsync();

        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"Serverfehler {response.StatusCode}: {text}");

        var result = JsonSerializer.Deserialize<T>(text, JsonOptions);
        return result ?? throw new InvalidOperationException($"Leere Serverantwort für {url}");
    }

    private static HttpContent CreateJsonContent(object body)
    {
        var json = JsonSerializer.SerializeToUtf8Bytes(body, JsonOptions);
        if (json.Length < GzipThresholdBytes)
            return CreateContent(json, isGzip: false);

        using var compressed = new MemoryStream();
        using (var gzip = new GZipStream(compressed, CompressionLevel.Fastest, leaveOpen: true))
            gzip.Write(json);

        return CreateContent(compressed.ToArray(), isGzip: true);
    }

    private static ByteArrayContent CreateContent(byte[] bytes, bool isGzip)
    {
        var content = new ByteArrayContent(bytes);
        content.Headers.ContentType = new MediaTypeHeaderValue("application/json");
        if (isGzip)
            content.Headers.ContentEncoding.Add("gzip");
        return content;
    }
}

public sealed record CustomerUpsertResponse(string CustomerId, bool Created);
public sealed record ProjectUpsertResponse(string ProjectId, bool Created);
public sealed record LicenseUpsertResponse(string LicenseId, bool Created);
public sealed record BuildStartResponse(string BuildId, string KeyId, string BuildKey, string ManifestSalt);
public sealed record ManifestSignResponse(string ManifestSignature, string VendorPublicKeyId, DateTimeOffset ServerTimeUtc);
public sealed record FileRegistrationDto(
    string FileId,
    string RelativePath,
    string PathHash,
    string PlainHash,
    string CipherHash,
    string Algorithm,
    string Kdf);
