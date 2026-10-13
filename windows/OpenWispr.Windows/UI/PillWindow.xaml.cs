using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;
using OpenWispr.Core;
using OpenWispr.Windows.Services;

namespace OpenWispr.Windows.UI;

/// <summary>Click-through, non-activating floating capsule at the bottom of the primary screen. Monochrome white on black.</summary>
public partial class PillWindow : Window
{
    private const int GWL_EXSTYLE = -20;
    private const int WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000;
    [DllImport("user32.dll")] private static extern int GetWindowLong(IntPtr hWnd, int nIndex);
    [DllImport("user32.dll")] private static extern int SetWindowLong(IntPtr hWnd, int nIndex, int dwNewLong);

    private readonly AppState _state;
    private readonly Settings _settings;
    private readonly Rectangle[] _bars;
    private bool _visible;

    public PillWindow(AppState state, Settings settings)
    {
        InitializeComponent();
        _state = state;
        _settings = settings;
        _bars = new Rectangle[state.Levels.Length];
        for (var i = 0; i < _bars.Length; i++)
        {
            _bars[i] = new Rectangle { Width = 3, Height = 4, RadiusX = 1.5, RadiusY = 1.5, Fill = Brushes.White, Margin = new Thickness(1, 0, 1, 0), VerticalAlignment = VerticalAlignment.Center };
            Bars.Children.Add(_bars[i]);
        }
        Dot.Fill = Brushes.White;
        SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            SetWindowLong(hwnd, GWL_EXSTYLE, GetWindowLong(hwnd, GWL_EXSTYLE) | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE);
        };
        state.Changed += () => Dispatcher.BeginInvoke(Sync);
        Opacity = 0;
    }

    private void Sync()
    {
        var shouldShow = _settings.ShowPill && _state.Phase != PipelinePhase.Idle;
        if (shouldShow)
        {
            Render();
            if (!_visible)
            {
                _visible = true;
                Reposition();
                Show();
                BeginAnimation(OpacityProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(180)));
            }
        }
        else if (_visible)
        {
            _visible = false;
            var fade = new DoubleAnimation(0, TimeSpan.FromMilliseconds(200));
            fade.Completed += (_, _) => { if (!_visible) Hide(); };
            BeginAnimation(OpacityProperty, fade);
        }
    }

    private void Render()
    {
        var recording = _state.Phase == PipelinePhase.Recording;
        Dot.Visibility = recording ? Visibility.Visible : Visibility.Collapsed;
        Bars.Visibility = recording ? Visibility.Visible : Visibility.Collapsed;
        for (var i = 0; i < _bars.Length; i++) _bars[i].Height = 4 + Math.Min(1, _state.Levels[i]) * 20;
        Label.Text = _state.Phase switch
        {
            PipelinePhase.Recording => _state.Mode == DictationMode.Command ? "Command" : (_state.HandsFree ? "Hands-free" : ""),
            PipelinePhase.Transcribing => "Transcribing…",
            PipelinePhase.Formatting => "Formatting…",
            PipelinePhase.Inserting => "Inserting…",
            PipelinePhase.Done => "✓ " + (_state.Message.Length == 0 ? "Done" : _state.Message),
            PipelinePhase.Notice => _state.Message,
            PipelinePhase.Error => "! " + _state.Message,
            _ => "",
        };
        Label.Visibility = Label.Text.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
    }

    private void Reposition()
    {
        var area = SystemParameters.WorkArea;
        Left = area.Left + (area.Width - Width) / 2;
        Top = area.Bottom - Height - 16;
    }
}
