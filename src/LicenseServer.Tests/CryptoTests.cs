using System.Security.Cryptography;
using System.Text;
using Microsoft.Extensions.Configuration;
using MmProtect.LicenseServer.Security;
using Xunit;

namespace MmProtect.LicenseServer.Tests;

public sealed class CryptoTests
{
    private static CryptoService MakeService(string? kekHex = null, string? signingKeyFile = null)
    {
        var dict = new Dictionary<string, string?>();
        if (kekHex != null)
            dict["Security:KeyEncryptionKey"] = kekHex;
        if (signingKeyFile != null)
            dict["Security:SigningPrivateKeyFile"] = signingKeyFile;

        var config = new ConfigurationBuilder()
            .AddInMemoryCollection(dict)
            .Build();
        return new CryptoService(config);
    }

    private static string RandomKekHex() =>
        Convert.ToHexString(RandomNumberGenerator.GetBytes(32));

    /* ── KEK: AES-256-GCM protect/unprotect ──────────────────────────────── */

    [Fact]
    public void Kek_ProtectAndUnprotect_RoundTrip()
    {
        var crypto = MakeService(kekHex: RandomKekHex());
        var original = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var encrypted = crypto.ProtectBuildKey(original);
        var recovered = crypto.UnprotectBuildKey(encrypted);
        Assert.Equal(original, recovered);
        Assert.True(crypto.HasKeyEncryptionKey);
    }

    [Fact]
    public void Kek_SameInput_DifferentCiphertext_EachCall()
    {
        var crypto = MakeService(kekHex: RandomKekHex());
        var key = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var c1 = crypto.ProtectBuildKey(key);
        var c2 = crypto.ProtectBuildKey(key);
        // Each call uses a fresh random nonce → ciphertexts must differ
        Assert.NotEqual(c1, c2);
    }

    [Fact]
    public void Kek_WrongKey_Throws_CryptographicException()
    {
        var cryptoA = MakeService(kekHex: RandomKekHex());
        var cryptoB = MakeService(kekHex: RandomKekHex());
        var key = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var ciphertext = cryptoA.ProtectBuildKey(key);
        // AuthenticationTagMismatchException is a subclass of CryptographicException
        Assert.ThrowsAny<CryptographicException>(() => cryptoB.UnprotectBuildKey(ciphertext));
    }

    [Fact]
    public void NoKek_Protect_UsesDemoPrefix()
    {
        var crypto = MakeService(); // no KEK configured
        var key = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var result = crypto.ProtectBuildKey(key);
        Assert.StartsWith("demo:", result);
        Assert.False(crypto.HasKeyEncryptionKey);
    }

    [Fact]
    public void NoKek_Unprotect_DemoPrefix_ReturnsKey()
    {
        var crypto = MakeService(); // no KEK configured
        var original = Convert.ToBase64String(RandomNumberGenerator.GetBytes(32));
        var stored = "demo:" + original;
        Assert.Equal(original, crypto.UnprotectBuildKey(stored));
    }

    [Fact]
    public void Kek_ShortBlob_Throws_CryptographicException()
    {
        var crypto = MakeService(kekHex: RandomKekHex());
        // Blob must be at least nonce(12) + tag(16) = 28 bytes; 5 bytes triggers the length guard
        var shortBlob = Convert.ToBase64String(new byte[5]);
        Assert.Throws<CryptographicException>(() => crypto.UnprotectBuildKey(shortBlob));
    }

    /* ── ECDSA-P256 signing ───────────────────────────────────────────────── */

    [Fact]
    public void Ecdsa_SignLease_VerifiableWithPublicKey()
    {
        using var ephemeral = ECDsa.Create(ECCurve.NamedCurves.nistP256);
        var privatePem = ephemeral.ExportPkcs8PrivateKeyPem();
        var publicKeyInfo = ephemeral.ExportSubjectPublicKeyInfo();

        var keyPath = Path.GetTempFileName();
        try
        {
            File.WriteAllText(keyPath, privatePem);
            var crypto = MakeService(signingKeyFile: keyPath);
            Assert.True(crypto.HasSigningKey);

            const string data = "test-lease-payload-ecdsa";
            var sig = crypto.SignLease(data);
            var sigBytes = Convert.FromBase64String(sig);

            using var verifier = ECDsa.Create();
            verifier.ImportSubjectPublicKeyInfo(publicKeyInfo, out _);
            Assert.True(verifier.VerifyData(
                Encoding.UTF8.GetBytes(data),
                sigBytes,
                HashAlgorithmName.SHA256,
                DSASignatureFormat.Rfc3279DerSequence));
        }
        finally
        {
            File.Delete(keyPath);
        }
    }

    [Fact]
    public void NoEcdsa_SignLease_UsesHmacFallback()
    {
        var crypto = MakeService(); // no signing key file
        Assert.False(crypto.HasSigningKey);

        const string data = "test-lease-payload-hmac";
        var sig = crypto.SignLease(data);

        var demoKey = SHA256.HashData(Encoding.UTF8.GetBytes("mmprotect-dev-signing-key"));
        using var hmac = new HMACSHA256(demoKey);
        var expected = Convert.ToBase64String(hmac.ComputeHash(Encoding.UTF8.GetBytes(data)));
        Assert.Equal(expected, sig);
    }
}
