using Xunit;
using MmProtect.EncoderCli.Encoding;

namespace MmProtect.EncoderCli.Tests;

public sealed class GlobTests
{
    [Theory]
    [InlineData("src/App/Application.php", "src/**/*.php", true)]
    [InlineData("vendor/autoload.php", "src/**/*.php", false)]
    [InlineData("public/index.php", "public/**", true)]
    [InlineData("vendor/composer/ClassLoader.php", "vendor/**", true)]
    [InlineData("vendor/autoload.php", "vendor/**", true)]
    [InlineData("src/deep/nested/file.php", "src/**/*.php", true)]
    [InlineData("config/app.php", "config/**", true)]
    [InlineData("composer.json", "composer.json", true)]
    [InlineData("composer.lock", "composer.lock", true)]
    [InlineData("public/assets/logo.png", "public/**", true)]
    [InlineData(".env", "vendor/**", false)]
    public void GlobMatchingWorks(string path, string pattern, bool expected)
    {
        Assert.Equal(expected, Glob.IsMatch(path, pattern));
    }

    [Fact]
    public void FileSelector_SelectsMatchingFiles()
    {
        var tmpRoot = Path.Combine(Path.GetTempPath(), "mmtest_fileselector_" + Path.GetRandomFileName());
        Directory.CreateDirectory(Path.Combine(tmpRoot, "src", "App"));
        Directory.CreateDirectory(Path.Combine(tmpRoot, "vendor"));
        Directory.CreateDirectory(Path.Combine(tmpRoot, "public"));

        File.WriteAllText(Path.Combine(tmpRoot, "src", "App", "Foo.php"), "<?php");
        File.WriteAllText(Path.Combine(tmpRoot, "vendor", "autoload.php"), "<?php");
        File.WriteAllText(Path.Combine(tmpRoot, "public", "index.php"), "<?php");

        try
        {
            var selected = FileSelector.SelectFiles(tmpRoot, ["src/**/*.php"], []);
            Assert.Single(selected);
            Assert.Contains("Foo.php", selected[0]);

            var copyPlain = FileSelector.SelectFiles(tmpRoot, ["public/**", "vendor/**"], []);
            Assert.Equal(2, copyPlain.Count);
        }
        finally
        {
            Directory.Delete(tmpRoot, recursive: true);
        }
    }
}
