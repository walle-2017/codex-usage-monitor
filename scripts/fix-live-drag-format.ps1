$ErrorActionPreference = 'Stop'
$path = 'src/window.rs'
$source = Get-Content -Raw -LiteralPath $path
$old = "        }        WM_CANCELMODE => {"
$new = "        }`r`n        WM_CANCELMODE => {"
if (-not $source.Contains($old)) { throw 'Expected live-drag formatting marker not found.' }
Set-Content -LiteralPath $path -Value ($source.Replace($old, $new)) -Encoding utf8
