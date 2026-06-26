using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace MmProtect.LicenseServer.Security;

public sealed class CryptoService
{
    private static readonly byte[] DemoSigningKey = SHA256.HashData(Encoding.UTF8.GetBytes("mmprotect-dev-signing-key"));

    public string SignForDemoOnly(string data)
    {
        using var hmac = new HMACSHA256(DemoSigningKey);
        return Convert.ToBase64String(hmac.ComputeHash(Encoding.UTF8.GetBytes(data)));
    }

    public string ProtectForDemoOnly(string value) => "demo:" + value;

    public string UnprotectForDemoOnly(string protectedValue)
        => protectedValue.StartsWith("demo:", StringComparison.Ordinal) ? protectedValue[5..] : protectedValue;
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
