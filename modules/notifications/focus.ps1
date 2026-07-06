# Invoked by the claudefocus: URL protocol when the toast is clicked.
# Receives "claudefocus:hwnd=<h>&tab=<url-encoded tab title>".
# Selects the matching Windows Terminal tab and brings its window to the foreground.
#
# Why we don't just trust <hwnd>: all Windows Terminal windows are served by ONE
# WindowsTerminal.exe process, so the hwnd notify.ps1 derived from process
# ancestry is that process's MainWindowHandle -- a single fixed window, not
# necessarily the window that hosts this session's tab. With >1 WT window open
# that hwnd points at the wrong window (focuses a terminal, wrong tab). So we
# search EVERY WT window for the tab whose title matches, and raise that one.
# <hwnd> is kept only as a fallback (single-tab / non-WT terminals).
param([string]$Uri)
$ErrorActionPreference = 'SilentlyContinue'

$hwnd = 0; $tab = ''
if ($Uri -match 'hwnd=(\d+)')   { $hwnd = [int64]$Matches[1] }
if ($Uri -match 'tab=([^&]*)')  { $tab  = [uri]::UnescapeDataString($Matches[1]) }

# Strip a leading glyph/spinner char (the status star or braille spinner + space) so
# matching is stable while that glyph animates.
function Normalize([string]$s) { if ($s) { ($s -replace '^[^\p{L}\p{N}]+', '').Trim() } else { '' } }
$tabCore = Normalize $tab

Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
public class WinFocus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
  // Visible, unowned top-level windows belonging to the given process id.
  public static List<IntPtr> WindowsForPid(uint targetPid) {
    var res = new List<IntPtr>();
    EnumWindows((h, l) => {
      uint pid; GetWindowThreadProcessId(h, out pid);
      if (pid == targetPid && IsWindowVisible(h) && GetWindow(h, 4 /*GW_OWNER*/) == IntPtr.Zero) res.Add(h);
      return true;
    }, IntPtr.Zero);
    return res;
  }
}
"@

$SW_RESTORE = 9

# Raise a window to the foreground (AttachThreadInput works around the foreground lock).
function Raise([IntPtr]$h) {
    $fg        = [WinFocus]::GetForegroundWindow()
    $fgThread  = [WinFocus]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
    $curThread = [WinFocus]::GetCurrentThreadId()
    [WinFocus]::AttachThreadInput($fgThread, $curThread, $true) | Out-Null
    if ([WinFocus]::IsIconic($h)) { [WinFocus]::ShowWindow($h, $SW_RESTORE) | Out-Null }
    [WinFocus]::BringWindowToTop($h) | Out-Null
    [WinFocus]::SetForegroundWindow($h) | Out-Null
    [WinFocus]::AttachThreadInput($fgThread, $curThread, $false) | Out-Null
}

# --- collect every Windows Terminal window (all WT windows share one process) ---
$wtWindows = New-Object System.Collections.Generic.List[IntPtr]
Get-Process WindowsTerminal -ErrorAction SilentlyContinue | ForEach-Object {
    foreach ($w in [WinFocus]::WindowsForPid([uint32]$_.Id)) { $wtWindows.Add($w) }
}

# --- find the WT window+tab whose title matches, via UI Automation ---
# Two passes so an exact title always beats a loose substring match in another window.
function Find-Tab([bool]$exact) {
    foreach ($wh in $wtWindows) {
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($wh)
        if (-not $root) { continue }
        $cond = New-Object System.Windows.Automation.PropertyCondition(
            [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
            [System.Windows.Automation.ControlType]::TabItem)
        foreach ($t in $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)) {
            $nameCore = Normalize $t.Current.Name
            if (-not $nameCore) { continue }
            $hit = if ($exact) { $nameCore -eq $tabCore }
                   else { $nameCore.Contains($tabCore) -or $tabCore.Contains($nameCore) }
            if ($hit) { return [pscustomobject]@{ Win = $wh; Tab = $t } }
        }
    }
    return $null
}

$found = $null
if ($tabCore -and $wtWindows.Count -gt 0) {
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $found = Find-Tab $true
        if (-not $found) { $found = Find-Tab $false }
    } catch { }
}

if ($found) {
    # Select the tab first (works even while its window is in the background), then raise the window.
    try {
        $p = $found.Tab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $p.Select()
    } catch { }
    Raise $found.Win
}
elseif ($hwnd) {
    # No tab matched (single-tab window, non-WT terminal, or the title drifted) -> best-effort window focus.
    Raise ([IntPtr]$hwnd)
}
