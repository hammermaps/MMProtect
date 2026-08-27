using System.Text;
using Avalonia;
using Avalonia.Controls;
using Avalonia.Platform.Storage;
using Avalonia.Threading;
using MmProtect.EncoderCli.Configuration;
using MmProtect.EncoderCli.Gui;

namespace MmProtect.EncoderGui;

public partial class MainWindow : Window
{
    private readonly EncoderFacade _encoder = new();
    private CancellationTokenSource? _cancellation;

    public MainWindow()
    {
        InitializeComponent();
        ServerUrl.Text = "https://license.example.com";
        Version.Text = "0.1.0";
        PhpVersion.Text = "8.4";
        Optimize.Text = "none";
        Include.Text = "**/*.php";
        Exclude.Text = "vendor/**";
        CopyPlain.Text = "vendor/**\ncomposer.json\ncomposer.lock";
    }

    private async void ChooseSource(object? sender, Avalonia.Interactivity.RoutedEventArgs e) => SourceRoot.Text = await PickFolder();
    private async void ChooseOutput(object? sender, Avalonia.Interactivity.RoutedEventArgs e) => OutputRoot.Text = await PickFolder();

    private async Task<string?> PickFolder()
    {
        var folders = await StorageProvider.OpenFolderPickerAsync(new FolderPickerOpenOptions { Title = "Ordner auswählen", AllowMultiple = false });
        return folders.Count == 0 ? null : folders[0].Path.LocalPath;
    }

    private async void Import(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        var files = await StorageProvider.OpenFilePickerAsync(new FilePickerOpenOptions { Title = "Encoder-Konfiguration importieren", AllowMultiple = false, FileTypeFilter = [new FilePickerFileType("JSON") { Patterns = ["*.json"] }] });
        if (files.Count == 0) return;
        try { Apply(GuiProjectProfile.Import(files[0].Path.LocalPath)); RunStatus.Text = "CLI-Konfiguration importiert."; }
        catch (Exception ex) { RunStatus.Text = "Import fehlgeschlagen: " + ex.Message; }
    }

    private void LoadProfile(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        try { Apply(GuiProjectProfile.Load(RequireSourceRoot())); RunStatus.Text = "Projektprofil geladen."; }
        catch (Exception ex) { RunStatus.Text = "Laden fehlgeschlagen: " + ex.Message; }
    }

    private void Save(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        try { ReadProfile().Save(RequireSourceRoot()); RunStatus.Text = "Profil unter .mmprotect/gui-project.json gespeichert und zu .gitignore hinzugefügt."; }
        catch (Exception ex) { RunStatus.Text = "Speichern fehlgeschlagen: " + ex.Message; }
    }

    private async void Export(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        var file = await StorageProvider.SaveFilePickerAsync(new FilePickerSaveOptions { Title = "CLI-Konfiguration exportieren", SuggestedFileName = "encoder.config.json", DefaultExtension = "json", FileTypeChoices = [new FilePickerFileType("JSON") { Patterns = ["*.json"] }] });
        if (file is null) return;
        try { ReadProfile().ExportCliConfig(file.Path.LocalPath); RunStatus.Text = "CLI-kompatible Konfiguration exportiert. Sie enthält den API-Schlüssel – sicher aufbewahren."; }
        catch (Exception ex) { RunStatus.Text = "Export fehlgeschlagen: " + ex.Message; }
    }

    private void Preview(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        try
        {
            var profile = ReadProfile(); var preview = _encoder.Preview(profile.ToEncoderConfig(), profile.Project);
            IgnoreInfo.Text = preview.MmIgnoreFiles.Count == 0 ? "Keine .mmignore-Dateien erkannt." : "Erkannte .mmignore: " + string.Join(", ", preview.MmIgnoreFiles);
            RunStatus.Text = $"Vorabprüfung erfolgreich: {preview.EncodedPhpFiles} PHP-Datei(en) verschlüsseln, {preview.PlainFiles} Klartextdatei(en).\n" + string.Join("\n", preview.EncodedPaths.Take(30)) + (preview.EncodedPaths.Count > 30 ? "\n…" : "");
        }
        catch (Exception ex) { RunStatus.Text = "Vorabprüfung fehlgeschlagen: " + ex.Message; }
    }

    private async void Run(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        GuiProjectProfile profile;
        try { profile = ReadProfile(); _encoder.Validate(profile.ToEncoderConfig(), profile.Project); }
        catch (Exception ex) { RunStatus.Text = "Ungültige Eingabe: " + ex.Message; return; }
        if (Directory.Exists(profile.Project.OutputRoot) && Directory.EnumerateFileSystemEntries(profile.Project.OutputRoot).Any() && !await ConfirmReplace()) return;
        _cancellation = new CancellationTokenSource(); RunButton.IsEnabled = false; Log.Text = ""; Progress.Maximum = 1; Progress.Value = 0; RunStatus.Text = "Verschlüsselung läuft…";
        try
        {
            await _encoder.EncodeAsync(profile.ToEncoderConfig(), profile.Project, verbose: true, new UiLogWriter(this), _cancellation.Token, (done, total) => Dispatcher.UIThread.Post(() => { Progress.Maximum = total; Progress.Value = done; RunStatus.Text = $"Verschlüsselung läuft: {done}/{total} Dateien"; }));
            RunStatus.Text = "Erfolgreich abgeschlossen. Manifest und Lizenzdatei wurden im Zielordner angelegt.";
        }
        catch (OperationCanceledException) { RunStatus.Text = "Abgebrochen. Bereits geschriebene Zieldateien bleiben zur Prüfung erhalten."; }
        catch (Exception ex) { RunStatus.Text = "Verschlüsselung fehlgeschlagen: " + ex.Message; }
        finally { _cancellation.Dispose(); _cancellation = null; RunButton.IsEnabled = true; }
    }

    private void Cancel(object? sender, Avalonia.Interactivity.RoutedEventArgs e) => _cancellation?.Cancel();

    private void GenerateLicenseKey(object? sender, Avalonia.Interactivity.RoutedEventArgs e)
    {
        LicenseKey.Text = LicenseKeyGenerator.Create();
        RunStatus.Text = "Neuer lokaler Lizenzschlüssel erzeugt. Er wird erst beim Verschlüsselungslauf am License Server registriert.";
    }

    private async Task<bool> ConfirmReplace()
    {
        var result = false;
        var dialog = new Window { Title = "Zielordner ersetzen?", Width = 480, Height = 170, WindowStartupLocation = WindowStartupLocation.CenterOwner };
        var yes = new Button { Content = "Ersetzen und fortfahren", IsDefault = true };
        yes.Click += (_, _) => { result = true; dialog.Close(); };
        var no = new Button { Content = "Abbrechen", IsCancel = true };
        no.Click += (_, _) => dialog.Close();
        dialog.Content = new StackPanel { Margin = new Thickness(18), Spacing = 14, Children = { new TextBlock { Text = "Der Zielordner enthält bereits Dateien. Der Encoder kann diese Dateien überschreiben. Fortfahren?", TextWrapping = Avalonia.Media.TextWrapping.Wrap }, new StackPanel { Orientation = Avalonia.Layout.Orientation.Horizontal, Spacing = 8, HorizontalAlignment = Avalonia.Layout.HorizontalAlignment.Right, Children = { no, yes } } } };
        await dialog.ShowDialog(this); return result;
    }

    private GuiProjectProfile ReadProfile() => new()
    {
        LicenseServer = new LicenseServerOptions { BaseUrl = ServerUrl.Text?.Trim() ?? "", ApiKey = ApiKey.Text ?? "" },
        Defaults = new DefaultOptions { PhpMinVersion = PhpVersion.Text?.Trim() ?? "8.4", Compression = Selected(Compression), Optimize = Optimize.Text?.Trim(), Obfuscate = Obfuscate.IsChecked == true, PhpBinary = LintPhp.IsChecked == true ? PhpBinary.Text?.Trim() : null, DownloadUrl = DownloadUrl.Text?.Trim() },
        Project = new ProjectOptions { ProjectKey = ProjectKey.Text?.Trim() ?? "", Name = ProjectName.Text?.Trim() ?? "", Version = Version.Text?.Trim() ?? "0.1.0", SourceRoot = SourceRoot.Text?.Trim() ?? "", OutputRoot = OutputRoot.Text?.Trim() ?? "", Include = Lines(Include.Text), Exclude = Lines(Exclude.Text), CopyPlain = Lines(CopyPlain.Text), Customer = new CustomerOptions { ExternalCustomerRef = CustomerRef.Text?.Trim() ?? "", Name = CustomerName.Text?.Trim() ?? "", Email = CustomerEmail.Text?.Trim() }, License = new LicenseOptions { LicenseKey = LicenseKey.Text?.Trim() ?? "", Features = (Features.Text ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries) } }
    };

    private void Apply(GuiProjectProfile p)
    {
        ServerUrl.Text = p.LicenseServer.BaseUrl; ApiKey.Text = p.LicenseServer.ApiKey; ProjectKey.Text = p.Project.ProjectKey; ProjectName.Text = p.Project.Name; Version.Text = p.Project.Version; CustomerRef.Text = p.Project.Customer.ExternalCustomerRef; CustomerName.Text = p.Project.Customer.Name; CustomerEmail.Text = p.Project.Customer.Email; LicenseKey.Text = p.Project.License.LicenseKey; Features.Text = string.Join(",", p.Project.License.Features); SourceRoot.Text = p.Project.SourceRoot; OutputRoot.Text = p.Project.OutputRoot; Include.Text = string.Join("\n", p.Project.Include); Exclude.Text = string.Join("\n", p.Project.Exclude); CopyPlain.Text = string.Join("\n", p.Project.CopyPlain); PhpVersion.Text = p.Defaults.PhpMinVersion; PhpBinary.Text = p.Defaults.PhpBinary; DownloadUrl.Text = p.Defaults.DownloadUrl; Optimize.Text = p.Defaults.Optimize; Obfuscate.IsChecked = p.Defaults.Obfuscate; LintPhp.IsChecked = !string.IsNullOrWhiteSpace(p.Defaults.PhpBinary); Compression.SelectedIndex = string.Equals(p.Defaults.Compression, "lz4", StringComparison.OrdinalIgnoreCase) ? 1 : 0;
    }
    private string RequireSourceRoot() => !string.IsNullOrWhiteSpace(SourceRoot.Text) ? SourceRoot.Text : throw new InvalidOperationException("Bitte zuerst einen Quellordner auswählen.");
    private static List<string> Lines(string? text) => (text ?? "").Split('\n', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries).ToList();
    private static string? Selected(ComboBox box) => (box.SelectedItem as ComboBoxItem)?.Content?.ToString() is "none" ? null : (box.SelectedItem as ComboBoxItem)?.Content?.ToString();

    private sealed class UiLogWriter(MainWindow window) : TextWriter
    {
        public override Encoding Encoding => Encoding.UTF8;
        public override void WriteLine(string? value) => Dispatcher.UIThread.Post(() => window.Log.Text += (value ?? "") + Environment.NewLine);
    }
}
