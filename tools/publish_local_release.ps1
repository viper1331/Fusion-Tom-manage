param(
  [string]$PublishRoot = "tools/terrain_bridge/data/publish",
  [string]$ManifestPath = "fusion.manifest.json",
  [string]$VersionPath = "fusion.version"
)

$ErrorActionPreference = "Stop"

function Invoke-Git {
  param(
    [string[]]$GitArgs
  )

  $output = & git @GitArgs 2>&1
  if ($LASTEXITCODE -ne 0) {
    $details = if ($output) { ($output -join [Environment]::NewLine) } else { "no output" }
    throw "git $($GitArgs -join ' ') failed`n$details"
  }

  return @($output)
}

function Get-IndexBlobSha {
  param(
    [string]$Path
  )

  $stageLines = @(Invoke-Git -GitArgs @("ls-files", "--stage", "--", $Path))
  if ($stageLines.Count -lt 1) {
    throw "Path not found in git index: $Path"
  }

  $stageLine = $stageLines[0].ToString().Trim()
  if ($stageLine -notmatch "^[0-9]+\s+([0-9a-f]{40})\s+[0-9]+\t") {
    throw "Cannot parse staged blob for ${Path}: $stageLine"
  }

  return $matches[1].ToLowerInvariant()
}

function Export-BlobToPath {
  param(
    [string]$BlobSha,
    [string]$Destination
  )

  if ($BlobSha -notmatch "^[0-9a-f]{40}$") {
    throw "Invalid blob SHA: $BlobSha"
  }

  $destinationDir = Split-Path -Parent $Destination
  if ($destinationDir -and -not (Test-Path -LiteralPath $destinationDir)) {
    New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
  }

  $tmp = [System.IO.Path]::GetTempFileName()
  try {
    $command = "git cat-file blob $BlobSha > `"$tmp`""
    & cmd /c $command | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to export git blob $BlobSha"
    }

    [System.IO.File]::Copy($tmp, $Destination, $true)
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Resolve-HashAlgorithm {
  param(
    [string]$HashAlgo
  )

  $algo = ([string]$HashAlgo).Trim().ToLowerInvariant()
  switch ($algo) {
    "sha256" { return "SHA256" }
    default {
      throw "Unsupported hash algorithm in manifest: $HashAlgo"
    }
  }
}

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

  $destination = Join-Path $resolvedPublishRoot $path
  $blobSha = Get-IndexBlobSha -Path $path
  Export-BlobToPath -BlobSha $blobSha -Destination $destination
}

$manifestTarget = Join-Path $resolvedPublishRoot "fusion.manifest.json"
$manifestBlob = Get-IndexBlobSha -Path $ManifestPath
Export-BlobToPath -BlobSha $manifestBlob -Destination $manifestTarget

$versionTarget = Join-Path $resolvedPublishRoot "fusion.version"
$versionBlob = Get-IndexBlobSha -Path $VersionPath
Export-BlobToPath -BlobSha $versionBlob -Destination $versionTarget

$mismatches = New-Object System.Collections.Generic.List[string]
foreach ($entry in @($manifest.files)) {
  $path = [string]$entry.path
  if ([string]::IsNullOrWhiteSpace($path)) {
    continue
  }

  $publishedFile = Join-Path $resolvedPublishRoot $path
  if (-not (Test-Path -LiteralPath $publishedFile)) {
    $mismatches.Add("missing published file: $path")
    continue
  }

  if ($entry.PSObject.Properties.Name -contains "size" -and $null -ne $entry.size) {
    $expectedSize = [int64]$entry.size
    $actualSize = (Get-Item -LiteralPath $publishedFile).Length
    if ($actualSize -ne $expectedSize) {
      $mismatches.Add("size mismatch $path expected=$expectedSize actual=$actualSize")
    }
  }

  if ($entry.PSObject.Properties.Name -contains "hash" -and -not [string]::IsNullOrWhiteSpace([string]$entry.hash)) {
    $algo = Resolve-HashAlgorithm -HashAlgo ([string]$entry.hashAlgo)
    $expectedHash = ([string]$entry.hash).Trim().ToLowerInvariant()
    $actualHash = (Get-FileHash -LiteralPath $publishedFile -Algorithm $algo).Hash.ToLowerInvariant()
    if ($actualHash -ne $expectedHash) {
      $mismatches.Add("hash mismatch $path expected=$expectedHash actual=$actualHash")
    }
  }
}

if ($mismatches.Count -gt 0) {
  throw "Publish verification failed:`n - " + ($mismatches -join "`n - ")
}

Write-Host "Local release published."
Write-Host ("  version: " + ((Get-Content -Raw -LiteralPath $VersionPath).Trim()))
Write-Host ("  publish root: " + $resolvedPublishRoot)
Write-Host ("  file count: " + @($manifest.files).Count)
