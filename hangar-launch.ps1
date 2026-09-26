<#
.SYNOPSIS
    Target script of a new tab: strips inherited CLAUDE_CODE_* variables and starts claude.

.DESCRIPTION
    Exists because the command handed to wt must NOT contain semicolons or pipes —
    wt treats `;` as its own command separator and splits a one-line
    "cleanup; claude" in two (learned 2026-08-23: the CLAUDE_CODE_CHILD_SESSION
    marker survived and switched transcript saving off). So the logic lives in a
    .ps1 file, not on the command line.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    # Resume the most recent conversation (claude --continue).
    [switch]$Continue,
    # Skip the Remote Control registration (e.g. a second instance of the same
    # project, which would otherwise claim the same address).
    [switch]$NoRemoteControl
)

# Variables Claude Code sets for ITS CHILD PROCESSES. Inherited, they would hurt a
# fresh session in two ways:
#   CLAUDE_CODE_CHILD_SESSION -> child mode, transcript saving (/resume) switched OFF
#   NO_COLOR                  -> claude does not draw its orange and falls back to the
#                                ANSI palette (verified 2026-08-23 with a window capture)
# The picker already passes `wt --reloadEnvironment`, so the tab gets a clean
# environment block and none of this arrives here. This is the second safety net for
# when the launcher is run directly (outside the picker), where nothing handles it.
Get-Item Env:CLAUDE_CODE_* -ErrorAction SilentlyContinue | Remove-Item -ErrorAction SilentlyContinue
foreach ($var in 'NO_COLOR','CLAUDECODE','CLAUDE_PID','AI_AGENT',
                 'GIT_EDITOR','GIT_ASKPASS','GIT_TERMINAL_PROMPT') {
    if (Test-Path "Env:$var") { Remove-Item "Env:$var" -ErrorAction SilentlyContinue }
}

# --name and --remote-control are two different switches that both take a name:
#   --name           = display name (tab title, /resume picker) -> the bare project name
#   --remote-control = the session ADDRESS for other machines -> must be unique across
#                      machines, otherwise two Hangars on the same project collide
# The machine prefix comes from HANGAR_MACHINE_PREFIX (set it per machine to a short
# label such as `LAPTOP` or `DESKTOP`) and falls back to COMPUTERNAME.
$machine = if ($env:HANGAR_MACHINE_PREFIX) { $env:HANGAR_MACHINE_PREFIX } else { $env:COMPUTERNAME }
# No spaces in the address (`my project`) — a dash reads better.
$address = "$machine-$($Name -replace '\s+', '-')"

$claudeArgs = @('--name', $Name)
if (-not $NoRemoteControl) { $claudeArgs += @('--remote-control', $address) }
if ($Continue)             { $claudeArgs += '--continue' }

& claude @claudeArgs
