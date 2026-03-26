param(
  [string]$ManifestPath = "fusion.manifest.json",
  [string]$VersionPath = "fusion.version",
  [string]$Commit = "",
  [string]$Treeish = "INDEX",
  [switch]$KeepManifestFileEntry
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
  param(
    [string[]]$GitArgs,
    [switch]$AllowMultiLine
  )

  $output = & git @GitArgs 2>&1
  if ($LASTEXITCODE -ne 0) {
    $details = if ($output) { ($output -join [Environment]::NewLine) } else { "no output" }
    throw "git $($GitArgs -join ' ') failed`n$details"
  }

  if ($AllowMultiLine) {
    return $output
  }

  return ($output | Select-Object -Last 1).ToString().Trim()
}

function Normalize-ManifestPath {
  param([string]$Path)

  if ([string]::IsNullOrWhiteSpace($Path)) {
    return ""
  }

  $normalized = $Path.Trim() -replace '\\', '/'
  while ($normalized.StartsWith("./")) {
    $normalized = $normalized.Substring(2)
  }
  while ($normalized.StartsWith("/")) {
    $normalized = $normalized.Substring(1)
  }
  return $normalized
}

function Export-BlobToTempFile {
  param([string]$BlobSha)

  if ($BlobSha -notmatch "^[0-9a-f]{40}$") {
    throw "Invalid blob SHA: $BlobSha"
  }

  $tmpFile = [System.IO.Path]::GetTempFileName()
  $command = "git cat-file blob $BlobSha > `"$tmpFile`""
  & cmd /c $command | Out-Null
  if ($LASTEXITCODE -ne 0) {
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
    throw "Failed to export git blob $BlobSha"
  }

  return $tmpFile
}

function Get-BlobShaForPath {
  param(
    [string]$Path,
    [bool]$UseIndex,
    [string]$ResolvedTreeish
  )

  if ($UseIndex) {
    $stageLines = @(Invoke-Git -GitArgs @("ls-files", "--stage", "--", $Path) -AllowMultiLine)
    if ($stageLines.Count -lt 1) {
      throw "Path not found in git index: $Path"
    }

    $stageLine = $stageLines[0].ToString().Trim()
    if ($stageLine -notmatch "^[0-9]+\s+([0-9a-f]{40})\s+[0-9]+\t") {
      throw "Cannot parse staged blob for ${Path}: $stageLine"
    }
    return $matches[1].ToLowerInvariant()
  }

  $blobSha = Invoke-Git -GitArgs @("rev-parse", "$ResolvedTreeish`:$Path")
  $blobSha = $blobSha.Trim().ToLowerInvariant()
  if ($blobSha -notmatch "^[0-9a-f]{40}$") {
    throw "Cannot resolve blob SHA for ${Path} at ${ResolvedTreeish}: $blobSha"
  }
  return $blobSha
}

function Get-BlobMetadata {
  param([string]$BlobSha)

  $sizeText = Invoke-Git -GitArgs @("cat-file", "-s", $BlobSha)
  if ($sizeText -notmatch "^[0-9]+$") {
    throw "Invalid blob size for ${BlobSha}: $sizeText"
  }

  $tmpFile = Export-BlobToTempFile -BlobSha $BlobSha
  try {
    $hash = (Get-FileHash -LiteralPath $tmpFile -Algorithm SHA256).Hash.ToLowerInvariant()
  } finally {
    Remove-Item -LiteralPath $tmpFile -Force -ErrorAction SilentlyContinue
  }

  return [pscustomobject]@{
    size = [int64]$sizeText
    hash = $hash
  }
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  throw "Manifest not found: $ManifestPath"
}

if ([string]::IsNullOrWhiteSpace($Commit)) {
  $Commit = Invoke-Git -GitArgs @("rev-parse", "HEAD")
}
$Commit = $Commit.Trim().ToLowerInvariant()
if ($Commit -notmatch "^[0-9a-f]{40}$") {
  throw "Invalid commit SHA: $Commit"
}

$resolvedTreeish = if ([string]::IsNullOrWhiteSpace($Treeish)) { "INDEX" } else { $Treeish.Trim() }
$useIndex = $resolvedTreeish.ToUpperInvariant() -eq "INDEX"

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

if ($manifest.PSObject.Properties.Name -notcontains "integrity" -or $null -eq $manifest.integrity) {
  $manifest | Add-Member -NotePropertyName integrity -NotePropertyValue ([pscustomobject]@{})
}

$manifest.integrity.mode = "hash+size"
$manifest.integrity.hashPlanned = $false
$manifest.integrity.hashRequired = $true
$manifest.integrity.defaultHashAlgo = "sha256"
$manifest.integrity.hashAlgorithms = @("sha256")

if ($manifest.PSObject.Properties.Name -notcontains "files" -or $null -eq $manifest.files) {
  throw "Manifest files list missing"
}

$normalizedManifestPath = Normalize-ManifestPath -Path $ManifestPath
$newFiles = New-Object System.Collections.Generic.List[object]
$seen = @{}

foreach ($entry in @($manifest.files)) {
  $rawPath = $null
  if ($entry -is [string]) {
    $rawPath = [string]$entry
  } elseif ($entry -ne $null -and $entry.PSObject.Properties.Name -contains "path") {
    $rawPath = [string]$entry.path
  } else {
    throw "Invalid manifest file entry: $entry"
  }

  $path = Normalize-ManifestPath -Path $rawPath
  if ([string]::IsNullOrWhiteSpace($path)) {
    throw "Manifest file entry has empty path"
  }

  if ($path -eq $normalizedManifestPath -and -not $KeepManifestFileEntry.IsPresent) {
    Write-Host "info: skipping self-referential manifest entry: $path"
    continue
  }

  if ($seen.ContainsKey($path)) {
    throw "Duplicate path in manifest files: $path"
  }
  $seen[$path] = $true

  if ($path -match "\s") {
    Write-Host "warning: manifest path contains spaces (URL encoding required): $path"
  }

  $blobSha = Get-BlobShaForPath -Path $path -UseIndex $useIndex -ResolvedTreeish $resolvedTreeish
  $metadata = Get-BlobMetadata -BlobSha $blobSha

  $newFiles.Add([pscustomobject]@{
      path = $path
      size = $metadata.size
      hash = $metadata.hash
      hashAlgo = "sha256"
    })
}

if ($newFiles.Count -lt 1) {
  throw "Manifest files list is empty after normalization"
}

$manifest.files = $newFiles

$json = $manifest | ConvertTo-Json -Depth 40
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText((Resolve-Path -LiteralPath $ManifestPath), $json + [Environment]::NewLine, $utf8NoBom)

Write-Host "Manifest updated:"
Write-Host "  path:    $ManifestPath"
Write-Host "  version: $($manifest.version)"
Write-Host "  commit:  $Commit"
Write-Host "  treeish: $resolvedTreeish"
Write-Host "  files:   $($newFiles.Count)"
