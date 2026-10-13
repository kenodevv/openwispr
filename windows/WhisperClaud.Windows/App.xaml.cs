using System.Windows;
using WhisperClaud.Windows.Services;

namespace WhisperClaud.Windows;

public partial class App : Application
{
    private static Mutex? _singleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _singleInstance = new Mutex(true, "WhisperClaud.SingleInstance", out var created);
        if (!created)
        {
            MessageBox.Show("WhisperClaud is already running (see the system tray).", "WhisperClaud");
            Shutdown();
            return;
        }
        DispatcherUnhandledException += (_, args) =>
        {
            FileLog.Write("CRASH " + args.Exception);
            args.Handled = true;
        };
        AppContainer.Shared.Boot();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        AppContainer.Shared.Shutdown();
        base.OnExit(e);
    }
}
