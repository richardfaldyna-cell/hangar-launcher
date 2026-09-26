# Security Policy

## Supported versions

Only the latest commit on `main` receives fixes.

## Reporting a vulnerability

Please do **not** open a public issue for security problems. Report them privately
through [GitHub private vulnerability reporting](https://github.com/richardfaldyna-cell/hangar-launcher/security/advisories/new).

Include a description of the issue, the steps to reproduce it and the impact you
expect. This is a personal project maintained in spare time, so replies are best
effort.

## Scope

Hangar runs locally, reads your project folders and starts `wt`, `pwsh`, `claude`,
`code` and `explorer`. Anything that makes it run an unexpected command or read
outside the configured workspace root is in scope.
