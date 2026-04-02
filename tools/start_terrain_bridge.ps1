param(
  [string]$Python = "python",
  [string]$Host = "127.0.0.1",
  [int]$Port = 8765
)

$ErrorActionPreference = "Stop"

$scriptPath = Join-Path $PSScriptRoot "terrain_bridge/server.py"
if (-not (Test-Path -LiteralPath $scriptPath)) {
  throw "Missing bridge server: $scriptPath"
}

$env:TERRAIN_BRIDGE_HOST = $Host
$env:TERRAIN_BRIDGE_PORT = [string]$Port

Write-Host ("Starting terrain bridge on http://{0}:{1}" -f $Host, $Port)
& $Python $scriptPath
