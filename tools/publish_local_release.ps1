param(
  [string]$PublishRoot = "tools/terrain_bridge/data/publish",
  [string]$ManifestPath = "fusion.manifest.json",
  [string]$VersionPath = "fusion.version"
)

$ErrorActionPreference = "Stop"

$releasePrepare = Join-Path $PSScriptRoot "release_prepare.ps1"
if (-not (Test-Path -LiteralPath $releasePrepare)) {
  throw "Missing release_prepare.ps1"
}

& $releasePrepare -ManifestPath $ManifestPath -VersionPath $VersionPath
if ($LASTEXITCODE -ne 0) {
  throw "release_prepare failed"
}

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
if (-not (Test-Path -LiteralPath $PublishRoot)) {
  New-Item -ItemType Directory -Path $PublishRoot -Force | Out-Null
}

$resolvedPublishRoot = (Resolve-Path -LiteralPath $PublishRoot).Path

foreach ($entry in @($manifest.files)) {
  $path = [string]$entry.path
  if ([string]::IsNullOrWhiteSpace($path)) {
    continue
  }

  $source = Join-Path (Get-Location) $path
  if (-not (Test-Path -LiteralPath $source)) {
    throw "Missing source file for publish: $path"
  }

  $destination = Join-Path $resolvedPublishRoot $path
  $destinationDir = Split-Path -Parent $destination
  if ($destinationDir -and -not (Test-Path -LiteralPath $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  }

  Copy-Item -LiteralPath $source -Destination $destination -Force
}

Copy-Item -LiteralPath $ManifestPath -Destination (Join-Path $resolvedPublishRoot "fusion.manifest.json") -Force
Copy-Item -LiteralPath $VersionPath -Destination (Join-Path $resolvedPublishRoot "fusion.version") -Force

Write-Host "Local release published."
Write-Host ("  version: " + ((Get-Content -Raw -LiteralPath $VersionPath).Trim()))
Write-Host ("  publish root: " + $resolvedPublishRoot)
Write-Host ("  file count: " + @($manifest.files).Count)
