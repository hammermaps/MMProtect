using MmProtect.EncoderCli.Encoding;

namespace MmProtect.EncoderCli.Tests;

public sealed class GlobTests
{
    [Theory]
    [InlineData("src/App/Application.php", "src/**/*.php", true)]
    [InlineData("vendor/autoload.php", "src/**/*.php", false)]
    [InlineData("public/index.php", "public/**", true)]
    public void GlobMatchingWorks(string path, string pattern, bool expected)
    {
        Assert.Equal(expected, Glob.IsMatch(path, pattern));
    }
}
