<#
.SYNOPSIS
    Creates (or removes) the Hangar desktop shortcuts.

.DESCRIPTION
    Two shortcuts, because Hangar has two front ends:

      Hangar              -> the WPF window, launched through hangar-gui.vbs so no
                             console flashes up first
      Hangar (terminal)   -> the terminal picker in a fresh Windows Terminal window

    Idempotent: running it again just overwrites the shortcuts, so it is the way to
    repair them after moving the workspace. Nothing is written outside the Desktop.

    Paths are resolved at run time from $PSScriptRoot and $env:USERPROFILE — never
    hard-coded, so the same checkout works on machines with different user names.

.EXAMPLE
    ./install-shortcuts.ps1
    ./install-shortcuts.ps1 -Remove
    ./install-shortcuts.ps1 -Destination "$env:USERPROFILE\Desktop\tools"
#>
[CmdletBinding()]
param(
    # Where to put the shortcuts. Defaults to the Desktop.
    [string]$Destination,
    # Delete the shortcuts instead of creating them.
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

if (-not $Destination) {
    # [Environment]::GetFolderPath, not "$env:USERPROFILE\Desktop" — the Desktop is
    # often redirected to OneDrive and the literal path would miss it.
    $Destination = [Environment]::GetFolderPath('Desktop')
}
if (-not (Test-Path -LiteralPath $Destination)) {
    throw "Destination folder does not exist: $Destination"
}

$iconPath = Join-Path $PSScriptRoot 'img\hangar.ico'
if (-not (Test-Path -LiteralPath $iconPath)) {
    Write-Host 'Icon missing, generating it...'
    & (Join-Path $PSScriptRoot 'make-icon.ps1') | Out-Null
}

$gui = Join-Path $Destination 'Hangar.lnk'
$tui = Join-Path $Destination 'Hangar (terminal).lnk'

if ($Remove) {
    foreach ($lnk in $gui, $tui) {
        if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force; Write-Host "removed: $lnk" }
    }
    return
}

$shell = New-Object -ComObject WScript.Shell

# --- 1. GUI window -----------------------------------------------------------------
$s = $shell.CreateShortcut($gui)
# wscript.exe (not pwsh) so the VBS shim runs windowless — see hangar-gui.vbs.
$s.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
$s.Arguments        = '"' + (Join-Path $PSScriptRoot 'hangar-gui.vbs') + '"'
$s.WorkingDirectory = $PSScriptRoot
$s.IconLocation     = "$iconPath,0"
$s.Description      = 'Hangar — project launcher for Claude Code'
$s.Save()
Write-Host "created: $gui"

# --- 2. terminal picker --------------------------------------------------------------
# wt.exe is a Store app execution alias; a shortcut to it works, but the path has to be
# resolved because it lives under WindowsApps, not in System32.
$wt = (Get-Command wt.exe -ErrorAction SilentlyContinue).Source
if ($wt) {
    $s = $shell.CreateShortcut($tui)
    $s.TargetPath = $wt
    # -w -1 = always a new window: the picker is a full-screen TUI and would otherwise
    # take over a tab in whatever window was last used.
    $s.Arguments  = '-w -1 nt --title "Hangar" pwsh -NoLogo -NoProfile -File "' +
                    (Join-Path $PSScriptRoot 'hangar.ps1') + '"'
    $s.WorkingDirectory = $PSScriptRoot
    $s.IconLocation     = "$iconPath,0"
    $s.Description      = 'Hangar — terminal project picker'
    $s.Save()
    Write-Host "created: $tui"
} else {
    Write-Warning 'wt.exe not found — the terminal picker shortcut was not created.'
}

Write-Host ''
Write-Host 'Done. Right-click a shortcut -> Pin to taskbar to keep it on the taskbar.'
