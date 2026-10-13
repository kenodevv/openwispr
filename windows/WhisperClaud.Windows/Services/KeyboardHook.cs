using System.Diagnostics;
using System.Runtime.InteropServices;
using WhisperClaud.Core;

namespace WhisperClaud.Windows.Services;

/// <summary>Low-level keyboard hook (WH_KEYBOARD_LL). Fires press/release for the configured hold-to-talk key.</summary>
public sealed class KeyboardHook : IDisposable
{
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100, WM_KEYUP = 0x0101, WM_SYSKEYDOWN = 0x0104, WM_SYSKEYUP = 0x0105;
    private const int VK_LWIN = 0x5B, VK_RWIN = 0x5C, VK_LCONTROL = 0xA2, VK_RCONTROL = 0xA3, VK_LMENU = 0xA4, VK_RMENU = 0xA5, VK_F13 = 0x7C, VK_SHIFT = 0x10;

    private delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool UnhookWindowsHookEx(IntPtr hhk);
    [DllImport("user32.dll")] private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    [DllImport("kernel32.dll")] private static extern IntPtr GetModuleHandle(string? lpModuleName);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int vKey);

    public event Action<DictationMode>? Pressed;
    public event Action? Released;
    public HotkeyChoice Choice { get; set; } = HotkeyChoice.CtrlWin;
    public bool IsActive => _hook != IntPtr.Zero;

    private IntPtr _hook;
    private LowLevelKeyboardProc? _proc;
    private bool _ctrl, _win, _down;

    public bool Start()
    {
        if (_hook != IntPtr.Zero) return true;
        _proc = Callback;
        using var module = Process.GetCurrentProcess().MainModule;
        _hook = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(module?.ModuleName), 0);
        if (_hook == IntPtr.Zero) FileLog.Write("SetWindowsHookEx failed: " + Marshal.GetLastWin32Error());
        return _hook != IntPtr.Zero;
    }

    private IntPtr Callback(int nCode, IntPtr wParam, IntPtr lParam)
    {
        if (nCode >= 0)
        {
            var vk = Marshal.ReadInt32(lParam);
            var msg = (int)wParam;
            var isDown = msg is WM_KEYDOWN or WM_SYSKEYDOWN;
            var isUp = msg is WM_KEYUP or WM_SYSKEYUP;
            if (isDown || isUp) Track(vk, isDown);
        }
        return CallNextHookEx(_hook, nCode, wParam, lParam);
    }

    private void Track(int vk, bool isDown)
    {
        if (vk is VK_LCONTROL or VK_RCONTROL) _ctrl = isDown || (vk == VK_LCONTROL ? IsPressed(VK_RCONTROL) : IsPressed(VK_LCONTROL));
        if (vk is VK_LWIN or VK_RWIN) _win = isDown || (vk == VK_LWIN ? IsPressed(VK_RWIN) : IsPressed(VK_LWIN));

        var active = Choice switch
        {
            HotkeyChoice.CtrlWin => _ctrl && _win,
            HotkeyChoice.RightCtrl => vk == VK_RCONTROL ? isDown : _down,
            HotkeyChoice.RightAlt => vk == VK_RMENU ? isDown : _down,
            HotkeyChoice.F13 => vk == VK_F13 ? isDown : _down,
            _ => false,
        };
        if (active && !_down)
        {
            _down = true;
            var mode = IsPressed(VK_SHIFT) ? DictationMode.Command : DictationMode.Dictation;
            System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => Pressed?.Invoke(mode));
        }
        else if (!active && _down)
        {
            _down = false;
            System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => Released?.Invoke());
        }
    }

    private static bool IsPressed(int vk) => (GetAsyncKeyState(vk) & 0x8000) != 0;

    public void Dispose()
    {
        if (_hook != IntPtr.Zero) UnhookWindowsHookEx(_hook);
        _hook = IntPtr.Zero;
    }
}
