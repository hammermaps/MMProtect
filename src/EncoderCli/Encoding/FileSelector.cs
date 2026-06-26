using System.Text.RegularExpressions;

namespace MmProtect.EncoderCli.Encoding;

public static class FileSelector
{
    public static List<string> SelectFiles(string root, List<string> include, List<string> exclude)
    {
        root = Path.GetFullPath(root);

        var allFiles = Directory.EnumerateFiles(root, "*", SearchOption.AllDirectories)
            .Select(Path.GetFullPath)
            .ToList();

        return allFiles
            .Where(path =>
            {
                var rel = Path.GetRelativePath(root, path).Replace('\\', '/');
                var included = include.Count == 0 || include.Any(p => Glob.IsMatch(rel, p));
                var excluded = exclude.Any(p => Glob.IsMatch(rel, p));
                return included && !excluded;
            })
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(x => x, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }
}

public static class Glob
{
    public static bool IsMatch(string path, string pattern)
    {
        path = path.Replace('\\', '/');
        pattern = pattern.Replace('\\', '/');

        var regex = "^" + Regex.Escape(pattern)
            .Replace("\\*\\*", "§DOUBLESTAR§")
            .Replace("\\*", "[^/]*")
            .Replace("§DOUBLESTAR§", ".*")
            .Replace("\\?", ".") + "$";

        return Regex.IsMatch(path, regex, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    }
}
