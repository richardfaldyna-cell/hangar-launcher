# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.0] - 2026-09-26

### Added

- Terminal picker (`hangar`) and WPF window (`hangar -Gui`) sharing one core.
- Direct launch of the best match (`hangar <name>`) and `-DryRun`.
- Frecency ranking with a 10-day half-life, seeded from Claude Code session history.
- Git status, open `TODO.md` tasks and Claude Code worktrees per project.
- Launching `claude` in a new Windows Terminal tab or window, with `--continue`,
  a plain shell, VS Code and Explorer as alternatives.
- Configuration through `HANGAR_ROOT` and `HANGAR_MACHINE_PREFIX`.
- Desktop shortcuts (`install-shortcuts.ps1`) and a generated icon (`make-icon.ps1`).
- CI with PSScriptAnalyzer and Pester smoke tests.

[Unreleased]: https://github.com/richardfaldyna-cell/hangar-launcher/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/richardfaldyna-cell/hangar-launcher/releases/tag/v1.0.0
