# Shared helpers for safely merging hooks into ~/.claude/settings.json.
# Dot-source this file:  . "$repoRoot\lib\settings.ps1"

function Get-ClaudeSettingsPath {
    Join-Path $env:USERPROFILE '.claude\settings.json'
}

function Save-ClaudeSettings {
    param([Parameter(Mandatory)] $Object, [Parameter(Mandatory)][string] $Path)
    $json = $Object | ConvertTo-Json -Depth 64
    # Write UTF-8 without BOM (some JSON readers dislike a BOM).
    [System.IO.File]::WriteAllText($Path, $json, (New-Object System.Text.UTF8Encoding($false)))
}

# Add a command hook to a given event if an identical command isn't already present.
function Add-ClaudeHook {
    param(
        [Parameter(Mandatory)][string] $Event,
        [Parameter(Mandatory)][string] $Command,
        [int] $Timeout = 15,
        [switch] $Sync            # default is async (non-blocking)
    )
    $path = Get-ClaudeSettingsPath
    if (-not (Test-Path $path)) {
        throw "Claude settings not found at $path. Is Claude Code installed and run at least once?"
    }
    $obj = (Get-Content $path -Raw) | ConvertFrom-Json

    if (-not $obj.PSObject.Properties['hooks']) {
        $obj | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([pscustomobject]@{})
    }
    $hooks = $obj.hooks
    if (-not $hooks.PSObject.Properties[$Event]) {
        $hooks | Add-Member -NotePropertyName $Event -NotePropertyValue @()
    }

    $existing = @($hooks.$Event)
    foreach ($grp in $existing) {
        foreach ($h in @($grp.hooks)) {
            if ($h.command -eq $Command) {
                Write-Host "  hook already present on '$Event' - skipping."
                return
            }
        }
    }

    $entry = [ordered]@{ type = 'command'; command = $Command; timeout = $Timeout }
    if (-not $Sync) { $entry['async'] = $true }
    $newGroup = [pscustomobject]@{ hooks = @([pscustomobject]$entry) }
    $hooks.$Event = @($existing + $newGroup)

    Save-ClaudeSettings -Object $obj -Path $path
    Write-Host "  added '$Event' hook."
}

# Remove any command hook on a given event whose command contains $CommandMatch.
function Remove-ClaudeHook {
    param(
        [Parameter(Mandatory)][string] $Event,
        [Parameter(Mandatory)][string] $CommandMatch
    )
    $path = Get-ClaudeSettingsPath
    if (-not (Test-Path $path)) { return }
    $obj = (Get-Content $path -Raw) | ConvertFrom-Json
    if (-not $obj.PSObject.Properties['hooks']) { return }
    $hooks = $obj.hooks
    if (-not $hooks.PSObject.Properties[$Event]) { return }

    $kept = @()
    foreach ($grp in @($hooks.$Event)) {
        $subKept = @($grp.hooks | Where-Object { $_.command -notlike "*$CommandMatch*" })
        if ($subKept.Count -gt 0) {
            $grp.hooks = $subKept
            $kept += $grp
        }
    }
    $hooks.$Event = $kept
    Save-ClaudeSettings -Object $obj -Path $path
    Write-Host "  removed '$Event' hooks matching '$CommandMatch'."
}
