<#
.SYNOPSIS
  Install claude-code-winkit modules.
.EXAMPLE
  .\install.ps1                       # install every module
.EXAMPLE
  .\install.ps1 -Modules notifications
#>
param([string[]] $Modules)

$ErrorActionPreference = 'Stop'
$repoRoot   = Split-Path -Parent $MyInvocation.MyCommand.Path
$modulesDir = Join-Path $repoRoot 'modules'

$available = Get-ChildItem $modulesDir -Directory | Select-Object -ExpandProperty Name
if (-not $Modules -or $Modules.Count -eq 0) { $Modules = $available }

foreach ($m in $Modules) {
    $installer = Join-Path $modulesDir "$m\install.ps1"
    if (Test-Path $installer) {
        Write-Host "== installing module: $m ==" -ForegroundColor Cyan
        & $installer
    } else {
        Write-Warning "unknown module '$m' (available: $($available -join ', '))"
    }
}

Write-Host ""
Write-Host "Done. If a module added a hook, open Claude Code's /hooks once (or restart) to load it." -ForegroundColor Green
