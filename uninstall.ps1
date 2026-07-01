<#
.SYNOPSIS
  Uninstall claude-code-winkit modules.
.EXAMPLE
  .\uninstall.ps1                       # uninstall every module
.EXAMPLE
  .\uninstall.ps1 -Modules notifications
#>
param([string[]] $Modules)

$ErrorActionPreference = 'Stop'
$repoRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesDir = Join-Path $repoRoot 'modules'

$available = Get-ChildItem $modulesDir -Directory | Select-Object -ExpandProperty Name
if (-not $Modules -or $Modules.Count -eq 0) { $Modules = $available }

foreach ($m in $Modules) {
    $uninstaller = Join-Path $modulesDir "$m\uninstall.ps1"
    if (Test-Path $uninstaller) {
        Write-Host "== uninstalling module: $m ==" -ForegroundColor Cyan
        & $uninstaller
    } else {
        Write-Warning "unknown module '$m' (available: $($available -join ', '))"
    }
}

Write-Host ""
Write-Host "Done." -ForegroundColor Green
