#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.5' }

# Smoke tests that need neither Windows Terminal nor Claude Code: they build a small
# workspace in TestDrive, run the indexer against it and exercise the shared core.

BeforeAll {
    $repoRoot = Split-Path $PSScriptRoot -Parent

    # Work on a copy so index.json / history.json never land in the checkout.
    $script:app = Join-Path $TestDrive 'hangar'
    New-Item -ItemType Directory $script:app | Out-Null
    Copy-Item (Join-Path $repoRoot '*.ps1') $script:app

    $script:workspace = Join-Path $TestDrive 'code'
    $script:home_     = Join-Path $TestDrive 'home'
    New-Item -ItemType Directory $script:workspace, $script:home_ | Out-Null

    function New-TestRepo([string]$Rel, [int]$Todos = 0) {
        $dir = Join-Path $script:workspace $Rel
        New-Item -ItemType Directory -Force $dir | Out-Null
        Set-Content (Join-Path $dir 'README.md') "# $Rel"
        if ($Todos) { Set-Content (Join-Path $dir 'TODO.md') (1..$Todos | ForEach-Object { "- [ ] task $_" }) }
        git -C $dir init -q
        git -C $dir add .
        git -C $dir -c user.name=test -c user.email=test@example.com commit -q -m "init $Rel"
    }

    New-TestRepo 'business/reports/ng' -Todos 3
    New-TestRepo 'business/reports/ng-legacy'
    New-TestRepo 'private/apps/something'
    New-Item -ItemType Directory -Force (Join-Path $script:workspace 'sandbox') | Out-Null
    Set-Content (Join-Path $script:workspace 'sandbox/CLAUDE.md') '# sandbox'
    # Not a project: no .git and no CLAUDE.md.
    New-Item -ItemType Directory -Force (Join-Path $script:workspace 'notes') | Out-Null

    $env:HANGAR_ROOT  = $script:workspace
    $env:USERPROFILE  = $script:home_
    if (-not $env:LOCALAPPDATA) { $env:LOCALAPPDATA = $script:home_ }

    & pwsh -NoProfile -File (Join-Path $script:app 'hangar-index.ps1') | Out-Null
    . (Join-Path $script:app 'hangar-core.ps1')
    $ErrorActionPreference = 'Continue'
    Import-HangarIndex -MaxAgeMinutes 99999
}

Describe 'Scripts' {
    It '<_> parses without errors' -ForEach @(Get-ChildItem (Join-Path (Split-Path $PSScriptRoot -Parent) '*.ps1') | ForEach-Object Name) {
        $errors = $null
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) $_
        [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors) | Out-Null
        $errors | Should -BeNullOrEmpty
    }
}

Describe 'hangar-index.ps1' {
    It 'finds folders with .git or CLAUDE.md and nothing else' {
        (Get-HangarProjects).id | Sort-Object |
            Should -Be @('business/reports/ng', 'business/reports/ng-legacy', 'private/apps/something', 'sandbox')
    }

    It 'assigns groups by top-level folder' {
        $byId = @{}; Get-HangarProjects | ForEach-Object { $byId[$_.id] = $_ }
        $byId['business/reports/ng'].group    | Should -Be 'business'
        $byId['private/apps/something'].group | Should -Be 'private'
        $byId['sandbox'].group                | Should -Be 'root'
    }

    It 'counts open TODO items and reads git metadata' {
        $ng = Get-HangarProjects | Where-Object id -eq 'business/reports/ng'
        $ng.openTodos | Should -Be 3
        $ng.git.lastCommitSubject | Should -Be 'init business/reports/ng'
        $ng.git.dirty | Should -Be 0
    }

    It 'leaves git empty for a CLAUDE.md-only project' {
        (Get-HangarProjects | Where-Object id -eq 'sandbox').git | Should -BeNullOrEmpty
    }
}

Describe 'Find-Project' {
    It 'ranks the exact name first' {
        (Find-Project 'ng')[0].id | Should -Be 'business/reports/ng'
    }

    It 'matches on the path as well' {
        (Find-Project 'reports').id | Should -Contain 'business/reports/ng-legacy'
    }

    It 'returns nothing for an unknown query' {
        @(Find-Project 'zzz-no-such-project') | Should -HaveCount 0
    }

    It 'orders an empty query by frecency' {
        Register-ProjectLaunch 'sandbox'
        (Find-Project '')[0].id | Should -Be 'sandbox'
    }
}

Describe 'Format-Age' {
    It 'formats <Offset> as <Expected>' -ForEach @(
        @{ Offset = [timespan]::FromMinutes(5);  Expected = '5m' }
        @{ Offset = [timespan]::FromHours(5);    Expected = '5h' }
        @{ Offset = [timespan]::FromDays(20);    Expected = '20d' }
        @{ Offset = [timespan]::FromDays(800);   Expected = '2y' }
    ) {
        Format-Age ([datetimeoffset]::Now - $Offset).ToString('o') | Should -Be $Expected
    }

    It 'returns an empty string for missing input' {
        Format-Age '' | Should -Be ''
        Format-Age 'not a date' | Should -Be ''
    }
}

Describe 'Start-Project -DryRun' {
    It 'builds a wt command with a clean environment and the launcher' {
        $project = (Find-Project 'ng')[0]
        $out = Start-Project -Project $project -DryRun -Continue 6>&1 | Out-String
        $out | Should -Match '--reloadEnvironment'
        $out | Should -Match 'hangar-launch\.ps1'
        $out | Should -Match '-Name ng -Continue'
        $out | Should -Match '#C0392B'
    }

    It 'opens a plain shell without the launcher' {
        $project = (Find-Project 'something')[0]
        $out = Start-Project -Project $project -DryRun -ShellOnly 6>&1 | Out-String
        $out | Should -Not -Match 'hangar-launch\.ps1'
        $out | Should -Match '--suppressApplicationTitle'
    }
}
