using System.Windows;
using System.Windows.Controls;
using WhisperClaud.Core;
using WhisperClaud.Windows.Services;

namespace WhisperClaud.Windows.UI;

public partial class SettingsWindow : Window
{
    private readonly AppContainer _container;
    private Settings S => _container.Settings;
    private bool _loading = true;

    private sealed record Choice<T>(T Value, string Label) { public override string ToString() => Label; }
    private sealed record TermRow(DictionaryTerm Term) { public string MisspellingsText => string.Join(", ", Term.Misspellings); }

    public SettingsWindow(AppContainer container)
    {
        InitializeComponent();
        _container = container;
        Closing += (_, e) => { e.Cancel = true; Hide(); };
        FillLists();
        LoadFromSettings();
        _loading = false;
        _container.State.Changed += () => Dispatcher.BeginInvoke(UpdateStatus);
        UpdateStatus();
    }

    private void FillLists()
    {
        HotkeyBox.ItemsSource = Enum.GetValues<HotkeyChoice>().Select(h => new Choice<HotkeyChoice>(h, AppContainer.HotkeyLabel(h) + " halten")).ToList();
        ModeBox.ItemsSource = new[] { new Choice<HotkeyMode>(HotkeyMode.PushToTalk, "Halten zum Sprechen (Push-to-Talk)"), new Choice<HotkeyMode>(HotkeyMode.Toggle, "Drücken zum Starten, nochmal zum Stoppen") };
        var mics = new List<Choice<int>> { new(-1, "Systemstandard") };
        mics.AddRange(AudioRecorder.InputDevices().Select(d => new Choice<int>(d.Number, d.Name)));
        MicBox.ItemsSource = mics;
        LanguageBox.ItemsSource = new[] { new Choice<DictationLanguage>(DictationLanguage.Auto, "Sprache automatisch erkennen"), new Choice<DictationLanguage>(DictationLanguage.De, "Deutsch"), new Choice<DictationLanguage>(DictationLanguage.En, "Englisch") };
        BackendBox.ItemsSource = new[]
        {
            new Choice<FormatterBackend>(FormatterBackend.Claude, "Claude (beste Qualität, API-Guthaben)"),
            new Choice<FormatterBackend>(FormatterBackend.Ollama, "Ollama – lokales LLM, kostenlos"),
            new Choice<FormatterBackend>(FormatterBackend.RulesOnly, "Nur Regeln – kostenlos, sofort, ohne KI"),
        };
        ModelBox.ItemsSource = new[]
        {
            new Choice<string>(ClaudeModels.Haiku, "Claude Haiku 5.5 – am schnellsten und günstigsten"),
            new Choice<string>(ClaudeModels.Sonnet, "Claude Sonnet 5.5 – schnell"),
            new Choice<string>(ClaudeModels.Opus, "Claude Opus 5.5 – beste Qualität"),
        };
        EffortBox.ItemsSource = new[] { new Choice<string>("low", "Effort: niedrig (schnellste Antwort)"), new Choice<string>("medium", "Effort: mittel"), new Choice<string>("high", "Effort: hoch") };
    }

    private void LoadFromSettings()
    {
        Select(HotkeyBox, S.Hotkey); Select(ModeBox, S.HotkeyMode); Select(MicBox, S.InputDeviceNumber); Select(LanguageBox, S.Language);
        Select(BackendBox, S.Backend); Select(ModelBox, S.Model); Select(EffortBox, S.Effort);
        TapHandsFree.IsChecked = S.TapForHandsFree; AutoStop.IsChecked = S.HandsFreeAutoStop; SilenceSlider.Value = S.HandsFreeSilenceSeconds;
        Sounds.IsChecked = S.PlaySounds; ShowPillBox.IsChecked = S.ShowPill; LaunchAtLogin.IsChecked = S.LaunchAtLogin;
        ContextBox.IsChecked = S.ContextAwareness; PrivacyBox.IsChecked = S.PrivacyMode;
        OllamaUrlBox.Text = S.OllamaUrl; OllamaModelBox.Text = S.OllamaModel;
        var creds = Credentials.Load();
        ApiKeyBox.Password = creds?.ApiKey ?? "";
        WorkspaceBox.Text = creds?.WorkspaceId ?? "";
        ReloadDictionary();
        ReloadSnippets();
        UpdateBackendPanels();
    }

    private static void Select<T>(ComboBox box, T value)
    {
        foreach (var item in box.Items)
            if (item is Choice<T> c && EqualityComparer<T>.Default.Equals(c.Value, value)) { box.SelectedItem = item; return; }
        if (box.Items.Count > 0) box.SelectedIndex = 0;
    }

    private static T Value<T>(ComboBox box, T fallback) => box.SelectedItem is Choice<T> c ? c.Value : fallback;

    private void Any_Changed(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        S.Hotkey = Value(HotkeyBox, S.Hotkey); S.HotkeyMode = Value(ModeBox, S.HotkeyMode); S.InputDeviceNumber = Value(MicBox, -1);
        S.Language = Value(LanguageBox, S.Language); S.Model = Value(ModelBox, S.Model); S.Effort = Value(EffortBox, S.Effort);
        S.TapForHandsFree = TapHandsFree.IsChecked == true; S.HandsFreeAutoStop = AutoStop.IsChecked == true; S.HandsFreeSilenceSeconds = SilenceSlider.Value;
        S.PlaySounds = Sounds.IsChecked == true; S.ShowPill = ShowPillBox.IsChecked == true; S.LaunchAtLogin = LaunchAtLogin.IsChecked == true;
        S.ContextAwareness = ContextBox.IsChecked == true; S.PrivacyMode = PrivacyBox.IsChecked == true;
        S.OllamaUrl = OllamaUrlBox.Text.Trim(); S.OllamaModel = OllamaModelBox.Text.Trim();
        S.OnboardingCompleted = true;
        S.Save();
        _container.ApplyHotkeySetting();
        UpdateStatus();
    }

    private void Backend_Changed(object sender, SelectionChangedEventArgs e)
    {
        if (_loading) return;
        S.Backend = Value(BackendBox, S.Backend);
        UpdateBackendPanels();
        Any_Changed(sender, e);
    }

    private void UpdateBackendPanels()
    {
        ClaudePanel.Visibility = S.Backend == FormatterBackend.Claude ? Visibility.Visible : Visibility.Collapsed;
        OllamaPanel.Visibility = S.Backend == FormatterBackend.Ollama ? Visibility.Visible : Visibility.Collapsed;
    }

    private void SaveKey_Click(object sender, RoutedEventArgs e)
    {
        Credentials.Save(ApiKeyBox.Password, WorkspaceBox.Text);
        _container.State.HasApiKey = Credentials.Load() is not null;
        KeyStatus.Text = _container.State.HasApiKey ? "Key gespeichert" : "Kein Key";
        S.OnboardingCompleted = true;
        S.Save();
    }

    private async void TestConnection_Click(object sender, RoutedEventArgs e)
    {
        SaveKey_Click(sender, e);
        var formatter = _container.Pipeline.FormatterForTest();
        if (formatter is null) { TestResult.Text = "Kein Key gespeichert bzw. Engine ohne LLM."; return; }
        TestButton.IsEnabled = false;
        TestResult.Text = "Teste…";
        try
        {
            var result = await formatter.CompleteAsync(FlowPrompts.DictationSystem, "", FlowPrompts.DictationUser("ähm das ist ein test"), 64, CancellationToken.None);
            TestResult.Text = $"✓ {result.Model} · {result.LatencyMs} ms · Antwort: „{result.Text}“";
        }
        catch (Exception ex) { TestResult.Text = "✗ " + ex.Message; }
        TestButton.IsEnabled = true;
    }

    private void ReloadDictionary() => DictList.ItemsSource = _container.Store.Dictionary.Select(t => new TermRow(t)).ToList();
    private void ReloadSnippets() => SnippetList.ItemsSource = _container.Store.Snippets.ToList();

    private void AddTerm_Click(object sender, RoutedEventArgs e)
    {
        var term = NewTerm.Text.Trim();
        if (term.Length == 0) return;
        var wrong = NewMisspellings.Text.Split(',').Select(x => x.Trim()).Where(x => x.Length > 0).ToList();
        _container.Store.Dictionary.Add(new DictionaryTerm(term, wrong));
        _container.Store.SaveDictionary();
        NewTerm.Clear(); NewMisspellings.Clear();
        ReloadDictionary();
    }

    private void RemoveTerm_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is TermRow row) { _container.Store.Dictionary.Remove(row.Term); _container.Store.SaveDictionary(); ReloadDictionary(); }
    }

    private void AddSnippet_Click(object sender, RoutedEventArgs e)
    {
        var trigger = SnippetTrigger.Text.Trim(); var content = SnippetContent.Text.Trim();
        if (trigger.Length == 0 || content.Length == 0) return;
        _container.Store.Snippets.Add(new SnippetDef(trigger, content));
        _container.Store.SaveSnippets();
        SnippetTrigger.Clear(); SnippetContent.Clear();
        ReloadSnippets();
    }

    private void RemoveSnippet_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is SnippetDef s) { _container.Store.Snippets.Remove(s); _container.Store.SaveSnippets(); ReloadSnippets(); }
    }

    private void ClearHistory_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("Gesamten Verlauf löschen?", "WhisperClaud", MessageBoxButton.YesNo, MessageBoxImage.Warning) == MessageBoxResult.Yes)
            _container.Store.ClearHistory();
    }

    private void UpdateStatus()
    {
        var st = _container.State;
        TestHint.Text = $"Klick in das Feld, halte {AppContainer.HotkeyLabel(S.Hotkey)}, sprich einen Satz mit „ähm“ drin und lass los. Kurz antippen startet Freisprechen.";
        TestChecks.Text = $"{(st.HotkeyActive ? "✅" : "❌")} Tastatur-Hook   {(st.ModelPhase == ModelPhase.Ready ? "✅" : "⏳")} Sprachmodell {st.ModelLabel}   {(st.HasApiKey ? "✅" : "❌")} Claude-Key";
        TestStatus.Text = st.Phase switch
        {
            PipelinePhase.Idle => st.Events.LastOrDefault() ?? "Warte auf Hotkey…",
            PipelinePhase.Recording => st.HandsFree ? "Freisprechen – Aufnahme läuft…" : "Aufnahme läuft… (Taste loslassen zum Beenden)",
            PipelinePhase.Transcribing => "Transkribiere lokal…",
            PipelinePhase.Formatting => "Formatiere…",
            PipelinePhase.Inserting => "Füge ein…",
            PipelinePhase.Done => "Fertig: " + st.Message,
            _ => st.Message,
        };
        if (st.LastError is { } err) TestStatus.Text += "\n⚠ " + err;
        KeyStatus.Text = st.HasApiKey ? "Key gespeichert" : "Kein Key";
    }
}
