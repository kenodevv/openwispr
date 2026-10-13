using System.Windows;
using OpenWispr.Windows.Services;

namespace OpenWispr.Windows;

public partial class App : Application
{
    private static Mutex? _singleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        _singleInstance = new Mutex(true, "OpenWispr.SingleInstance", out var created);
        if (!created)
        {
            MessageBox.Show("OpenWispr is already running (see the system tray).", "OpenWispr");
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
