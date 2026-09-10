Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ReleaseWorkflow = Get-Content -Raw -LiteralPath '.github/workflows/release.yml'

$Required = @(
    'Copy-Item target/release/codex-usage-win.exe dist/codex-usage.exe',
    'dist/codex-usage.exe.sha256',
    'dist/codex-usage.exe'
)

foreach ($Text in $Required) {
    if (-not $ReleaseWorkflow.Contains($Text)) {
        throw "v1.0.3 update compatibility is missing from release workflow: $Text"
    }
}

if (-not $ReleaseWorkflow.Contains('codex-usage.exe" | Set-Content -Encoding ascii dist/codex-usage.exe.sha256')) {
    throw 'Legacy checksum asset must describe codex-usage.exe for v1.0.3 clients.'
}

Write-Output 'PASS: future Releases retain v1.0.3 updater compatibility assets.'
exit 0
