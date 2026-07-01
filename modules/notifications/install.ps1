<#
  Installs the "notifications" module:
   - copies notify.ps1 / focus.ps1 into ~/.claude/hooks
   - registers the claudefocus: URL protocol (HKCU) -> focus.ps1
   - adds a Notification hook to ~/.claude/settings.json -> notify.ps1
#>
$ErrorActionPreference = 'Stop'
$moduleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $moduleDir '..\..')
. (Join-Path $repoRoot 'lib\settings.ps1')

# 1) Deploy the scripts into ~/.claude/hooks
$hooksDir = Join-Path $env:USERPROFILE '.claude\hooks'
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null
Copy-Item (Join-Path $moduleDir 'notify.ps1') $hooksDir -Force
Copy-Item (Join-Path $moduleDir 'focus.ps1')  $hooksDir -Force
Write-Host "  copied notify.ps1 / focus.ps1 to $hooksDir"

# 2) Register the claudefocus: protocol so the toast is clickable
$focusPath = Join-Path $hooksDir 'focus.ps1'
$base = 'HKCU:\Software\Classes\claudefocus'
New-Item -Path $base -Force | Out-Null
New-ItemProperty -Path $base -Name '(Default)'    -Value 'URL:Claude Code Focus' -PropertyType String -Force | Out-Null
New-ItemProperty -Path $base -Name 'URL Protocol' -Value ''                      -PropertyType String -Force | Out-Null
$cmdKey = "$base\shell\open\command"
New-Item -Path $cmdKey -Force | Out-Null
$protoCmd = 'powershell.exe -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" "%1"' -f $focusPath
New-ItemProperty -Path $cmdKey -Name '(Default)' -Value $protoCmd -PropertyType String -Force | Out-Null
Write-Host "  registered claudefocus: protocol"

# 3) Add the Notification hook (forward slashes => works under both bash and PowerShell hook shells)
$notifyPath = (Join-Path $hooksDir 'notify.ps1') -replace '\\', '/'
$hookCmd = 'powershell.exe -NoProfile -ExecutionPolicy Bypass -File "{0}"' -f $notifyPath
Add-ClaudeHook -Event 'Notification' -Command $hookCmd

Write-Host "  notifications module installed."
