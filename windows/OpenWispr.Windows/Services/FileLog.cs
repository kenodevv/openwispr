namespace OpenWispr.Windows.Services;

public static class FileLog
{
    public static readonly string Directory = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "OpenWispr");
    public static readonly string Path_ = Path.Combine(Directory, "OpenWispr.log");
    private static readonly object Gate = new();

    public static void Write(string message)
    {
        try
        {
            System.IO.Directory.CreateDirectory(Directory);
            lock (Gate) File.AppendAllText(Path_, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}  {message}{Environment.NewLine}");
        }
        catch { /* logging must never crash the app */ }
    }
}
