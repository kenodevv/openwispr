using System.Runtime.InteropServices;
using System.Windows;

namespace WhisperClaud.Windows.Services;

/// <summary>Pastes text via Ctrl+V while preserving the user's clipboard. Must run on the UI (STA) thread.</summary>
public static class TextInserter
{
    [StructLayout(LayoutKind.Sequential)]
    private struct INPUT { public uint type; public InputUnion u; }
    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion { [FieldOffset(0)] public KEYBDINPUT ki; [FieldOffset(0)] public MOUSEINPUT mi; }
    [StructLayout(LayoutKind.Sequential)]
    private struct KEYBDINPUT { public ushort wVk; public ushort wScan; public uint dwFlags; public uint time; public IntPtr dwExtraInfo; }
    [StructLayout(LayoutKind.Sequential)]
    private struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr dwExtraInfo; }
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
    private const uint INPUT_KEYBOARD = 1, KEYEVENTF_KEYUP = 0x0002;
    private const ushort VK_CONTROL = 0x11, VK_V = 0x56;

    public static async Task PasteAsync(string text)
    {
        IDataObject? saved = null;
        try { saved = Snapshot(Clipboard.GetDataObject()); } catch { }
        try { Clipboard.SetDataObject(text, true); } catch (Exception e) { FileLog.Write("clipboard set failed: " + e.Message); return; }
        SendCtrlV();
        await Task.Delay(400);
        if (saved is not null)
        {
            try { Clipboard.SetDataObject(saved, true); } catch { }
        }
    }

    private static IDataObject? Snapshot(IDataObject? source)
    {
        if (source is null) return null;
        var copy = new DataObject();
        var any = false;
        foreach (var format in source.GetFormats(false))
        {
            try
            {
                var data = source.GetData(format, false);
                if (data is null) continue;
                copy.SetData(format, data);
                any = true;
            }
            catch { }
        }
        return any ? copy : null;
    }

    private static void SendCtrlV()
    {
        INPUT Key(ushort vk, bool up) => new() { type = INPUT_KEYBOARD, u = new InputUnion { ki = new KEYBDINPUT { wVk = vk, dwFlags = up ? KEYEVENTF_KEYUP : 0 } } };
        var inputs = new[] { Key(VK_CONTROL, false), Key(VK_V, false), Key(VK_V, true), Key(VK_CONTROL, true) };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());
    }
}
