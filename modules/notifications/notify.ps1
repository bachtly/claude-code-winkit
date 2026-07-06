# Claude Code "needs your input" notifier.
# - Plays a sound
# - Shows a clickable WinRT toast; clicking it focuses the terminal WINDOW *and* the exact TAB
#   running this session (via the tab title captured below).
# Invoked by the Notification (and optionally Stop) hook. Reads the hook JSON from stdin.
$ErrorActionPreference = 'SilentlyContinue'

# --- message text from the hook payload on stdin (read before any console juggling) ---
$raw = [Console]::In.ReadToEnd()
$msg = 'Waiting for your input'
if ($raw) {
    try { $d = $raw | ConvertFrom-Json; if ($d.message) { $msg = [string]$d.message } } catch { }
}

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class Native {
  [DllImport("kernel32.dll")] public static extern bool FreeConsole();
  [DllImport("kernel32.dll")] public static extern bool AttachConsole(uint pid);
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] public static extern uint GetConsoleTitle(StringBuilder s, uint n);
}
"@

# --- find this session's terminal window AND its tab title ---
# The tab title is the title Claude set on the console of the shell hosting this tab. We CANNOT
# read it from [Console]::Title here: the Notification hook runs async in its own (bash) console,
# whose title is just the bash exe path. So we walk up the process tree to the shell Windows
# Terminal launched for this tab and read *its* console title via AttachConsole.
function Get-SessionTarget {
    $consoleTitle = ''
    try { $consoleTitle = [Console]::Title } catch { }   # fallback for non-WT terminals

    $parentOf = @{}
    Get-CimInstance Win32_Process | ForEach-Object { $parentOf[[int]$_.ProcessId] = [int]$_.ParentProcessId }
    $chain = New-Object System.Collections.Generic.List[int]
    $cur = $PID
    while ($cur -and $chain.Count -lt 25) { $chain.Add($cur); if (-not $parentOf.ContainsKey($cur)) { break }; $cur = $parentOf[$cur] }

    # first ancestor with a window = the Windows Terminal window; the ancestor just below it is
    # the tab's root shell (whose console carries the Claude-set tab title).
    $hwnd = 0; $wtIdx = -1
    for ($i = 0; $i -lt $chain.Count; $i++) {
        $p = Get-Process -Id $chain[$i] -ErrorAction SilentlyContinue
        if ($p -and $p.MainWindowHandle -ne 0) { $hwnd = [int64]$p.MainWindowHandle; $wtIdx = $i; break }
    }

    $title = ''
    if ($wtIdx -gt 0) {
        $sb = New-Object System.Text.StringBuilder 1024
        for ($j = $wtIdx - 1; $j -ge 0; $j--) {
            [Native]::FreeConsole() | Out-Null
            if ([Native]::AttachConsole([uint32]$chain[$j])) {
                $sb.Length = 0
                [Native]::GetConsoleTitle($sb, 1024) | Out-Null
                [Native]::FreeConsole() | Out-Null
                $t = $sb.ToString()
                if ($t -and $t -notlike '*.exe') { $title = $t; break }   # skip bash.exe / powershell.exe consoles
            }
        }
    }
    if (-not $title) { $title = $consoleTitle }
    return [pscustomobject]@{ Hwnd = $hwnd; Title = $title }
}

$sess     = Get-SessionTarget
$hwnd     = $sess.Hwnd
$tabTitle = $sess.Title

# --- sound (guaranteed, independent of the toast) ---
try { (New-Object System.Media.SoundPlayer 'C:\Windows\Media\Windows Notify System Generic.wav').PlaySync() }
catch { [System.Media.SystemSounds]::Asterisk.Play() }

# --- build the click target: focus window + tab ---
$launch = "claudefocus:hwnd=$hwnd"
if ($tabTitle) { $launch += "&tab=" + [uri]::EscapeDataString($tabTitle) }

# --- clickable WinRT toast (persists in Action Center; survives process exit) ---
[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.UI.Notifications.ToastNotification, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null

$AppId   = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
$msgX    = [System.Security.SecurityElement]::Escape($msg)
$launchX = [System.Security.SecurityElement]::Escape($launch)

$xml = @"
<toast activationType="protocol" launch="$launchX">
  <visual>
    <binding template="ToastGeneric">
      <text>Claude Code</text>
      <text>$msgX</text>
      <text placement="attribution">Click to jump to this tab</text>
    </binding>
  </visual>
  <audio silent="true"/>
</toast>
"@

$doc = New-Object Windows.Data.Xml.Dom.XmlDocument
$doc.LoadXml($xml)
$toast = New-Object Windows.UI.Notifications.ToastNotification $doc
[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($AppId).Show($toast)
