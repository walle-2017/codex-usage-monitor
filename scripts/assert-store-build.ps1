Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Cargo = Get-Content -Raw -LiteralPath 'Cargo.toml'
$Window = Get-Content -Raw -LiteralPath 'src/window.rs'
$Workflow = Get-Content -Raw -LiteralPath '.github/workflows/store-msix.yml'

if (-not $Cargo.Contains('default = ["github-update"]')) { throw 'Default standalone build must enable github-update.' }
if (-not $Cargo.Contains('store = []')) { throw 'Cargo must define the store feature.' }
if (-not $Workflow.Contains('--no-default-features --features store')) { throw 'Store workflow must build with the store-only feature set.' }
if (-not $Window.Contains('#[cfg(feature = "github-update")]')) { throw 'Update startup/command paths must be gated for Store builds.' }
if (-not $Window.Contains('v{} (Microsoft Store)')) { throw 'Store build must expose a non-clickable Store version label.' }

Write-Output 'PASS: Microsoft Store builds disable GitHub executable self-update while standalone builds keep it.'
exit 0
