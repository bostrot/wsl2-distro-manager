# _common.ps1 -- shared plumbing for the Maestro UI-automation helpers.
#
# Dot-source this from any helper:  . "$PSScriptRoot\_common.ps1"
#
# Everything the other scripts need lives here: the P/Invoke surface, window
# resolution, DWM-accurate bounds and window-relative -> screen coordinate
# conversion. Do not duplicate any of it in the individual helpers.

$ErrorActionPreference = 'Stop'

# Default identity of the app under automation. windows/runner/main.cpp creates
# the window with the title "WSL Manager"; windows/CMakeLists.txt names the
# binary wsl2distromanager.exe, so the process is "wsl2distromanager" for both
# `flutter run -d windows` and the packaged Release build.
$MaestroAppProcessNames = @('wsl2distromanager')
$MaestroAppTitle        = 'WSL Manager'

# Repo root: this file lives at <repo>/.maestro/tools/_common.ps1
$MaestroRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path

if (-not ('Maestro.Native' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;

namespace Maestro {

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }

    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X; public int Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT {
        public int dx; public int dy; public uint mouseData;
        public uint dwFlags; public uint time; public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct KEYBDINPUT {
        public ushort wVk; public ushort wScan; public uint dwFlags;
        public uint time; public IntPtr dwExtraInfo;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct HARDWAREINPUT { public uint uMsg; public ushort wParamL; public ushort wParamH; }

    [StructLayout(LayoutKind.Explicit)]
    public struct INPUTUNION {
        [FieldOffset(0)] public MOUSEINPUT mi;
        [FieldOffset(0)] public KEYBDINPUT ki;
        [FieldOffset(0)] public HARDWAREINPUT hi;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public INPUTUNION u; }

    public static class Native {

        // ---- window ---------------------------------------------------------
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool   SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool   BringWindowToTop(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool   ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern bool   ShowWindowAsync(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")] public static extern bool   IsIconic(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool   IsWindow(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool   IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll")] public static extern bool   MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);
        [DllImport("user32.dll")] public static extern bool   GetWindowRect(IntPtr hWnd, out RECT lpRect);
        [DllImport("user32.dll")] public static extern bool   SetWindowPos(IntPtr hWnd, IntPtr hWndInsertAfter, int X, int Y, int cx, int cy, uint uFlags);
        [DllImport("user32.dll")] public static extern IntPtr GetShellWindow();
        [DllImport("user32.dll")] public static extern IntPtr GetDesktopWindow();
        [DllImport("user32.dll")] public static extern uint   GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
        [DllImport("user32.dll")] public static extern bool   AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
        [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();

        [DllImport("user32.dll")]
        private static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, IntPtr wParam,
            IntPtr lParam, uint fuFlags, uint uTimeout, out IntPtr lpdwResult);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowTextLength(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        private delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);

        // ---- dwm ------------------------------------------------------------
        // DWMWA_EXTENDED_FRAME_BOUNDS = 9. Unlike GetWindowRect it excludes the
        // invisible resize border Windows 10/11 pads every window with, which is
        // the ~8px-per-side over-capture the old screenshot helper suffered from.
        [DllImport("dwmapi.dll")]
        public static extern int DwmGetWindowAttribute(IntPtr hwnd, int dwAttribute, out RECT pvAttribute, int cbAttribute);

        // ---- dpi ------------------------------------------------------------
        [DllImport("user32.dll")] private static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("user32.dll")] private static extern bool SetProcessDPIAware();

        // ---- input ----------------------------------------------------------
        [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
        [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT lpPoint);
        [DllImport("user32.dll")] private static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);
        [DllImport("user32.dll")] private static extern uint MapVirtualKey(uint uCode, uint uMapType);

        public const int SW_HIDE = 0, SW_SHOWNORMAL = 1, SW_SHOWMINIMIZED = 2,
                         SW_MAXIMIZE = 3, SW_SHOW = 5, SW_MINIMIZE = 6, SW_RESTORE = 9;

        public const uint INPUT_MOUSE = 0, INPUT_KEYBOARD = 1;
        public const uint MOUSEEVENTF_LEFTDOWN = 0x0002, MOUSEEVENTF_LEFTUP = 0x0004,
                          MOUSEEVENTF_RIGHTDOWN = 0x0008, MOUSEEVENTF_RIGHTUP = 0x0010,
                          MOUSEEVENTF_MIDDLEDOWN = 0x0020, MOUSEEVENTF_MIDDLEUP = 0x0040,
                          MOUSEEVENTF_WHEEL = 0x0800, MOUSEEVENTF_HWHEEL = 0x1000;
        public const uint KEYEVENTF_EXTENDEDKEY = 0x0001, KEYEVENTF_KEYUP = 0x0002,
                          KEYEVENTF_UNICODE = 0x0004;

        // Marking the host PowerShell per-monitor DPI aware keeps every number in
        // this module in physical pixels. Without it GetWindowRect/DWM report
        // physical pixels while CopyFromScreen and SetCursorPos are silently
        // rescaled into the DPI-virtualised space, so screenshots and clicks
        // disagree by the display scale factor on any non-100% monitor.
        public static void EnsureDpiAware() {
            try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch { }
            try { SetProcessDPIAware(); } catch { }
        }

        public static string GetTitle(IntPtr hWnd) {
            int len = GetWindowTextLength(hWnd);
            if (len <= 0) return string.Empty;
            StringBuilder sb = new StringBuilder(len + 1);
            GetWindowText(hWnd, sb, sb.Capacity);
            return sb.ToString();
        }

        public static string GetClass(IntPtr hWnd) {
            StringBuilder sb = new StringBuilder(256);
            GetClassName(hWnd, sb, sb.Capacity);
            return sb.ToString();
        }

        public static uint GetPid(IntPtr hWnd) {
            uint pid; GetWindowThreadProcessId(hWnd, out pid); return pid;
        }

        // Visible top-level windows whose title contains `needle` (ordinal,
        // case-insensitive). Empty needle returns every titled visible window.
        public static IntPtr[] FindWindows(string needle) {
            List<IntPtr> hits = new List<IntPtr>();
            EnumWindows(delegate(IntPtr h, IntPtr l) {
                if (!IsWindowVisible(h)) return true;
                string t = GetTitle(h);
                if (t.Length == 0) return true;
                if (needle == null || needle.Length == 0 ||
                    t.IndexOf(needle, StringComparison.OrdinalIgnoreCase) >= 0) hits.Add(h);
                return true;
            }, IntPtr.Zero);
            return hits.ToArray();
        }

        // True bounds of the visible frame. Falls back to GetWindowRect if DWM
        // composition is unavailable (S_OK == 0).
        public static bool TryGetFrameBounds(IntPtr hWnd, out RECT r) {
            r = new RECT();
            if (DwmGetWindowAttribute(hWnd, 9, out r, Marshal.SizeOf(typeof(RECT))) == 0
                && r.Right > r.Left && r.Bottom > r.Top) return true;
            return GetWindowRect(hWnd, out r);
        }

        // A window whose thread does not answer a WM_NULL within `ms` is either
        // hung or sitting in a modal loop. Attaching to such a thread is a trap:
        // SetForegroundWindow then blocks on a synchronous send that never
        // returns. Probing first is what keeps focus.ps1 from wedging when a
        // system dialog (an "Open with" prompt, a UAC consent, an installer)
        // owns the foreground.
        public static bool IsResponsive(IntPtr hWnd, uint ms) {
            IntPtr result;
            // SMTO_ABORTIFHUNG (0x0002) | SMTO_BLOCK (0x0001)
            return SendMessageTimeout(hWnd, 0x0000, IntPtr.Zero, IntPtr.Zero, 0x0003, ms, out result) != IntPtr.Zero;
        }

        // SetForegroundWindow is refused unless the caller owns the foreground.
        // Borrowing the foreground thread's input queue lifts that restriction.
        public static bool ForceForeground(IntPtr hWnd) {
            if (IsIconic(hWnd)) ShowWindow(hWnd, SW_RESTORE);
            IntPtr fg = GetForegroundWindow();
            uint self = GetCurrentThreadId();
            uint other = (fg == IntPtr.Zero) ? self : GetWindowThreadProcessId(fg, out _dummy);
            bool attached = (other != self) && IsResponsive(fg, 250) && AttachThreadInput(self, other, true);
            try {
                BringWindowToTop(hWnd);
                SetForegroundWindow(hWnd);
                SetActiveWindow(hWnd);
                SetFocus(hWnd);
            } finally {
                if (attached) AttachThreadInput(self, other, false);
            }
            return GetForegroundWindow() == hWnd;
        }
        private static uint _dummy;

        // ---- input helpers --------------------------------------------------
        private static void Send(INPUT[] inputs) {
            uint sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT)));
            if (sent != (uint)inputs.Length)
                throw new InvalidOperationException(
                    "SendInput delivered " + sent + " of " + inputs.Length +
                    " events (win32 error " + Marshal.GetLastWin32Error() + "). " +
                    "A more privileged window is probably blocking input (UIPI).");
        }

        private static INPUT Mouse(uint flags, uint data) {
            INPUT i = new INPUT();
            i.type = INPUT_MOUSE;
            i.u.mi.dwFlags = flags;
            i.u.mi.mouseData = data;
            return i;
        }

        private static INPUT Kb(ushort vk, ushort scan, uint flags) {
            INPUT i = new INPUT();
            i.type = INPUT_KEYBOARD;
            i.u.ki.wVk = vk;
            i.u.ki.wScan = scan;
            i.u.ki.dwFlags = flags;
            return i;
        }

        public static void MouseButton(uint flags) { Send(new INPUT[] { Mouse(flags, 0) }); }

        // One wheel notch is WHEEL_DELTA (120). Positive scrolls up / right.
        public static void Wheel(int notches, bool horizontal) {
            Send(new INPUT[] { Mouse(horizontal ? MOUSEEVENTF_HWHEEL : MOUSEEVENTF_WHEEL,
                                    unchecked((uint)(notches * 120))) });
        }

        // The scan code is not optional. Flutter's Windows embedder derives the
        // physical key from the scan code in lParam, not from the virtual key, so
        // a VK-only SendInput (wScan = 0) is silently dropped by the framework --
        // ctrl+a and delete simply do nothing in a Flutter text field. Real
        // keyboards always supply a scan code; MapVirtualKey reproduces it.
        public static void Key(ushort vk, bool up, bool extended) {
            ushort scan = (ushort)MapVirtualKey(vk, 0 /* MAPVK_VK_TO_VSC */);
            uint f = (up ? KEYEVENTF_KEYUP : 0) | (extended ? KEYEVENTF_EXTENDEDKEY : 0);
            Send(new INPUT[] { Kb(vk, scan, f) });
        }

        // Unicode scan codes bypass the active keyboard layout entirely, so text
        // types identically on the German layout this machine runs and on en-US.
        public static void TypeText(string text) {
            foreach (char c in text) {
                if (c == '\r') continue;
                if (c == '\n') { Key(0x0D, false, false); Key(0x0D, true, false); continue; }
                Send(new INPUT[] {
                    Kb(0, (ushort)c, KEYEVENTF_UNICODE),
                    Kb(0, (ushort)c, KEYEVENTF_UNICODE | KEYEVENTF_KEYUP)
                });
            }
        }
    }
}
'@
}

[Maestro.Native]::EnsureDpiAware() | Out-Null

# ---------------------------------------------------------------------------
# Window resolution
# ---------------------------------------------------------------------------

<#
.SYNOPSIS
Resolve the app's top-level window handle.

.DESCRIPTION
Tries, in order: an explicit -Handle, the MainWindowHandle of a process named in
-ProcessName, then a title search for -TitleMatch. Waits up to -TimeoutSeconds
for the window to appear (0 = do not wait). Throws if nothing is found.
#>
function Get-AppWindow {
    [CmdletBinding()]
    param(
        [long]$Handle = 0,
        [string[]]$ProcessName = $MaestroAppProcessNames,
        [string]$TitleMatch = $MaestroAppTitle,
        [int]$TimeoutSeconds = 0
    )

    if ($Handle -ne 0) {
        $h = [IntPtr]$Handle
        if (-not [Maestro.Native]::IsWindow($h)) { throw "Handle $Handle is not a live window." }
        return New-AppWindowInfo $h
    }

    $deadline = (Get-Date).AddSeconds([Math]::Max($TimeoutSeconds, 0))
    do {
        foreach ($name in $ProcessName) {
            $procs = @(Get-Process -Name $name -ErrorAction SilentlyContinue |
                       Where-Object { $_.MainWindowHandle -ne 0 })
            if ($procs.Count -gt 1) {
                Write-Warning "$($procs.Count) '$name' windows are open; using pid $($procs[0].Id). Pass -Handle to disambiguate."
            }
            if ($procs.Count -ge 1) { return New-AppWindowInfo ([IntPtr]$procs[0].MainWindowHandle) }
        }

        if ($TitleMatch) {
            $hits = @([Maestro.Native]::FindWindows($TitleMatch))
            if ($hits.Count -ge 1) { return New-AppWindowInfo $hits[0] }
        }

        if ((Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    } while ((Get-Date) -lt $deadline)

    throw ("No window found for process [{0}] or title '{1}'. Is the app running? Start it with launch.ps1." -f ($ProcessName -join ', '), $TitleMatch)
}

function New-AppWindowInfo {
    param([IntPtr]$Handle)
    $pid_ = [Maestro.Native]::GetPid($Handle)
    $name = try { (Get-Process -Id $pid_ -ErrorAction Stop).ProcessName } catch { '<unknown>' }
    [pscustomobject]@{
        Handle      = $Handle
        HandleValue = [int64]$Handle
        ProcessId   = [int]$pid_
        ProcessName = $name
        Title       = [Maestro.Native]::GetTitle($Handle)
    }
}

<#
.SYNOPSIS
Visible frame bounds of a window, in physical screen pixels.

.DESCRIPTION
Uses DWMWA_EXTENDED_FRAME_BOUNDS, so the rectangle matches exactly what the user
sees -- no invisible resize border. -Raw returns the GetWindowRect rectangle
instead, which is what MoveWindow consumes.
#>
function Get-AppBounds {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Window, [switch]$Raw)

    $h = if ($Window -is [IntPtr]) { $Window } else { $Window.Handle }
    $r = New-Object Maestro.RECT
    $ok = if ($Raw) { [Maestro.Native]::GetWindowRect($h, [ref]$r) }
          else      { [Maestro.Native]::TryGetFrameBounds($h, [ref]$r) }
    if (-not $ok) { throw "Could not read bounds for window $([int64]$h)." }

    [pscustomobject]@{
        X = $r.Left; Y = $r.Top; Right = $r.Right; Bottom = $r.Bottom
        Width = $r.Right - $r.Left; Height = $r.Bottom - $r.Top
    }
}

<#
.SYNOPSIS
Translate a window-relative point to absolute screen coordinates.

.DESCRIPTION
(0,0) is the top-left of the *visible* frame, so coordinates read straight off a
shot.ps1 PNG land where you expect. Negative values count back from the right or
bottom edge (-1 = last pixel). Values are clamped into the window.
#>
function ConvertTo-ScreenPoint {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Window, [Parameter(Mandatory)][int]$X, [Parameter(Mandatory)][int]$Y)

    $b = Get-AppBounds -Window $Window
    $rx = if ($X -lt 0) { $b.Width  + $X } else { $X }
    $ry = if ($Y -lt 0) { $b.Height + $Y } else { $Y }

    if ($rx -lt 0 -or $rx -ge $b.Width -or $ry -lt 0 -or $ry -ge $b.Height) {
        Write-Warning ("Point ({0},{1}) is outside the {2}x{3} window; clamping." -f $rx, $ry, $b.Width, $b.Height)
        $rx = [Math]::Min([Math]::Max($rx, 0), $b.Width  - 1)
        $ry = [Math]::Min([Math]::Max($ry, 0), $b.Height - 1)
    }

    [pscustomobject]@{ X = $b.X + $rx; Y = $b.Y + $ry; RelativeX = $rx; RelativeY = $ry; Bounds = $b }
}

<#
.SYNOPSIS
Focus the window unless -NoFocus was passed. Used by every input helper.
#>
function Confirm-AppFocus {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Window, [switch]$NoFocus, [int]$TimeoutSeconds = 10)

    if ($NoFocus) { return }
    if ([Maestro.Native]::GetForegroundWindow() -eq $Window.Handle) { return }
    & (Join-Path $PSScriptRoot 'focus.ps1') -Handle $Window.HandleValue -TimeoutSeconds $TimeoutSeconds -Quiet | Out-Null
}
