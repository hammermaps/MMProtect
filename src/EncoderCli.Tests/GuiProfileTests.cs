using MmProtect.EncoderCli.Configuration;
using MmProtect.EncoderCli.Gui;
using Xunit;

namespace MmProtect.EncoderCli.Tests;

public sealed class GuiProfileTests
{
    [Fact]
    public void LicenseKeyGeneratorCreatesReadableUniqueKeys()
    {
        var key = LicenseKeyGenerator.Create();
        Assert.Matches("^MM-[A-Z2-9]{5}(-[A-Z2-9]{5}){3}$", key);
        Assert.NotEqual(key, LicenseKeyGenerator.Create());
    }

    [Fact]
    public void ProfileRoundTripExportsCliShapeAndIgnoresSecretProfile()
    {
        var root = Path.Combine(Path.GetTempPath(), "mmprotect_gui_" + Guid.NewGuid()); Directory.CreateDirectory(root);
        try
        {
            var profile = Profile(root); profile.Save(root);
            var loaded = GuiProjectProfile.Load(root);
            var export = Path.Combine(root, "encoder.json"); loaded.ExportCliConfig(export);
            Assert.Equal("secret", loaded.LicenseServer.ApiKey);
            Assert.Equal("demo", EncoderConfigLoader.Load(export).Projects.Single().ProjectKey);
            Assert.Contains(GuiProjectProfile.RelativePath, File.ReadAllText(Path.Combine(root, ".gitignore")));
            if (!OperatingSystem.IsWindows()) Assert.Equal(UnixFileMode.UserRead | UnixFileMode.UserWrite, File.GetUnixFileMode(Path.Combine(root, GuiProjectProfile.RelativePath)));
        }
        finally { Directory.Delete(root, true); }
    }

    [Fact]
    public void ValidationRejectsIdenticalSourceAndOutput()
    {
        var root = Path.Combine(Path.GetTempPath(), "mmprotect_gui_" + Guid.NewGuid()); Directory.CreateDirectory(root);
        try
        {
            var profile = Profile(root); profile.Project.OutputRoot = root;
            Assert.Throws<InvalidOperationException>(() => new EncoderFacade().Validate(profile.ToEncoderConfig(), profile.Project));
        }
        finally { Directory.Delete(root, true); }
    }

    private static GuiProjectProfile Profile(string root) => new()
    {
        LicenseServer = new LicenseServerOptions { BaseUrl = "https://license.example.invalid", ApiKey = "secret" },
        Project = new ProjectOptions { ProjectKey = "demo", Name = "Demo", SourceRoot = root, OutputRoot = Path.Combine(root, "out"), Customer = new CustomerOptions { ExternalCustomerRef = "c", Name = "Customer" }, License = new LicenseOptions { LicenseKey = "license" } }
    };
}
