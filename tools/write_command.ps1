param(
  [Parameter(Mandatory = $true)]
  [ValidateSet("noop", "sync_only", "test_only", "sync_and_test")]
  [string]$Command,

  [string]$Computer = "fusion_terrain_01",
  [string]$ExpectedVersion = "",
  [string]$OutputRoot = "tools/terrain_bridge/data/commands"
)

$ErrorActionPreference = "Stop"

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
$target = Join-Path $resolvedRoot ($Computer + ".json")
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($target, ($payload | ConvertTo-Json -Depth 10) + [Environment]::NewLine, $utf8NoBom)

Write-Host ("command written: " + $target)
Write-Host ("  id: " + $id)
Write-Host ("  command: " + $Command)
if ($ExpectedVersion -ne "") {
  Write-Host ("  expectedVersion: " + $ExpectedVersion)
}
