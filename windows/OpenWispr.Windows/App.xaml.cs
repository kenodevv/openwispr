using System.Windows;
using OpenWispr.Windows.Services;

namespace OpenWispr.Windows;

public partial class App : Application
{
    private static Mutex? _singleInstance;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        if (e.Args.Contains(ReplayTool.Arg))
        {
            // Task.Run: awaiting on the WPF dispatcher here would deadlock.
            try { Task.Run(() => ReplayTool.RunAsync(e.Args)).GetAwaiter().GetResult(); }
            catch (Exception error) { FileLog.Write("Replay failed: " + error); }
            Environment.Exit(0);
        }
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
