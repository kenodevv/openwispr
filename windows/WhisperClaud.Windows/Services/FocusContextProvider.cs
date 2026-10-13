using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Windows.Automation;
using WhisperClaud.Core;

namespace WhisperClaud.Windows.Services;

/// <summary>Reads the foreground app and (best effort, via UI Automation) the focused text field.</summary>
public static class FocusContextProvider
{
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    public static FocusContext Capture(bool readText)
    {
        var hwnd = GetForegroundWindow();
        var appName = ""; var appId = ""; var title = "";
        if (hwnd != IntPtr.Zero)
        {
            GetWindowThreadProcessId(hwnd, out var pid);
            try
            {
                using var process = Process.GetProcessById((int)pid);
                appId = process.ProcessName;
                appName = string.IsNullOrWhiteSpace(process.MainWindowTitle) ? process.ProcessName : process.ProcessName;
            }
            catch { }
            var sb = new StringBuilder(512);
            GetWindowText(hwnd, sb, sb.Capacity);
            title = sb.ToString();
        }
        var selected = ""; var before = ""; var secure = false;
        if (readText)
        {
            var task = Task.Run(() => ReadFocusedText());
            if (task.Wait(TimeSpan.FromMilliseconds(400))) (selected, before, secure) = task.Result;
        }
        return new FocusContext { AppName = appName, AppId = appId, WindowTitle = title, SelectedText = selected, TextBeforeCursor = before, IsSecureField = secure };
    }

    private static (string Selected, string Before, bool Secure) ReadFocusedText()
    {
        try
        {
            var element = AutomationElement.FocusedElement;
            if (element is null) return ("", "", false);
            if (element.Current.IsPassword) return ("", "", true);
            if (!element.TryGetCurrentPattern(TextPattern.Pattern, out var patternObj) || patternObj is not TextPattern text) return ("", "", false);
            var selection = text.GetSelection();
            if (selection.Length == 0) return ("", "", false);
            var range = selection[0];
            var selected = range.GetText(6000) ?? "";
            var beforeRange = range.Clone();
            beforeRange.MoveEndpointByRange(TextPatternRangeEndpoint.End, range, TextPatternRangeEndpoint.Start);
            beforeRange.MoveEndpointByUnit(TextPatternRangeEndpoint.Start, TextUnit.Character, -500);
            var before = beforeRange.GetText(500) ?? "";
            return (selected, before, false);
        }
        catch { return ("", "", false); }
    }
}
