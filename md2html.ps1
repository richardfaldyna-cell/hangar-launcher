<#
.SYNOPSIS
    Renders a Markdown document to its styled HTML twin (README.md -> README.html).

.DESCRIPTION
    A standalone HTML copy of a long document can be read outside an editor and
    survives being copied or mailed on its own. Keeping such a copy in sync by hand
    does not scale, so this script regenerates it instead.

    Conversion uses PowerShell 7's built-in ConvertFrom-Markdown (Markdig), so there
    is no dependency beyond pwsh itself.

.EXAMPLE
    ./md2html.ps1 README.md
    ./md2html.ps1 README.md -Destination C:\temp\hangar.html
#>
[CmdletBinding()]
param(
    # Markdown file to render. Relative paths resolve against the script directory.
    [Parameter(Mandatory)]
    [string]$Source,
    # Output file. Defaults to the source with an .html extension.
    [string]$Destination
)

$ErrorActionPreference = 'Stop'

if (-not [System.IO.Path]::IsPathRooted($Source)) {
    $Source = Join-Path $PSScriptRoot $Source
}
$Source = (Resolve-Path -LiteralPath $Source).Path
if (-not $Destination) {
    $Destination = [System.IO.Path]::ChangeExtension($Source, '.html')
}

# Shared stylesheet for every generated document. Inlined on purpose:
# the HTML twin has to survive being copied or mailed on its own.
$style = @'
:root{--blue:#1a4f8a;--blue-l:#2f6fb5;--bg:#f7f9fc;--card:#fff;--bd:#dce4ee;--txt:#1f2933;--muted:#5b6b7c;}
*{box-sizing:border-box}
body{margin:0;padding:0;background:var(--bg);color:var(--txt);
     font-family:"Segoe UI",-apple-system,Roboto,Arial,sans-serif;line-height:1.65;font-size:16px}
.wrap{max-width:980px;margin:0 auto;padding:40px 28px 90px}
h1{color:var(--blue);font-size:2.1rem;font-weight:600;margin:0 0 .3em;
   border-bottom:3px solid var(--blue);padding-bottom:.3em}
h2{color:var(--blue);font-size:1.45rem;font-weight:600;margin:2.1em 0 .6em;
   border-bottom:1px solid var(--bd);padding-bottom:.25em}
h3{color:var(--blue-l);font-size:1.15rem;font-weight:600;margin:1.6em 0 .4em}
h4{color:var(--blue-l);font-size:1rem;font-weight:600;margin:1.3em 0 .3em}
a{color:var(--blue-l);text-decoration:none}
a:hover{text-decoration:underline}
blockquote{margin:1.2em 0;padding:.8em 1.2em;background:#eaf2fb;
           border-left:4px solid var(--blue-l);border-radius:0 6px 6px 0;color:#22384f}
blockquote p{margin:.4em 0}
table{border-collapse:collapse;width:100%;margin:1.2em 0;background:var(--card);
      font-size:.94rem;box-shadow:0 1px 3px rgba(26,79,138,.08);border-radius:6px;overflow:hidden;display:block;overflow-x:auto}
th{background:var(--blue);color:#fff;text-align:left;font-weight:600;padding:9px 12px;white-space:nowrap}
td{border-top:1px solid var(--bd);padding:9px 12px;vertical-align:top}
tr:nth-child(even) td{background:#fafcff}
code{background:#eef3f9;color:#0f3c66;padding:.12em .38em;border-radius:4px;
     font-family:Consolas,"Cascadia Mono",monospace;font-size:.9em}
pre{background:#0f2438;color:#e6edf3;padding:16px 18px;border-radius:8px;overflow-x:auto;
    font-family:Consolas,"Cascadia Mono",monospace;font-size:.88rem;line-height:1.5}
pre code{background:none;color:inherit;padding:0}
hr{border:0;border-top:1px solid var(--bd);margin:2.4em 0}
ul,ol{padding-left:1.5em}
li{margin:.25em 0}
li input[type=checkbox]{margin-right:.5em}
.footer{margin-top:3em;padding-top:1em;border-top:1px solid var(--bd);
        color:var(--muted);font-size:.85rem}
img{max-width:100%;height:auto;border:1px solid var(--bd);border-radius:8px;
    box-shadow:0 2px 10px rgba(15,36,56,.12);margin:.6em 0}
@media print{body{background:#fff}.wrap{max-width:none;padding:0}}
'@

$body = (ConvertFrom-Markdown -LiteralPath $Source).Html

# Local images are inlined as data URIs. The HTML twin has to survive being copied
# or mailed on its own — a bare <img src="img/..."> would break the moment the file
# leaves the repo folder. Remote and already-inlined sources are left untouched;
# a missing or unknown file keeps its original reference rather than failing.
$sourceDir = Split-Path $Source
$body = [regex]::Replace($body, '<img src="([^"]+)"', {
    param($m)
    $ref = $m.Groups[1].Value
    if ($ref -match '^(https?:|data:)') { return $m.Value }
    $file = Join-Path $sourceDir ([uri]::UnescapeDataString($ref) -replace '/', '\')
    if (-not (Test-Path -LiteralPath $file)) { return $m.Value }
    $mime = switch ([System.IO.Path]::GetExtension($file).ToLower()) {
        '.png'  { 'image/png' }
        '.jpg'  { 'image/jpeg' }
        '.jpeg' { 'image/jpeg' }
        '.gif'  { 'image/gif' }
        '.svg'  { 'image/svg+xml' }
        default { $null }
    }
    if (-not $mime) { return $m.Value }
    $b64 = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($file))
    '<img src="data:' + $mime + ';base64,' + $b64 + '"'
})

# Document title = text of the first H1 with inline markup stripped out.
$heading = [regex]::Match($body, '(?s)<h1[^>]*>(.*?)</h1>')
$title = if ($heading.Success) {
    [System.Net.WebUtility]::HtmlDecode(($heading.Groups[1].Value -replace '<[^>]+>', '')).Trim()
} else {
    [System.IO.Path]::GetFileNameWithoutExtension($Source)
}

$sourceName = Split-Path -Leaf $Source
$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$([System.Net.WebUtility]::HtmlEncode($title))</title>
<style>
$style
</style>
</head>
<body>
<div class="wrap">
$body<div class="footer">Generated from $sourceName</div>
</div>
</body>
</html>
"@

# UTF-8 without BOM — browsers read the <meta charset>, and a BOM only shows up as
# stray characters when the file is inlined somewhere else.
[System.IO.File]::WriteAllText($Destination, $html, [System.Text.UTF8Encoding]::new($false))
Write-Host "$sourceName -> $(Split-Path -Leaf $Destination) ($($html.Length) characters)"
