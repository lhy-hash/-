param(
  [string]$DeviceId = "c04a9c3a"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$secretsPath = Join-Path $root ".llm_secrets"
$defines = @()

if (Test-Path $secretsPath) {
  Get-Content $secretsPath | ForEach-Object {
    $line = $_.Trim()
    if ($line -eq "" -or $line.StartsWith("#")) { return }
    $parts = $line.Split("=", 2)
    if ($parts.Length -ne 2) { return }
    $key = $parts[0].Trim()
    $val = $parts[1].Trim()
    if ($val -ne "") {
      $defines += "--dart-define=$key=$val"
    }
  }
}

Write-Host "Installing to device: $DeviceId"
Write-Host "Dart defines count: $($defines.Count)"

$args = @("run", "-d", $DeviceId, "--release") + $defines
& flutter @args
