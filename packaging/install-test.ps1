param(
    [string]$MsixPath = "",
    [string]$CertificatePath = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([string]::IsNullOrWhiteSpace($MsixPath)) {
    $candidate = Get-ChildItem -Path $scriptDir -Filter "*-test-signed.msix" |
        Sort-Object Name |
        Select-Object -First 1
    if (-not $candidate) {
        throw "No *-test-signed.msix file was found next to this script."
    }
    $MsixPath = $candidate.FullName
}

if ([string]::IsNullOrWhiteSpace($CertificatePath)) {
    $CertificatePath = Join-Path $scriptDir "codex-usage-win-test.cer"
}

$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = [Security.Principal.WindowsPrincipal]::new($identity)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw "Run this script from an elevated PowerShell window (Run as administrator)."
}

if (-not (Test-Path -LiteralPath $MsixPath -PathType Leaf)) {
    throw "MSIX file not found: $MsixPath"
}
if (-not (Test-Path -LiteralPath $CertificatePath -PathType Leaf)) {
    throw "Test certificate not found: $CertificatePath"
}

$cert = Import-Certificate -FilePath $CertificatePath -CertStoreLocation "Cert:\LocalMachine\TrustedPeople"

Write-Host "Installed temporary test certificate: $($cert.Thumbprint)"
Add-AppxPackage -Path $MsixPath
Write-Host "Codex Usage Win test MSIX installed."
Write-Host "After testing, uninstall the app and remove the temporary certificate from Local Computer > Trusted People."
