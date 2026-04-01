param(
  [string]$ManifestPath = "fusion.manifest.json",
  [string]$VersionPath = "fusion.version",
  [string]$ExpectedEntrypoint = "start.lua"
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

function Is-ValidCommitSha {
  param([string]$Value)
  return -not [string]::IsNullOrWhiteSpace($Value) -and ($Value -match '^[0-9a-f]{40}$')
}

$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

$expectedEntrypointPath = Normalize-ManifestPath -Path $ExpectedEntrypoint
if ([string]::IsNullOrWhiteSpace($expectedEntrypointPath)) {
  $errors.Add("expected entrypoint is empty")
}

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

  if ($manifest.PSObject.Properties.Name -notcontains "commit" -or -not (Is-ValidCommitSha -Value ([string]$manifest.commit)) ) {
    $errors.Add("manifest.commit missing or invalid (expected 40-char lowercase SHA)")
  }

  if ($manifest.PSObject.Properties.Name -notcontains "source" -or $null -eq $manifest.source) {
    $errors.Add("manifest.source missing")
  } elseif ($manifest.source.PSObject.Properties.Name -notcontains "commit" -or -not (Is-ValidCommitSha -Value ([string]$manifest.source.commit))) {
    $errors.Add("manifest.source.commit missing or invalid (expected 40-char lowercase SHA)")
  } elseif ([string]$manifest.source.commit -ne [string]$manifest.commit) {
    $errors.Add("commit mismatch: manifest.commit=$($manifest.commit) source.commit=$($manifest.source.commit)")
  }

  $entrypoint = Normalize-ManifestPath -Path ([string]$manifest.entrypoint)
  if ($entrypoint -eq "") {
    $errors.Add("manifest.entrypoint missing")
  } else {
    if ($entrypoint -ne $expectedEntrypointPath) {
      $errors.Add("manifest.entrypoint mismatch: expected=$expectedEntrypointPath actual=$entrypoint")
    }
    if (-not (Test-Path -LiteralPath $entrypoint)) {
      $errors.Add("manifest entrypoint missing on disk: $entrypoint")
    }
  }

  if (-not (Test-Path -LiteralPath $expectedEntrypointPath)) {
    $errors.Add("expected entrypoint missing on disk: $expectedEntrypointPath")
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

    if (-not $filePaths.Contains($expectedEntrypointPath)) {
      $errors.Add("expected entrypoint not listed in manifest.files: $expectedEntrypointPath")
    }

    $legacyShimPath = "start_menu_pages_live_v7.lua"
    if ((Test-Path -LiteralPath $legacyShimPath) -and (-not $filePaths.Contains($legacyShimPath))) {
      $errors.Add("legacy shim missing in manifest.files: $legacyShimPath")
    }

    $rescuePath = "rescue_update.lua"
    if ((Test-Path -LiteralPath $rescuePath) -and (-not $filePaths.Contains($rescuePath))) {
      $errors.Add("rescue mode missing in manifest.files: $rescuePath")
    }

    $criticalOverviewFiles = @(
      "ui/pages/overview_page.lua",
      "ui/pages/overview_graphics.lua",
      "ui/animations/electric_flow.lua",
      "ui/animations/reactor_core.lua",
      "ui/helpers/gpu_safe.lua",
      "ui/helpers/callout_renderer.lua"
    )

    foreach ($criticalPath in $criticalOverviewFiles) {
      if (-not (Test-Path -LiteralPath $criticalPath)) {
        $errors.Add("critical overview file missing on disk: $criticalPath")
        continue
      }
      if (-not $filePaths.Contains($criticalPath)) {
        $errors.Add("critical overview file missing in manifest.files: $criticalPath")
      }
    }

    if ($manifest.PSObject.Properties.Name -notcontains "project" -or [string]::IsNullOrWhiteSpace([string]$manifest.project)) {
      $warnings.Add("manifest.project missing (recommended for release metadata)")
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
  Write-Host ("  commit: " + [string]$manifest.commit)
  Write-Host ("  files: " + @($manifest.files).Count)
}
