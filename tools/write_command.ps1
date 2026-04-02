param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("noop", "sync_only", "test_only", "sync_and_test")]
  [string]$Command,

  [string]$Computer = "",
  [string]$ExpectedVersion = "",
  [string]$OutputRoot = "tools/terrain_bridge/data/commands",
  [string]$FusionConfigPath = "fusion_config.lua"
)

$ErrorActionPreference = "Stop"

function Resolve-ComputerName {
  param(
    [string]$ComputerName,
    [string]$ConfigPath
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

  return [pscustomobject]@{
    Name = "fusion_terrain_01"
    Source = "default"
  }
}

$computerResolution = Resolve-ComputerName -ComputerName $Computer -ConfigPath $FusionConfigPath
$resolvedComputer = [string]$computerResolution.Name

if (-not (Test-Path -LiteralPath $OutputRoot)) {
  New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

$id = [guid]::NewGuid().ToString("N")
$payload = [pscustomobject]@{
  id = $id
  command = $Command
  expectedVersion = $ExpectedVersion
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
if ($ExpectedVersion -ne "") {
  Write-Host ("  expectedVersion: " + $ExpectedVersion)
}
