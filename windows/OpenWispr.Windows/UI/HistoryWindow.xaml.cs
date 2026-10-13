using System.Windows;
using System.Windows.Controls;
using OpenWispr.Core;
using OpenWispr.Windows.Services;

namespace OpenWispr.Windows.UI;

public partial class HistoryWindow : Window
{
    private readonly AppContainer _container;
    private List<DictationEntry> _entries = new();

    public HistoryWindow(AppContainer container)
    {
        InitializeComponent();
        _container = container;
        Reload();
    }

    private void Reload()
    {
        _entries = _container.Store.History();
        var stats = Store.Stats(_entries);
        StatDictations.Text = stats.Dictations.ToString();
        StatWords.Text = stats.Words.ToString();
        StatWpm.Text = stats.AverageWpm.ToString("F0");
        StatSaved.Text = stats.MinutesSaved < 60 ? $"{stats.MinutesSaved:F0} min" : $"{stats.MinutesSaved / 60:F1} h";
        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var q = Search.Text.Trim();
        List.ItemsSource = q.Length == 0 ? _entries : _entries.Where(e =>
            e.FinalText.Contains(q, StringComparison.OrdinalIgnoreCase) || e.RawTranscript.Contains(q, StringComparison.OrdinalIgnoreCase) || e.AppName.Contains(q, StringComparison.OrdinalIgnoreCase)).ToList();
    }

    private void Search_TextChanged(object sender, TextChangedEventArgs e) => ApplyFilter();

    private void List_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (List.SelectedItem is not DictationEntry entry) { Detail.Visibility = Visibility.Collapsed; return; }
        Detail.Visibility = Visibility.Visible;
        DetailMeta.Text = $"{entry.AppName} · {entry.Date:dd.MM.yyyy HH:mm} · {entry.AudioSeconds:F1} s audio · {entry.LatencyMs} ms · {entry.Model}";
        DetailFinal.Text = entry.FinalText;
        DetailRaw.Text = entry.RawTranscript;
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (List.SelectedItem is not DictationEntry entry) return;
        _container.Store.DeleteEntry(entry.Id);
        Reload();
    }

    private void CopyFinal_Click(object sender, RoutedEventArgs e) => Clipboard.SetText(DetailFinal.Text);
    private void CopyRaw_Click(object sender, RoutedEventArgs e) => Clipboard.SetText(DetailRaw.Text);
}
