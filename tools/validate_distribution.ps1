param(
  [string]$ManifestPath = "fusion.manifest.json",
  [string]$VersionPath = "fusion.version"
)

$ErrorActionPreference = "Stop"

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

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

if (-not (Test-Path -LiteralPath $VersionPath)) {
  $errors.Add("version file missing: $VersionPath")
}

if (-not (Test-Path -LiteralPath $ManifestPath)) {
  $errors.Add("manifest missing: $ManifestPath")
}

$versionText = ""
if ($errors.Count -eq 0) {
  $versionText = (Get-Content -Raw -LiteralPath $VersionPath).Trim()
  if ([string]::IsNullOrWhiteSpace($versionText)) {
    $errors.Add("version file is empty: $VersionPath")
  }
}

$manifest = $null
if ($errors.Count -eq 0) {
  try {
    $manifest = Get-Content -Raw -LiteralPath $ManifestPath | ConvertFrom-Json
  } catch {
    $errors.Add("manifest JSON invalid: $ManifestPath")
  }
}

if ($null -ne $manifest) {
  if ([string]::IsNullOrWhiteSpace([string]$manifest.version)) {
    $errors.Add("manifest.version missing")
  } elseif ($versionText -ne "" -and [string]$manifest.version -ne $versionText) {
    $errors.Add("version mismatch: fusion.version=$versionText manifest.version=$($manifest.version)")
  }

  $entrypoint = Normalize-ManifestPath -Path ([string]$manifest.entrypoint)
  if ($entrypoint -eq "") {
    $errors.Add("manifest.entrypoint missing")
  } elseif (-not (Test-Path -LiteralPath $entrypoint)) {
    $errors.Add("manifest entrypoint missing on disk: $entrypoint")
  }

  if ($manifest.PSObject.Properties.Name -notcontains "files" -or $null -eq $manifest.files) {
    $errors.Add("manifest.files missing")
  } else {
    $seen = @{}
    $filePaths = New-Object System.Collections.Generic.List[string]

    foreach ($entry in @($manifest.files)) {
      $rawPath = $null
      if ($entry -is [string]) {
        $rawPath = [string]$entry
      } elseif ($entry -and $entry.PSObject.Properties.Name -contains "path") {
        $rawPath = [string]$entry.path
      } else {
        $errors.Add("invalid manifest file entry format")
        continue
      }

      $path = Normalize-ManifestPath -Path $rawPath
      if ($path -eq "") {
        $errors.Add("manifest contains empty file path")
        continue
      }

      if ($seen.ContainsKey($path)) {
        $errors.Add("duplicate manifest file path: $path")
      } else {
        $seen[$path] = $true
      }

      $filePaths.Add($path)

      if (-not (Test-Path -LiteralPath $path)) {
        $errors.Add("manifest file missing on disk: $path")
      }
    }

    if ($entrypoint -ne "" -and -not $filePaths.Contains($entrypoint)) {
      $errors.Add("entrypoint not listed in manifest.files: $entrypoint")
    }
  }
}

if ($warnings.Count -gt 0) {
  Write-Host "Warnings:"
  foreach ($line in $warnings) {
    Write-Host ("  - " + $line)
  }
}

if ($errors.Count -gt 0) {
  Write-Host "Validation FAILED:"
  foreach ($line in $errors) {
    Write-Host ("  - " + $line)
  }
  exit 1
}

Write-Host "Validation OK"
Write-Host ("  version: " + $versionText)
if ($null -ne $manifest) {
  Write-Host ("  manifest: " + $ManifestPath)
  Write-Host ("  entrypoint: " + [string]$manifest.entrypoint)
  Write-Host ("  files: " + @($manifest.files).Count)
}
