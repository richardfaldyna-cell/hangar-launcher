<#
.SYNOPSIS
    Generates index.json — the catalogue of every project under the workspace root.

.DESCRIPTION
    Project = a folder containing .git OR CLAUDE.md. Folders under .claude/worktrees
    do not count as projects — they are listed under their parent in worktrees[].

    The workspace root is $env:HANGAR_ROOT. When it is not set, the parent folder of
    the Hangar checkout is used (clone Hangar next to your other projects and it
    finds them).

    All paths in the index are RELATIVE to the workspace root (portable between
    machines with different user names). index.json is machine specific and
    therefore in .gitignore.

.NOTES
    Speed: git queries over ~60 repos take a few seconds. The picker (hangar.ps1)
    always reads the finished JSON; this script runs in the background or via
    -Refresh.
#>
[CmdletBinding()]
param(
    # Skip git metadata (fast mode, project list only).
    [switch]$NoGit
)

$ErrorActionPreference = 'Stop'

# Git prints UTF-8, but PowerShell decodes native command output according to
# [Console]::OutputEncoding — OEM 852 on Czech Windows, other legacy code pages
# elsewhere. Commit subjects with diacritics then turned into mojibake in the index;
# it only showed up in the GUI, because the older git fields were pure ASCII. The
# indexer always runs in its own process (pwsh -File), so switching affects no one.
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# $PSScriptRoot only in the body — with [CmdletBinding()] it is empty in a parameter
# default value.
$workspaceRoot = if ($env:HANGAR_ROOT) { $env:HANGAR_ROOT } else { Join-Path $PSScriptRoot '..' }
if (-not (Test-Path -LiteralPath $workspaceRoot -PathType Container)) {
    throw "Workspace root does not exist: $workspaceRoot (check HANGAR_ROOT)"
}
$workspaceRoot = (Resolve-Path -LiteralPath $workspaceRoot).Path.TrimEnd('\', '/')
$output = Join-Path $PSScriptRoot 'index.json'

# ~/.claude/projects — folder name encoding: every non-alphanumeric character -> '-'
# (verified: C:\Users\me\Documents\code -> C--Users-me-Documents-code).
# Unofficial mapping; when it does not match, the claude field stays empty — never fail.
$claudeProjects = Join-Path $env:USERPROFILE '.claude\projects'

function Get-ClaudeSessionDirName([string]$AbsolutePath) {
    return ($AbsolutePath -replace '[^A-Za-z0-9]', '-')
}

# --- 1. find projects (max 4 levels deep) -------------------------------------------
# .export is skipped too: a full git working copy used for exports would otherwise
# show up in the picker as one more project.
$skip = '\\(\.git|node_modules|\.venv|__pycache__|\.claude|\.export)(\\|$)'
$candidates = [System.Collections.Generic.List[string]]::new()

# The root itself counts as a project when it is a repo or has a CLAUDE.md.
if ((Test-Path (Join-Path $workspaceRoot '.git')) -or
    (Test-Path (Join-Path $workspaceRoot 'CLAUDE.md'))) {
    $candidates.Add($workspaceRoot)
}

Get-ChildItem -LiteralPath $workspaceRoot -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $skip } |
    ForEach-Object {
        if ((Test-Path (Join-Path $_.FullName '.git')) -or
            (Test-Path (Join-Path $_.FullName 'CLAUDE.md'))) {
            $candidates.Add($_.FullName)
        }
    }

# --- 2. per-project metadata --------------------------------------------------------
$projects = foreach ($path in $candidates) {
    $rel = if ($path -eq $workspaceRoot) { '.' }
           else { $path.Substring($workspaceRoot.Length + 1) -replace '\\', '/' }
    $name = Split-Path $path -Leaf
    # Optional convention: projects under business/ and private/ get their own
    # sections and tab colours; everything else falls into "other".
    $group = switch -Regex ($rel) {
        '^business(/|$)' { 'business'; break }
        '^private(/|$)'  { 'private';  break }
        default          { 'root' }
    }

    # TODO.md — number of open tasks (unchecked `- [ ]` items)
    $todoFile = Join-Path $path 'TODO.md'
    $openTodos = 0
    if (Test-Path -LiteralPath $todoFile) {
        $openTodos = @(Select-String -LiteralPath $todoFile -Pattern '^\s*- \[ \]' -ErrorAction SilentlyContinue).Count
    }

    # git metadata — every call guarded, a broken repo must not take the index down
    $git = $null
    if (-not $NoGit -and (Test-Path (Join-Path $path '.git'))) {
        try {
            $branch = git -C $path rev-parse --abbrev-ref HEAD 2>$null
            $dirty  = @(git -C $path status --porcelain 2>$null).Count
            $ahead = 0; $behind = 0
            $upstream = git -C $path rev-parse --abbrev-ref '@{u}' 2>$null
            if ($LASTEXITCODE -eq 0 -and $upstream) {
                # one call instead of two: '--left-right' returns "behind<TAB>ahead"
                $lr = (git -C $path rev-list --count --left-right '@{u}...HEAD' 2>$null) -split '\s+'
                if ($lr.Count -ge 2) { $behind = [int]$lr[0]; $ahead = [int]$lr[1] }
            }
            # One call carries the date, short hash and subject. Separator %x1f (ASCII
            # Unit Separator) rather than | or tab — it practically never appears in a
            # commit message, so a subject containing a pipe or tab does not break the split.
            $logLine = git -C $path log -1 --format='%cI%x1f%h%x1f%s' 2>$null
            $parts = if ($logLine) { $logLine -split "`u{1f}" } else { @() }
            $git = [ordered]@{
                branch            = $branch
                dirty             = $dirty
                ahead             = $ahead
                behind            = $behind
                lastCommit        = if ($parts.Count -ge 1) { $parts[0] } else { $null }
                lastCommitShort   = if ($parts.Count -ge 2) { $parts[1] } else { $null }
                lastCommitSubject = if ($parts.Count -ge 3) { $parts[2] } else { $null }
            }
        } catch { $git = $null }
    }

    # Most recent TERMINAL session (Claude Desktop sessions are not in ~/.claude/projects)
    $claude = $null
    $sessionDir = Join-Path $claudeProjects (Get-ClaudeSessionDirName $path)
    if (Test-Path -LiteralPath $sessionDir) {
        $sessions = @(Get-ChildItem -LiteralPath $sessionDir -Filter '*.jsonl' -ErrorAction SilentlyContinue |
                      Sort-Object LastWriteTime -Descending)
        if ($sessions.Count -gt 0) {
            $claude = [ordered]@{
                lastSessionAt = $sessions[0].LastWriteTime.ToString('o')
                sessionCount  = $sessions.Count
            }
        }
    }

    # Claude Code worktrees as sub-items
    $worktrees = @()
    $wtDir = Join-Path $path '.claude\worktrees'
    if (Test-Path -LiteralPath $wtDir) {
        $worktrees = @(Get-ChildItem -LiteralPath $wtDir -Directory -ErrorAction SilentlyContinue |
                       Select-Object -ExpandProperty Name)
    }

    [ordered]@{
        id          = $rel
        name        = $name
        group       = $group
        hasClaudeMd = Test-Path (Join-Path $path 'CLAUDE.md')
        openTodos   = $openTodos
        git         = $git
        claude      = $claude
        worktrees   = $worktrees
    }
}

# --- 3. write -----------------------------------------------------------------------
$index = [ordered]@{
    generatedAt = (Get-Date).ToString('o')
    root        = $workspaceRoot   # the only absolute path; valid on this machine only
    projects    = @($projects)
}

$index | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $output -Encoding UTF8
Write-Host "index.json: $(@($projects).Count) projects -> $output"
