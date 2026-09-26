# Contributing to Hangar

Hangar is a personal tool shared as is. Bug reports and small, focused pull requests
are welcome. There is no promise of a response time or of new features.

## Reporting a bug

Open an [issue](https://github.com/richardfaldyna-cell/hangar-launcher/issues/new/choose)
and include:

- Windows, PowerShell (`$PSVersionTable.PSVersion`) and Windows Terminal versions
- the command you ran (`hangar ng -DryRun` output helps a lot)
- what you expected and what happened instead

Security issues are handled separately. See [SECURITY.md](SECURITY.md).

## Pull requests

1. Keep a pull request to one change. Discuss larger ideas in an issue first.
2. Match the surrounding code: English identifiers and comments, and comments that
   explain *why* rather than *what*.
3. Run the same checks as CI before you push (PowerShell 7):

   ```powershell
   Install-Module PSScriptAnalyzer, Pester -Scope CurrentUser
   Invoke-ScriptAnalyzer -Path . -Recurse -Settings ./PSScriptAnalyzerSettings.psd1
   Invoke-Pester ./tests
   ```

4. Add or update tests in `tests/` when you change indexing, search or launching.
5. Note user-visible changes in [CHANGELOG.md](CHANGELOG.md) under *Unreleased*.

By contributing you agree that your contribution is licensed under the
[MIT License](LICENSE) and that you follow the [Code of Conduct](CODE_OF_CONDUCT.md).
