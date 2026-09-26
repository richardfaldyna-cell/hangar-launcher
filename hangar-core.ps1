<#
.SYNOPSIS
    Shared layer for Hangar: index loading, search, frecency, launching.

.DESCRIPTION
    Dot-sourced by both front ends — hangar.ps1 (terminal picker) and
    hangar-gui.ps1 (WPF window). Everything that is not drawing lives here, so a
    second front end costs a presentation layer and nothing else.

    Launching in particular must stay in one place: it encodes findings that were
    expensive to make (see the comments in Start-Project) and would silently rot in
    a copy.
#>

$ErrorActionPreference = 'Stop'

$script:HangarRoot     = $null
$script:HangarProjects = @()
$script:HangarHistory  = @{}

$script:IndexFile   = Join-Path $PSScriptRoot 'index.json'
$script:IndexScript = Join-Path $PSScriptRoot 'hangar-index.ps1'
# Launch history is per machine (like the index) and never leaves the disk.
$script:HistoryFile = Join-Path $PSScriptRoot 'history.json'

# Frecency half-life. Ten days suits a workspace that rotates between a handful of
# active projects: a repo touched today outranks one touched last week, and a repo
# untouched for a month drops out of sight without disappearing.
$script:FrecencyHalfLifeDays = 10
# How many launches to remember per project. Older entries weigh almost nothing
# after a few half-lives, so keeping more would only grow the file.
$script:HistoryDepth = 40

# --- index -------------------------------------------------------------------------

function ConvertTo-DateOffset {
    <#  Parses an ISO timestamp, returning $null instead of throwing. Index fields
        are best-effort and a broken one must never take a front end down. #>
    param([string]$Text)
    if (-not $Text) { return $null }
    try { return [datetimeoffset]::Parse($Text, [cultureinfo]::InvariantCulture) } catch { return $null }
}

function Import-HangarIndex {
    <#  Loads index.json. A stale index is used as-is and refreshed in the
        background — the picker must never wait on git. #>
    param(
        [switch]$Refresh,
        [int]$MaxAgeMinutes = 60
    )

    if ($Refresh -or -not (Test-Path -LiteralPath $script:IndexFile)) {
        & pwsh -NoProfile -File $script:IndexScript | Out-Null
    } elseif ((Get-Date) - (Get-Item -LiteralPath $script:IndexFile).LastWriteTime -gt
              [TimeSpan]::FromMinutes($MaxAgeMinutes)) {
        Start-Process pwsh -ArgumentList '-NoProfile', '-File', $script:IndexScript -WindowStyle Hidden
    }

    $index = Get-Content -LiteralPath $script:IndexFile -Raw | ConvertFrom-Json
    $script:HangarRoot     = $index.root
    $script:HangarProjects = @($index.projects)
    Import-HangarHistory
}

function Get-HangarRoot     { $script:HangarRoot }
function Get-HangarProjects { $script:HangarProjects }

function Get-ProjectPath {
    param($Project)
    if ($Project.id -eq '.') { return $script:HangarRoot }
    Join-Path $script:HangarRoot ($Project.id -replace '/', '\')
}

# --- frecency ----------------------------------------------------------------------

function Import-HangarHistory {
    $script:HangarHistory = @{}
    if (-not (Test-Path -LiteralPath $script:HistoryFile)) { return }
    try {
        $raw = Get-Content -LiteralPath $script:HistoryFile -Raw | ConvertFrom-Json
        foreach ($entry in $raw.PSObject.Properties) {
            $script:HangarHistory[$entry.Name] = @($entry.Value)
        }
    } catch {
        # A corrupt history costs ordering quality, nothing else — start over quietly.
        $script:HangarHistory = @{}
    }
}

function Register-ProjectLaunch {
    <#  Records that a project was actually launched. This is the frequency half of
        frecency — lastSessionAt alone only knows recency. #>
    param([string]$Id)
    $stamps = @([datetimeoffset]::Now.ToString('o'))
    if ($script:HangarHistory.ContainsKey($Id)) {
        $stamps += @($script:HangarHistory[$Id])
    }
    $script:HangarHistory[$Id] = @($stamps | Select-Object -First $script:HistoryDepth)
    try {
        $script:HangarHistory | ConvertTo-Json -Depth 3 |
            Set-Content -LiteralPath $script:HistoryFile -Encoding UTF8
    } catch {
        # Ordering is a convenience; failing to persist it must not block a launch.
    }
}

function Get-FrecencyScore {
    <#  Sum of exponentially decayed launch weights, seeded from the last terminal
        session so the ordering is useful before any history exists. #>
    param($Project, [datetimeoffset]$Now)

    $score = 0.0
    foreach ($stamp in @($script:HangarHistory[$Project.id])) {
        $when = ConvertTo-DateOffset $stamp
        if (-not $when) { continue }
        $ageDays = ($Now - $when).TotalDays
        $score += [Math]::Pow(2, -$ageDays / $script:FrecencyHalfLifeDays)
    }

    # A terminal session is evidence of work, but weaker than choosing the project
    # here on purpose — hence the 0.6 factor rather than counting it as a launch.
    $session = ConvertTo-DateOffset $Project.claude.lastSessionAt
    if ($session) {
        $ageDays = ($Now - $session).TotalDays
        $score += 0.6 * [Math]::Pow(2, -$ageDays / $script:FrecencyHalfLifeDays)
    }
    $score
}

# --- search ------------------------------------------------------------------------

function Find-Project {
    <#  Weighted fuzzy filter over name and path. Weight order matters: without it
        "ng" matched "+Codi_ng_" before the project actually called "ng".
        Frecency breaks ties, and orders everything when the query is empty. #>
    param([string]$Query)

    $now = [datetimeoffset]::Now

    if (-not $Query) {
        return @($script:HangarProjects |
            Sort-Object -Property `
                @{ Expression = { Get-FrecencyScore $_ $now }; Descending = $true },
                @{ Expression = { $_.name } })
    }

    $pattern = ($Query.ToCharArray() | ForEach-Object { [regex]::Escape($_) }) -join '.*'
    $scored = foreach ($p in $script:HangarProjects) {
        $weight = if     ($p.name -ieq $Query)        { 0 }
                  elseif ($p.name -ilike "$Query*")   { 1 }
                  elseif ($p.name -ilike "*$Query*")  { 2 }
                  elseif ($p.name -imatch $pattern)   { 3 }
                  elseif ($p.id   -ilike "*$Query*")  { 4 }
                  elseif ($p.id   -imatch $pattern)   { 5 }
                  else                                { $null }
        if ($null -ne $weight) {
            [pscustomobject]@{ Project = $p; Weight = $weight; Score = (Get-FrecencyScore $p $now) }
        }
    }

    @($scored |
        Sort-Object -Property `
            @{ Expression = { $_.Weight } },
            @{ Expression = { $_.Score }; Descending = $true },
            @{ Expression = { $_.Project.name.Length } },
            @{ Expression = { $_.Project.id } } |
        ForEach-Object Project)
}

# --- formatting --------------------------------------------------------------------

function Format-Age {
    <#  "12m" / "5h" / "20d" / "2y". Empty string when the value is missing or
        unparseable, so the column simply stays blank. #>
    param([string]$Iso)
    $when = ConvertTo-DateOffset $Iso
    if (-not $when) { return '' }
    $d = [datetimeoffset]::Now - $when
    if ($d.TotalMinutes -lt 60)  { return ('{0:0}m' -f $d.TotalMinutes) }
    if ($d.TotalHours   -lt 24)  { return ('{0:0}h' -f $d.TotalHours) }
    if ($d.TotalDays    -lt 365) { return ('{0:0}d' -f $d.TotalDays) }
    ('{0:0}y' -f ($d.TotalDays / 365))
}

# --- launching ---------------------------------------------------------------------

function Get-TerminalProfileName {
    <#  Name of the WT profile the new tab should take its LOOK from (colorScheme,
        font, opacity). A bare `wt nt … pwsh` matches no profile and the tab falls
        back to WT's built-in defaults (Campbell + Cascadia Mono) — MS Learn says so
        outright: "If you're launching a profile (shell executable combined with
        color scheme, title, command …), you must use the profile name."
        The look is inherited from the profile of the tab the picker runs in
        ($env:WT_PROFILE_ID); outside WT, from defaultProfile.
        Returns $null when nothing can be resolved -> `-p` is omitted. #>
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\settings.json')
    )
    $file = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $file) { return $null }
    try {
        # PS7 parses JSON via Newtonsoft, so `//` comments in WT settings are fine.
        $settings = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json
    } catch { return $null }
    $guid = if ($env:WT_PROFILE_ID) { $env:WT_PROFILE_ID } else { $settings.defaultProfile }
    if (-not $guid) { return $null }
    ($settings.profiles.list | Where-Object { $_.guid -eq $guid } | Select-Object -First 1).name
}

function Add-QuotesIfNeeded {
    <#  Start-Process -ArgumentList in PS 7.6 joins the array with spaces and does NOT
        quote, so `-d C:\…\my project` reaches wt as two arguments. Verified
        2026-08-23 on project folders whose names contain a space. #>
    param([string]$Value)
    if ($Value -match '\s') { '"' + $Value + '"' } else { $Value }
}

function Start-Project {
    <#  Opens the project. Always through Start-Process — wt is a Store app and a
        direct call would block the prompt until the window closes. #>
    param(
        [Parameter(Mandatory)] $Project,
        [switch]$NewWindow,
        [switch]$Continue,
        [switch]$ShellOnly,
        [switch]$DryRun
    )

    $path = Get-ProjectPath $Project

    # Target window. `-w 0` = most recently used window = the one the picker runs in,
    # so the tab lands HERE. The original `-w hangar` opened a separate
    # named window — and since a tab can only be moved out of it by dragging, it took
    # down all of Windows Terminal on 2026-08-23 (tab tear-out,
    # Microsoft.Terminal.Control.dll, 0xc0000005). A named window is therefore only
    # used where the picker is not inside WT (no WT_SESSION) and `-w 0` has no target.
    $window = if     ($NewWindow)        { '-1' }
              elseif ($env:WT_SESSION)   { '0' }
              else                       { 'hangar' }
    # Tab colour by group: red for business/, blue for everything else.
    $color = if ($Project.group -eq 'business') { '#C0392B' } else { '#1A6FB5' }

    # `-p <profile>` must come before the commandline; the profile supplies the look,
    # the commandline overrides its `commandline`. Without a resolvable profile, skip it.
    # Not $profile — that is an automatic variable ($PROFILE) and shadowing it here
    # would be a trap for anyone later adding profile-related code to this function.
    $profileName = Get-TerminalProfileName
    $profileArg = if ($profileName) { @('-p', (Add-QuotesIfNeeded $profileName)) } else { @() }

    # --reloadEnvironment = the tab gets a FRESH environment block instead of an
    # inherited one. WT always inherits when a commandline is passed (documented
    # `--inheritEnvironment` behaviour). Launching hangar FROM a Claude Code session
    # therefore leaked NO_COLOR -> the new claude lost its orange and fell back to the
    # ANSI palette (verified 2026-08-23 by a window capture). CLAUDECODE, CLAUDE_PID,
    # GIT_EDITOR, GIT_ASKPASS and CLAUDE_CODE_* travelled the same way.
    $envArg = @('--reloadEnvironment')

    if ($ShellOnly) {
        # Without claude nothing sets the title -> --title + suppress.
        $wtArgs = @('-w', $window, 'nt') + $profileArg + $envArg + @(
            '-d', (Add-QuotesIfNeeded $path),
            '--title', (Add-QuotesIfNeeded $Project.name), '--suppressApplicationTitle',
            '--tabColor', $color, 'pwsh', '-NoExit')
    } else {
        # CAREFUL: the command handed to wt must contain no `;` or `|` — wt reads the
        # semicolon as its own command separator and would split a "cleanup; claude"
        # one-liner (lesson learned: the CLAUDE_CODE_CHILD_SESSION marker then survived
        # and switched transcript saving off). Cleanup + launch therefore live in
        # hangar-launch.ps1.
        $launcher = Join-Path $PSScriptRoot 'hangar-launch.ps1'
        $wtArgs = @('-w', $window, 'nt') + $profileArg + $envArg + @(
            '-d', (Add-QuotesIfNeeded $path),
            '--tabColor', $color, 'pwsh', '-NoExit',
            '-File', (Add-QuotesIfNeeded $launcher), '-Name', (Add-QuotesIfNeeded $Project.name))
        if ($Continue) { $wtArgs += '-Continue' }
    }

    if ($DryRun) {
        Write-Host "[dry run] wt $($wtArgs -join ' ')"
        return
    }

    Start-Process wt -ArgumentList $wtArgs   # never call wt directly, see above
    Register-ProjectLaunch $Project.id
}

function Open-ProjectInEditor {
    <#  Alternative action: open the folder in VS Code. Falls back silently when
        `code` is not on PATH — a missing editor is not worth an error dialog. #>
    param([Parameter(Mandatory)] $Project, [switch]$DryRun)
    $path = Get-ProjectPath $Project
    # $true on a dry run too — a bare `return` would send the caller down the
    # "code is not on PATH" branch.
    if ($DryRun) { Write-Host "[dry run] code `"$path`""; return $true }
    $code = Get-Command code -ErrorAction SilentlyContinue
    if (-not $code) { return $false }
    Start-Process $code.Source -ArgumentList (Add-QuotesIfNeeded $path)
    Register-ProjectLaunch $Project.id
    $true
}

function Open-ProjectInExplorer {
    <#  Alternative action: reveal the folder in Explorer. #>
    param([Parameter(Mandatory)] $Project, [switch]$DryRun)
    $path = Get-ProjectPath $Project
    if ($DryRun) { Write-Host "[dry run] explorer `"$path`""; return }
    Start-Process explorer.exe -ArgumentList (Add-QuotesIfNeeded $path)
    $true
}
