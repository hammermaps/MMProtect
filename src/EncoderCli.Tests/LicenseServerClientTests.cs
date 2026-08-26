using System.IO.Compression;
using System.Net;
using System.Net.Http.Json;
using System.Text;
using MmProtect.EncoderCli.Server;
using Xunit;

namespace MmProtect.EncoderCli.Tests;

public sealed class LicenseServerClientTests
{
    [Fact]
    public async Task LargeJsonRequest_IsSentAsGzipAndKeepsItsJsonPayload()
    {
        var handler = new CapturingHandler();
        using var http = new HttpClient(handler) { BaseAddress = new Uri("https://license.example.test/") };
        var client = new LicenseServerClient(http, "test-key");

        await client.UpsertCustomerAsync(new
        {
            externalCustomerRef = "gzip-test",
            name = new string('x', 16 * 1024),
            email = "test@example.invalid",
            notes = "large request"
        });

        Assert.True(handler.WasGzip);
        Assert.Contains("gzip-test", handler.JsonPayload);
        Assert.Contains("\"name\"", handler.JsonPayload);
    }

    private sealed class CapturingHandler : HttpMessageHandler
    {
        public bool WasGzip { get; private set; }
        public string JsonPayload { get; private set; } = "";

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            WasGzip = request.Content!.Headers.ContentEncoding.Contains("gzip", StringComparer.OrdinalIgnoreCase);
            var bytes = await request.Content.ReadAsByteArrayAsync(cancellationToken);

            if (WasGzip)
            {
                using var input = new MemoryStream(bytes);
                using var gzip = new GZipStream(input, CompressionMode.Decompress);
                using var output = new MemoryStream();
                await gzip.CopyToAsync(output, cancellationToken);
                bytes = output.ToArray();
            }

            JsonPayload = System.Text.Encoding.UTF8.GetString(bytes);
            return new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = JsonContent.Create(new { customerId = "cust_test", created = true })
            };
        }
    }
}
