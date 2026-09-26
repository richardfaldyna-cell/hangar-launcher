<#
.SYNOPSIS
    Generates img/hangar.ico — the icon used by the desktop shortcuts.

.DESCRIPTION
    A hangar seen head-on: rounded arch with an open doorway, on the same blue the
    picker uses for private projects (#1A6FB5). Drawn rather than downloaded so the
    repo stays self-contained and the icon can be regenerated at any size.

    A real multi-resolution .ico is written by hand — System.Drawing's Icon.Save
    only round-trips an existing icon, and Bitmap.Save(..., Icon) is not supported.
    The file therefore gets an ICONDIR header plus one PNG-compressed entry per size,
    which every Windows version since Vista understands.

.EXAMPLE
    ./make-icon.ps1
#>
[CmdletBinding()]
param(
    # Where to write the icon.
    [string]$Path,
    # Accent colour of the arch.
    [string]$Color = '#1A6FB5'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

if (-not $Path) { $Path = Join-Path $PSScriptRoot 'img\hangar.ico' }
New-Item -ItemType Directory -Force (Split-Path $Path) | Out-Null

$sizes = 16, 24, 32, 48, 64, 128, 256

function New-HangarBitmap([int]$S) {
    $bmp = [System.Drawing.Bitmap]::new($S, $S, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.Clear([System.Drawing.Color]::Transparent)

    $accent = [System.Drawing.ColorTranslator]::FromHtml($Color)
    # Lighter tint for the arch face; the doorway stays transparent so the icon reads
    # on both light and dark taskbars.
    $light = [System.Drawing.Color]::FromArgb(255,
        [Math]::Min(255, $accent.R + 60), [Math]::Min(255, $accent.G + 60), [Math]::Min(255, $accent.B + 60))

    $pad = [Math]::Max(1, [int]($S * 0.08))
    $w = $S - 2 * $pad
    $h = [int]($S * 0.66)
    $top = $S - $pad - $h

    # Outer shell: arch = rectangle with a half-round top.
    $shell = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $r = [int]($w / 2)
    $shell.AddArc($pad, $top, $w, $w, 180, 180)          # rounded roof
    $shell.AddLine($pad + $w, $top + $r, $pad + $w, $S - $pad)
    $shell.AddLine($pad + $w, $S - $pad, $pad, $S - $pad)
    $shell.CloseFigure()

    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.Point]::new(0, $top), [System.Drawing.Point]::new(0, $S),
        $light, $accent)
    $g.FillPath($brush, $shell)

    # Doorway: same arch shape, scaled down and punched out.
    $dw = [int]($w * 0.46)
    $dx = $pad + [int](($w - $dw) / 2)
    $dh = [int]($h * 0.62)
    $dy = $S - $pad - $dh
    $door = [System.Drawing.Drawing2D.GraphicsPath]::new()
    $door.AddArc($dx, $dy, $dw, $dw, 180, 180)
    $door.AddLine($dx + $dw, $dy + [int]($dw / 2), $dx + $dw, $S - $pad)
    $door.AddLine($dx + $dw, $S - $pad, $dx, $S - $pad)
    $door.CloseFigure()
    $g.SetClip($door)
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.ResetClip()

    $brush.Dispose(); $shell.Dispose(); $door.Dispose(); $g.Dispose()
    $bmp
}

# Render every size to an in-memory PNG first.
$pngs = foreach ($s in $sizes) {
    $bmp = New-HangarBitmap $s
    $ms = [System.IO.MemoryStream]::new()
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bmp.Dispose()
    [pscustomobject]@{ Size = $s; Bytes = $ms.ToArray() }
}

# ICONDIR (6 B) + ICONDIRENTRY (16 B each) + the PNG payloads.
$out = [System.IO.MemoryStream]::new()
$bw = [System.IO.BinaryWriter]::new($out)
$bw.Write([uint16]0)                 # reserved
$bw.Write([uint16]1)                 # type 1 = icon
$bw.Write([uint16]$pngs.Count)

$offset = 6 + 16 * $pngs.Count
foreach ($p in $pngs) {
    # 256 px is stored as 0 — the field is a single byte.
    $bw.Write([byte]($(if ($p.Size -ge 256) { 0 } else { $p.Size })))
    $bw.Write([byte]($(if ($p.Size -ge 256) { 0 } else { $p.Size })))
    $bw.Write([byte]0)               # palette colours
    $bw.Write([byte]0)               # reserved
    $bw.Write([uint16]1)             # colour planes
    $bw.Write([uint16]32)            # bits per pixel
    $bw.Write([uint32]$p.Bytes.Length)
    $bw.Write([uint32]$offset)
    $offset += $p.Bytes.Length
}
foreach ($p in $pngs) { $bw.Write($p.Bytes) }
$bw.Flush()

[System.IO.File]::WriteAllBytes($Path, $out.ToArray())
$bw.Dispose(); $out.Dispose()
Write-Host "$Path  ($((Get-Item $Path).Length) B, sizes: $($sizes -join ', '))"
