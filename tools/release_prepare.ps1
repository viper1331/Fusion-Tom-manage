param(
  [string]$ManifestPath = "fusion.manifest.json",
  [string]$VersionPath = "fusion.version",
  [string]$ExpectedEntrypoint = "start.lua",
  [string]$Commit = "",
  [string]$Treeish = "INDEX"
)

$ErrorActionPreference = "Stop"

$generateScript = Join-Path $PSScriptRoot "generate_manifest.ps1"
$validateScript = Join-Path $PSScriptRoot "validate_distribution.ps1"

if (-not (Test-Path -LiteralPath $generateScript)) {
  throw "Missing generator script: $generateScript"
}
if (-not (Test-Path -LiteralPath $validateScript)) {
  throw "Missing validation script: $validateScript"
}

Write-Host "[release] step 1/2: generate manifest"
$generateArgs = @{
  ManifestPath = $ManifestPath
  VersionPath = $VersionPath
  Treeish = $Treeish
}
if (-not [string]::IsNullOrWhiteSpace($Commit)) {
  $generateArgs.Commit = $Commit
}
& $generateScript @generateArgs
if ($LASTEXITCODE -ne 0) {
  throw "Manifest generation failed"
}

Write-Host "[release] step 2/2: validate distribution"
& $validateScript -ManifestPath $ManifestPath -VersionPath $VersionPath -ExpectedEntrypoint $ExpectedEntrypoint
if ($LASTEXITCODE -ne 0) {
  throw "Distribution validation failed"
}

$version = (Get-Content -Raw -LiteralPath $VersionPath).Trim()
$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
$fileCount = @($manifest.files).Count

Write-Host ""
Write-Host "Release summary:"
Write-Host ("  version: " + $version)
Write-Host ("  entrypoint: " + [string]$manifest.entrypoint)
Write-Host ("  commit pin: " + [string]$manifest.commit)
Write-Host ("  files: " + $fileCount)
Write-Host ""
Write-Host "Release commit workflow reminder:"
Write-Host "  1) Commit fonctionnel (code/outillage/version)"
Write-Host "  2) Commit release (manifest pin synchronise)"
Write-Host "  3) Push origin/main"
