' Launches hangar-gui.ps1 without a console window flashing up first.
'
' PowerShell 7 ships no windowless host (there is no pwshw.exe), so even
' `pwsh -WindowStyle Hidden` creates a console and hides it a moment later — on a
' desktop shortcut that reads as a glitch. WScript.Shell.Run with intWindowStyle 0
' never creates the window at all.
'
' The script resolves its own folder, so the shortcut works from anywhere and the
' path is not baked in (the same checkout works on machines with different user
' names).

Dim shell, base
Set shell = CreateObject("WScript.Shell")
base = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))
shell.Run "pwsh.exe -NoProfile -File """ & base & "hangar-gui.ps1""", 0, False
