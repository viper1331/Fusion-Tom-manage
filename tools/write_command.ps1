param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("noop", "sync_only", "test_only", "sync_and_test")]
  [string]$Command,

  [string]$Computer = "",
  [string]$ExpectedVersion = "",
  [string]$OutputRoot = "tools/terrain_bridge/data/commands",
  [string]$FusionConfigPath = "fusion_config.lua",
  [string]$BridgeActivityPath = "tools/terrain_bridge/data/activity.json"
)

$ErrorActionPreference = "Stop"
$AllowedTargetNames = @("fusion_test_01", "fusion_primary_01")

function Test-UsableComputerName {
  param(
    [string]$Name
  )

  $value = [string]$Name
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $false
  }

  $trimmed = $value.Trim().ToLowerInvariant()
  if ($trimmed -eq "unknown") {
    return $false
  }

  if ($trimmed.StartsWith("bridge_self_test")) {
    return $false
  }

  if ($trimmed.StartsWith("ack_probe")) {
    return $false
  }

  if ($trimmed.StartsWith("fusion_terrain_") -or ($trimmed -match '^computer_\d+$')) {
    return $false
  }

  return $true
}

function Assert-AllowedTarget {
  param(
    [string]$ComputerName
  )

  $name = ([string]$ComputerName).Trim()
  if ([string]::IsNullOrWhiteSpace($name)) {
    throw "target computer name is empty"
  }

  if ($AllowedTargetNames -notcontains $name) {
    throw ("target computer '" + $name + "' is not allowed. Allowed values: " + ($AllowedTargetNames -join ", "))
  }
}

function Resolve-ComputerFromBridgeActivity {
  param(
    [string]$ActivityPath
  )

  if (-not (Test-Path -LiteralPath $ActivityPath)) {
    return $null
  }

  try {
    $json = Get-Content -Raw -LiteralPath $ActivityPath | ConvertFrom-Json
    if ($null -ne $json -and $null -ne $json.lastCommandPoll) {
      $candidate = [string]$json.lastCommandPoll.computer
      if (Test-UsableComputerName -Name $candidate) {
        return [pscustomobject]@{
          Name = $candidate.Trim()
          Source = "bridge_activity"
        }
      }
    }
  } catch {
    # Fallback handled by caller.
  }

  return $null
}

function Resolve-ComputerName {
  param(
    [string]$ComputerName,
    [string]$ConfigPath,
    [string]$ActivityPath
  )

  if (-not [string]::IsNullOrWhiteSpace($ComputerName)) {
    return [pscustomobject]@{
      Name = $ComputerName.Trim()
      Source = "argument"
    }
  }

  if (Test-Path -LiteralPath $ConfigPath) {
    try {
      $content = Get-Content -Raw -LiteralPath $ConfigPath
      $agentBlock = [regex]::Match($content, 'terrainAgent\s*=\s*{(?<block>.*?)}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
      if ($agentBlock.Success) {
        $testNameMatch = [regex]::Match($agentBlock.Groups["block"].Value, 'testComputerName\s*=\s*"(?<name>[^"]*)"')
        if ($testNameMatch.Success) {
          $resolvedTest = $testNameMatch.Groups["name"].Value.Trim()
          if (-not [string]::IsNullOrWhiteSpace($resolvedTest)) {
            return [pscustomobject]@{
              Name = $resolvedTest
              Source = "fusion_config.testComputerName"
            }
          }
        }
        $nameMatch = [regex]::Match($agentBlock.Groups["block"].Value, 'computerName\s*=\s*"(?<name>[^"]*)"')
        if ($nameMatch.Success) {
          $resolved = $nameMatch.Groups["name"].Value.Trim()
          if (-not [string]::IsNullOrWhiteSpace($resolved)) {
            return [pscustomobject]@{
              Name = $resolved
              Source = "fusion_config"
            }
          }
        }
      }
    } catch {
      # Fallback handled below.
    }
  }

  $bridgeResolved = Resolve-ComputerFromBridgeActivity -ActivityPath $ActivityPath
  if ($null -ne $bridgeResolved -and -not [string]::IsNullOrWhiteSpace([string]$bridgeResolved.Name)) {
    return $bridgeResolved
  }

  return [pscustomobject]@{
    Name = "fusion_test_01"
    Source = "default"
  }
}

function Resolve-ExpectedVersion {
  param(
    [string]$VersionValue,
    [string]$VersionPath
  )

  if (-not [string]::IsNullOrWhiteSpace($VersionValue)) {
    return [pscustomobject]@{
      Value = $VersionValue.Trim()
      Source = "argument"
    }
  }

  if (Test-Path -LiteralPath $VersionPath) {
    try {
      $raw = (Get-Content -Raw -LiteralPath $VersionPath).Trim()
      if (-not [string]::IsNullOrWhiteSpace($raw)) {
        return [pscustomobject]@{
          Value = $raw
          Source = "fusion.version"
        }
      }
    } catch {
      # fallback below
    }
  }

  return [pscustomobject]@{
    Value = ""
    Source = "empty"
  }
}

$computerResolution = Resolve-ComputerName -ComputerName $Computer -ConfigPath $FusionConfigPath -ActivityPath $BridgeActivityPath
$resolvedComputer = [string]$computerResolution.Name
Assert-AllowedTarget -ComputerName $resolvedComputer
$expectedVersionResolution = Resolve-ExpectedVersion -VersionValue $ExpectedVersion -VersionPath "fusion.version"
$resolvedExpectedVersion = [string]$expectedVersionResolution.Value

if (-not (Test-Path -LiteralPath $OutputRoot)) {
  New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

$id = [guid]::NewGuid().ToString("N")
$payload = [pscustomobject]@{
  id = $id
  command = $Command
  expectedVersion = $resolvedExpectedVersion
  createdAt = (Get-Date).ToString("s")
}

$resolvedRoot = (Resolve-Path -LiteralPath $OutputRoot).Path
$target = Join-Path $resolvedRoot ($resolvedComputer + ".json")
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target, ($payload | ConvertTo-Json -Depth 10) + [Environment]::NewLine, $utf8NoBom)

Write-Host ("command written: " + $target)
Write-Host ("  id: " + $id)
Write-Host ("  command: " + $Command)
Write-Host ("  computer: " + $resolvedComputer + " (source=" + [string]$computerResolution.Source + ")")
if ($resolvedExpectedVersion -ne "") {
  Write-Host ("  expectedVersion: " + $resolvedExpectedVersion + " (source=" + [string]$expectedVersionResolution.Source + ")")
}
