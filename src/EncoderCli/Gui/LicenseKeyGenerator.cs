using System.Security.Cryptography;

namespace MmProtect.EncoderCli.Gui;

/// <summary>Creates human-readable, cryptographically random license keys without server-side state.</summary>
public static class LicenseKeyGenerator
{
    private const string Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

    public static string Create(string prefix = "MM", int groups = 4, int charactersPerGroup = 5)
    {
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(groups);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(charactersPerGroup);
        var chunks = new string[groups];
        for (var group = 0; group < groups; group++)
        {
            var chars = new char[charactersPerGroup];
            for (var i = 0; i < chars.Length; i++) chars[i] = Alphabet[RandomNumberGenerator.GetInt32(Alphabet.Length)];
            chunks[group] = new string(chars);
        }
        return prefix.Trim().ToUpperInvariant() + "-" + string.Join("-", chunks);
    }
}
