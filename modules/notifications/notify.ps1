# Claude Code "needs your input" notifier.
# - Plays a sound
# - Shows a clickable WinRT toast; clicking it focuses the terminal WINDOW *and* the exact TAB
#   running this session (via the tab title captured below).
# Invoked by the Notification (and optionally Stop) hook. Reads the hook JSON from stdin.
$ErrorActionPreference = 'SilentlyContinue'

# --- message text from the hook payload on stdin ---
$raw = [Console]::In.ReadToEnd()
$msg = 'Waiting for your input'
if ($raw) {
    try { $d = $raw | ConvertFrom-Json; if ($d.message) { $msg = [string]$d.message } } catch { }
}

# --- this session's tab title (inherited console title = the Windows Terminal tab title) ---
$tabTitle = ''
try { $tabTitle = [Console]::Title } catch { }

# --- find the terminal window by walking up the process ancestry ---
function Get-TerminalHwnd {
    $parentOf = @{}
    Get-CimInstance Win32_Process | ForEach-Object { $parentOf[[int]$_.ProcessId] = [int]$_.ParentProcessId }
    $cur = $PID; $depth = 0
    while ($cur -and $depth -lt 20) {
        try {
            $p = Get-Process -Id $cur -ErrorAction Stop
            if ($p.MainWindowHandle -ne 0) { return [int64]$p.MainWindowHandle }
        } catch { }
        if (-not $parentOf.ContainsKey($cur)) { break }
        $cur = $parentOf[$cur]; $depth++
    }
    return 0
}
$hwnd = Get-TerminalHwnd

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
