<#
  Uninstalls the "notifications" module:
   - removes the Notification hook from ~/.claude/settings.json
   - unregisters the claudefocus: protocol
   - deletes the deployed scripts
#>
$ErrorActionPreference = 'Stop'
$moduleDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot  = Resolve-Path (Join-Path $moduleDir '..\..')
. (Join-Path $repoRoot 'lib\settings.ps1')

# 1) Remove the hook (matches any Notification hook that runs notify.ps1)
Remove-ClaudeHook -Event 'Notification' -CommandMatch 'notify.ps1'

# 2) Unregister the protocol
$base = 'HKCU:\Software\Classes\claudefocus'
if (Test-Path $base) { Remove-Item -Path $base -Recurse -Force; Write-Host "  removed claudefocus: protocol" }

# 3) Delete deployed scripts
$hooksDir = Join-Path $env:USERPROFILE '.claude\hooks'
foreach ($f in 'notify.ps1', 'focus.ps1') {
    $p = Join-Path $hooksDir $f
    if (Test-Path $p) { Remove-Item $p -Force; Write-Host "  removed $p" }
}

Write-Host "  notifications module uninstalled."
