using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace MmProtect.LicenseServer.Security;

public sealed class CryptoService
{
    private static readonly byte[] DemoSigningKey =
        SHA256.HashData(Encoding.UTF8.GetBytes("mmprotect-dev-signing-key"));

    /* Week 4: ECDSA-P256 private key — null when not configured */
    private readonly ECDsa? _ecKey;

    public CryptoService(IConfiguration config)
    {
        var keyFile = config["Security:SigningPrivateKeyFile"];
        if (!string.IsNullOrWhiteSpace(keyFile) && File.Exists(keyFile))
        {
            try
            {
                var pem = File.ReadAllText(keyFile);
                var ecdsa = ECDsa.Create(ECCurve.NamedCurves.nistP256);
                ecdsa.ImportFromPem(pem);
                _ecKey = ecdsa;
            }
            catch (Exception ex)
            {
                /* Fall back to demo HMAC — log the warning, never rethrow */
                Console.Error.WriteLine(
                    $"[mmprotect] WARNING: could not load signing key from {keyFile}: {ex.Message}");
            }
        }
    }

    /*
     * Sign data for the lease response.
     *
     * With ECDSA key configured (Week 4):
     *   Returns Base64(ECDSA-P256-DER(SHA-256(data)))
     *
     * Without key (demo fallback):
     *   Returns Base64(HMAC-SHA256(demoKey, data))
     */
    public string SignForDemoOnly(string data)
    {
        var bytes = Encoding.UTF8.GetBytes(data);

        if (_ecKey != null)
        {
            var sig = _ecKey.SignData(bytes, HashAlgorithmName.SHA256,
                                      DSASignatureFormat.Rfc3279DerSequence);
            return Convert.ToBase64String(sig);
        }

        using var hmac = new HMACSHA256(DemoSigningKey);
        return Convert.ToBase64String(hmac.ComputeHash(bytes));
    }

    public string ProtectForDemoOnly(string value) => "demo:" + value;

    public string UnprotectForDemoOnly(string protectedValue)
        => protectedValue.StartsWith("demo:", StringComparison.Ordinal)
            ? protectedValue[5..]
            : protectedValue;
}

public static class Ids
{
    public static string NewId() => Guid.NewGuid().ToString("N");
}

public static class JsonCanonical
{
    public static string Serialize<T>(T value)
        => JsonSerializer.Serialize(value, new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = false
        });
}
