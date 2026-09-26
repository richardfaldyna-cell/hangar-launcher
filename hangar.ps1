<#
.SYNOPSIS
    Hangar — terminal project picker: pick a project and a terminal opens in the
    right folder with `claude` already running.

.DESCRIPTION
    Drawing and input handling. Everything else — index, search, frecency,
    launching — lives in hangar-core.ps1, shared with hangar-gui.ps1.

    Keys:
      typing            fuzzy filter (name and path)
      up/down arrows    selection
      Enter             claude in a NEW TAB of THIS window
      Shift+Enter       claude in a NEW WINDOW
      Ctrl+R            claude --continue (resume the last conversation)
      Ctrl+S            plain shell, no claude
      Ctrl+E            VS Code
      Ctrl+O            Explorer
      Esc               quit

.EXAMPLE
    hangar               # interactive picker
    hangar ng            # launch the best match for "ng" straight away
    hangar ng -DryRun    # only print what would be launched
    hangar -Gui          # open the window instead of the terminal list
#>
[CmdletBinding()]
param(
    # When given, the TUI is skipped and the best match is launched.
    [string]$Project,
    # Force a fresh index before starting.
    [switch]$Refresh,
    # Only print the command, launch nothing.
    [switch]$DryRun,
    # Open the graphical window (hangar-gui.ps1) instead of the terminal list.
    [switch]$Gui,
    # Maximum index age before it is refreshed in the background.
    [int]$MaxAgeMinutes = 60
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'hangar-core.ps1')

if ($Gui) {
    & (Join-Path $PSScriptRoot 'hangar-gui.ps1') -Project $Project -Refresh:$Refresh -DryRun:$DryRun
    return
}

Import-HangarIndex -Refresh:$Refresh -MaxAgeMinutes $MaxAgeMinutes
$projects = Get-HangarProjects

# --- non-interactive mode: hangar <project> -----------------------------------------
if ($Project) {
    $matched = @(Find-Project $Project)
    if (-not $matched) { Write-Error "No project matches '$Project'."; exit 1 }
    Start-Project -Project $matched[0] -DryRun:$DryRun
    return
}

# --- TUI ----------------------------------------------------------------------------
$query = ''
$selected = 0
$maxRows = 15

# Width of the path column. The median id is 25 characters and the 90th percentile
# 38, so 44 covers almost everything and only a few outliers get truncated to keep
# the columns on the right aligned. Without truncation one long project would throw
# the whole table off.
$idWidth = 44

# ANSI colours instead of -ForegroundColor. Write-Host always colours the WHOLE call,
# so a row with seven columns meant seven console writes and a full frame over a
# hundred — WT rendered them as they came and the frame assembled itself top to
# bottom in front of your eyes. ANSI sequences, on the other hand, can be joined into
# a single string and sent in one write (see Show-Frame).
$Colors = @{
    Cyan       = "`e[96m"
    White      = "`e[97m"
    Red        = "`e[91m"
    Gray       = "`e[37m"
    Yellow     = "`e[93m"
    Green      = "`e[92m"
    DarkYellow = "`e[33m"
    Magenta    = "`e[95m"
    DarkGray   = "`e[90m"
}
$Reset = "`e[0m"

# NO_COLOR (https://no-color.org): when set, the sequences become empty strings —
# the column layout does not depend on colours.
if ($env:NO_COLOR) {
    foreach ($key in @($Colors.Keys)) { $Colors[$key] = '' }
    $Reset = ''
}

# One coloured fixed-width column. Returns a STRING and writes nothing — the frame is
# assembled in memory and goes to the console only when complete.
function Format-Column([string]$Text, [int]$Width, [string]$Color) {
    $Colors[$Color] + ("{0,-$Width}" -f $Text)
}

# Redraw without Clear-Host. In PS7, Clear-Host first scrolls the buffer and only then
# clears (PowerShell#13972), so there is a visibly empty frame between clearing and
# printing — that was the flicker on every arrow key. Instead: cursor to 1,1 (ESC[H),
# write each row and clear only its remainder (ESC[K), and at the end clear the rest of
# the screen (ESC[J) in case the filter shortened the list. There is never an empty
# screen; every character is simply overwritten.
function Show-Frame($list) {
    $count = @($list).Count
    $rows = [System.Collections.Generic.List[string]]::new()
    $rows.Add($Colors.Cyan  + ("┌ Hangar ─ {0}/{1} projects" -f $count, $projects.Count) + $Reset)
    $rows.Add($Colors.White + ("│ > {0}_" -f $query) + $Reset)

    $from = [Math]::Max(0, $selected - $maxRows + 1)
    $visible = @($list) | Select-Object -Skip $from -First $maxRows
    $i = $from
    foreach ($p in $visible) {
        $cursor = if ($i -eq $selected) { '►' } else { ' ' }
        $color  = switch ($p.group) { 'business' { 'Red' } 'private' { 'Cyan' } default { 'Gray' } }
        $id = if ($p.id.Length -gt $idWidth) { $p.id.Substring(0, $idWidth - 1) + '…' } else { $p.id }

        # Changed files, ahead/behind, open tasks, worktrees, session age.
        # hangar-index.ps1 already collects all of it — the picker only draws it.
        $dirty = ''; $ahead = ''; $behind = ''
        if ($p.git) {
            if ($p.git.dirty  -gt 0) { $dirty  = "~$($p.git.dirty)" }
            if ($p.git.ahead  -gt 0) { $ahead  = "⇡$($p.git.ahead)" }
            if ($p.git.behind -gt 0) { $behind = "⇣$($p.git.behind)" }
        }
        $rows.Add(
            $Colors[$color] + ("│{0} " -f $cursor) +
            (Format-Column $id     $idWidth $color) +
            (Format-Column $dirty  5 'Yellow') +
            (Format-Column $ahead  5 'Green') +
            (Format-Column $behind 5 'Red') +
            (Format-Column $(if ($p.openTodos -gt 0)       { "☐$($p.openTodos)" }        else { '' }) 6 'DarkYellow') +
            (Format-Column $(if ($p.worktrees.Count -gt 0) { "wt:$($p.worktrees.Count)" } else { '' }) 6 'Magenta') +
            (Format-Column (Format-Age $p.claude.lastSessionAt) 5 'DarkGray') + $Reset)
        $i++
    }

    $rows.Add($Colors.DarkGray + '│ ~changes ⇡ahead ⇣behind ☐tasks wt:worktree · right: age of last session' + $Reset)
    $rows.Add($Colors.DarkGray + '└ ↑↓ · Enter tab · Shift+Enter window · ^R resume · ^S shell · ^E Code · ^O Explorer · Esc' + $Reset)

    [Console]::Out.Write("`e[H" + ($rows -join "`e[K`n") + "`e[K`e[J")
}

# Alternate screen buffer — the same mechanism vim and less use. Besides being meant
# for full-screen apps, it has a second benefit: after Esc the ORIGINAL terminal
# content comes back, history included, which Clear-Host used to wipe for good. The
# cursor is hidden with an ANSI sequence, not [Console]::CursorVisible — that one
# clashes with the alternate buffer in PS7 (PowerShell#21212).
function Enter-AltBuffer { [Console]::Out.Write("`e[?1049h`e[?25l") }
function Exit-AltBuffer  { [Console]::Out.Write("`e[?25h`e[?1049l") }

# The choice is only recorded and launched AFTER leaving the buffer — otherwise the
# -DryRun output would end up in a frame that is thrown away on return.
$action = $null
$list = @(Find-Project $query)

# Without UTF-8 output (legacy OEM code pages are the default on many Windows
# locales) ►, ⇡⇣ and ☐ render as '?' — the picker must not rely on the user's profile
# having switched the encoding (`pwsh -NoProfile` has none). The original encoding is
# restored in finally, so the console is left as it was after Esc.
$originalEncoding = [Console]::OutputEncoding
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

Enter-AltBuffer
try {
    Show-Frame $list
    :loop while ($true) {
        $k = [Console]::ReadKey($true)
        $ctrl = ($k.Modifiers -band 'Control') -ne 0
        switch ($k.Key) {
            'Escape'    { break loop }
            'UpArrow'   { if ($selected -gt 0) { $selected-- } }
            'DownArrow' { if ($selected -lt $list.Count - 1) { $selected++ } }
            'Backspace' { if ($query) { $query = $query.Substring(0, $query.Length - 1); $selected = 0 } }
            'Enter' {
                if ($list.Count -gt 0) {
                    $action = @{ Kind = 'launch'; Project = $list[$selected]
                                 NewWindow = (($k.Modifiers -band 'Shift') -ne 0) }
                    break loop
                }
            }
            'R' { if ($ctrl -and $list.Count -gt 0) {
                    $action = @{ Kind = 'launch'; Project = $list[$selected]; Continue = $true }; break loop }
                  elseif (-not $ctrl) { $query += $k.KeyChar; $selected = 0 } }
            'S' { if ($ctrl -and $list.Count -gt 0) {
                    $action = @{ Kind = 'launch'; Project = $list[$selected]; ShellOnly = $true }; break loop }
                  elseif (-not $ctrl) { $query += $k.KeyChar; $selected = 0 } }
            'E' { if ($ctrl -and $list.Count -gt 0) {
                    $action = @{ Kind = 'editor'; Project = $list[$selected] }; break loop }
                  elseif (-not $ctrl) { $query += $k.KeyChar; $selected = 0 } }
            'O' { if ($ctrl -and $list.Count -gt 0) {
                    $action = @{ Kind = 'explorer'; Project = $list[$selected] }; break loop }
                  elseif (-not $ctrl) { $query += $k.KeyChar; $selected = 0 } }
            default {
                if ($k.KeyChar -and -not [char]::IsControl($k.KeyChar)) { $query += $k.KeyChar; $selected = 0 }
            }
        }
        $list = @(Find-Project $query)
        if ($selected -ge $list.Count) { $selected = [Math]::Max(0, $list.Count - 1) }
        Show-Frame $list
    }
} finally {
    # finally, not after the loop: on Ctrl+C or an exception the terminal would
    # otherwise stay in the alternate buffer with a hidden cursor (and the switched
    # encoding).
    Exit-AltBuffer
    [Console]::OutputEncoding = $originalEncoding
}

if ($action) {
    switch ($action.Kind) {
        'editor' {
            if (-not (Open-ProjectInEditor -Project $action.Project -DryRun:$DryRun)) {
                Write-Warning "VS Code (`code`) is not on PATH."
            }
        }
        'explorer' { Open-ProjectInExplorer -Project $action.Project -DryRun:$DryRun | Out-Null }
        default {
            Start-Project -Project $action.Project -DryRun:$DryRun `
                -NewWindow:([bool]$action.NewWindow) -Continue:([bool]$action.Continue) `
                -ShellOnly:([bool]$action.ShellOnly)
        }
    }
}
