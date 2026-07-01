# Invoked by the claudefocus: URL protocol when the toast is clicked.
# Receives "claudefocus:hwnd=<h>&tab=<url-encoded tab title>".
# Brings that window to the foreground, then selects the matching Windows Terminal tab.
param([string]$Uri)
$ErrorActionPreference = 'SilentlyContinue'

$hwnd = 0; $tab = ''
if ($Uri -match 'hwnd=(\d+)')   { $hwnd = [int64]$Matches[1] }
if ($Uri -match 'tab=([^&]*)')  { $tab  = [uri]::UnescapeDataString($Matches[1]) }
if (-not $hwnd) { exit }

# Strip a leading glyph/spinner char (e.g. the status star or braille spinner + space) so
# matching is stable while that glyph animates.
function Normalize([string]$s) { if ($s) { ($s -replace '^[^\p{L}\p{N}]+', '').Trim() } else { '' } }
$tabCore = Normalize $tab

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class WinFocus {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
}
"@

$h = [IntPtr]$hwnd
$SW_RESTORE = 9

# --- raise the window (AttachThreadInput works around the foreground lock) ---
$fg        = [WinFocus]::GetForegroundWindow()
$fgThread  = [WinFocus]::GetWindowThreadProcessId($fg, [IntPtr]::Zero)
$curThread = [WinFocus]::GetCurrentThreadId()
[WinFocus]::AttachThreadInput($fgThread, $curThread, $true) | Out-Null
if ([WinFocus]::IsIconic($h)) { [WinFocus]::ShowWindow($h, $SW_RESTORE) | Out-Null }
[WinFocus]::BringWindowToTop($h) | Out-Null
[WinFocus]::SetForegroundWindow($h) | Out-Null
[WinFocus]::AttachThreadInput($fgThread, $curThread, $false) | Out-Null

# --- select the matching tab via UI Automation ---
if ($tabCore) {
    try {
        Add-Type -AssemblyName UIAutomationClient
        Add-Type -AssemblyName UIAutomationTypes
        $root = [System.Windows.Automation.AutomationElement]::FromHandle($h)
        if ($root) {
            $cond = New-Object System.Windows.Automation.PropertyCondition(
                [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
                [System.Windows.Automation.ControlType]::TabItem)
            $tabs = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $cond)
            foreach ($t in $tabs) {
                $nameCore = Normalize $t.Current.Name
                if ($nameCore -and ($nameCore -eq $tabCore -or $nameCore.Contains($tabCore) -or $tabCore.Contains($nameCore))) {
                    $p = $t.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
                    $p.Select()
                    break
                }
            }
        }
    } catch { }
}
