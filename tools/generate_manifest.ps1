param(
  [string]$ManifestPath = "fusion.manifest.json",
  [string]$VersionPath = "fusion.version",
  [string]$Commit = "",
  [string]$Treeish = "INDEX"
)

$ErrorActionPreference = "Stop"

function Get-GitOutput {
  param([string[]]$GitArgs)
  $output = & git @GitArgs
  if ($LASTEXITCODE -ne 0) {
    throw "git $($GitArgs -join ' ') failed"
  }
  return ($output | Select-Object -Last 1).Trim()
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}

if ([string]::IsNullOrWhiteSpace($Commit)) {
  $Commit = Get-GitOutput -GitArgs @("rev-parse", "HEAD")
}

$Commit = $Commit.Trim().ToLowerInvariant()
if ($Commit -notmatch "^[0-9a-f]{40}$") {
  throw "Invalid commit SHA: $Commit"
}

if ([string]::IsNullOrWhiteSpace($Treeish)) {
  $Treeish = "INDEX"
}

$treeishMode = $Treeish.Trim().ToUpperInvariant()
if ($treeishMode -ne "INDEX") {
  $Treeish = $Treeish.Trim()
}

$manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json

if (Test-Path -LiteralPath $VersionPath) {
  $version = (Get-Content -Raw -LiteralPath $VersionPath).Trim()
  if (-not [string]::IsNullOrWhiteSpace($version)) {
    $manifest.version = $version
  }
}

if ($manifest.PSObject.Properties.Name -notcontains "source" -or $null -eq $manifest.source) {
  $manifest | Add-Member -NotePropertyName source -NotePropertyValue ([pscustomobject]@{})
}
if ($manifest.source.PSObject.Properties.Name -contains "commit") {
  $manifest.source.commit = $Commit
} else {
  $manifest.source | Add-Member -NotePropertyName commit -NotePropertyValue $Commit
}

if ($manifest.PSObject.Properties.Name -contains "commit") {
  $manifest.commit = $Commit
} else {
  $manifest | Add-Member -NotePropertyName commit -NotePropertyValue $Commit
}

foreach ($entry in $manifest.files) {
  if ($null -eq $entry.size) {
    continue
  }

  $path = [string]$entry.path
  if ([string]::IsNullOrWhiteSpace($path)) {
    throw "Manifest entry with size has empty path"
  }
  if ($path.Trim() -ne $path) {
    throw "Manifest path has leading/trailing spaces: '$path'"
  }

  $normalizedPath = $path -replace '\\', '/'
  if ($normalizedPath -ne $path) {
    $entry.path = $normalizedPath
    $path = $normalizedPath
  }

  if ($path -match "\s") {
    Write-Host "warning: manifest path contains spaces (URL encoding required): $path"
  }

  $sizeText = $null
  if ($treeishMode -eq "INDEX") {
    $stageLine = Get-GitOutput -GitArgs @("ls-files", "--stage", "--", $path)
    if ($stageLine -notmatch "^[0-9]+\s+([0-9a-f]{40})\s+[0-9]+\t") {
      throw "Cannot parse staged blob for ${path}: $stageLine"
    }
    $blobSha = $matches[1]
    $sizeText = Get-GitOutput -GitArgs @("cat-file", "-s", $blobSha)
  } else {
    $blobQuery = "$Treeish`:$path"
    $sizeText = Get-GitOutput -GitArgs @("cat-file", "-s", $blobQuery)
  }

  if ($sizeText -notmatch "^[0-9]+$") {
    throw "Invalid blob size for ${path}: $sizeText"
  }

  $entry.size = [int64]$sizeText
}

$json = $manifest | ConvertTo-Json -Depth 30
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $ManifestPath), $json + [Environment]::NewLine, $utf8NoBom)

Write-Host "Manifest updated:"
Write-Host "  path:    $ManifestPath"
Write-Host "  version: $($manifest.version)"
Write-Host "  commit:  $Commit"
Write-Host "  treeish: $Treeish"
