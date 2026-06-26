using System.Security.Cryptography;
using System.Text;

namespace MmProtect.EncoderCli.Encoding;

public static class CryptoPrimitives
{
    public static byte[] HkdfSha256(byte[] ikm, string info, int length)
    {
        var salt = SHA256.HashData(Encoding.UTF8.GetBytes("MMProtect-HKDF-v1"));
        return HKDF.DeriveKey(HashAlgorithmName.SHA256, ikm, length, salt, Encoding.UTF8.GetBytes(info));
    }
}

public static class Hashing
{
    public static string Sha256Hex(string text)
        => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text))).ToLowerInvariant();

    public static string Sha256Hex(byte[] bytes)
        => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();

    public static string ShortSha256(string text)
        => Sha256Hex(text)[..24];
}
