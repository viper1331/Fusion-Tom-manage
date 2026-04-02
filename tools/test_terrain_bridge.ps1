param(
  [string]$BridgeBaseUrl = "http://127.0.0.1:8765",
  [string]$Computer = "bridge_self_test_node",
  [string]$DataRoot = "tools/terrain_bridge/data"
)

$ErrorActionPreference = "Stop"

function Ensure-JsonResponse {
  param(
    [string]$Url
  )
  $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 5
  if ($response.StatusCode -ne 200) {
    throw "HTTP $($response.StatusCode) on $Url"
  }
  return ($response.Content | ConvertFrom-Json)
}

$health = Ensure-JsonResponse -Url ($BridgeBaseUrl.TrimEnd("/") + "/health")
if (-not $health.ok) {
  throw "Bridge health endpoint returned ok=false"
}

$commandPayload = Ensure-JsonResponse -Url ($BridgeBaseUrl.TrimEnd("/") + "/command?computer=" + [uri]::EscapeDataString($Computer))
if ($null -eq $commandPayload) {
  throw "Bridge command endpoint returned empty payload"
}
$activityBefore = Ensure-JsonResponse -Url ($BridgeBaseUrl.TrimEnd("/") + "/activity")

$id = [guid]::NewGuid().ToString("N")
$resultPayload = @{
  id = $id
  command = "bridge_self_test"
  ok = $true
  detail = "result endpoint self-test"
  computerName = $Computer
  sentAt = (Get-Date).ToString("s")
}
$reportPayload = @{
  label = "bridge_self_test"
  suite = "bridge"
  project = "Fusion-Tom-manage"
  computerName = $Computer
  sentAt = (Get-Date).ToString("s")
  results = @(
    @{
      ok = $true
      name = "bridge"
      message = "self-test"
    }
  )
}

Invoke-RestMethod -Uri ($BridgeBaseUrl.TrimEnd("/") + "/result") -Method Post -ContentType "application/json" -Body ($resultPayload | ConvertTo-Json -Depth 10) | Out-Null
Invoke-RestMethod -Uri ($BridgeBaseUrl.TrimEnd("/") + "/report") -Method Post -ContentType "application/json" -Body ($reportPayload | ConvertTo-Json -Depth 10) | Out-Null

$resultsDir = Join-Path $DataRoot "results"
$reportsDir = Join-Path $DataRoot "reports"
$resultFile = Get-ChildItem -LiteralPath $resultsDir -File -Filter ("*-" + $id + ".json") -ErrorAction SilentlyContinue | Select-Object -First 1
$reportFile = Get-ChildItem -LiteralPath $reportsDir -File -Filter ($Computer + "-bridge_self_test-*.json") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if (-not $resultFile) {
  throw "Bridge result endpoint did not persist expected file for id $id"
}
if (-not $reportFile) {
  throw "Bridge report endpoint did not persist expected report file"
}

$activityAfter = Ensure-JsonResponse -Url ($BridgeBaseUrl.TrimEnd("/") + "/activity")
if ($null -eq $activityAfter.lastResult -or [string]::IsNullOrWhiteSpace([string]$activityAfter.lastResult.computer)) {
  throw "Bridge activity endpoint missing lastResult after self-test"
}
if ($null -eq $activityAfter.lastReport -or [string]::IsNullOrWhiteSpace([string]$activityAfter.lastReport.computer)) {
  throw "Bridge activity endpoint missing lastReport after self-test"
}

Write-Host "Terrain bridge self-test OK"
Write-Host ("  health: " + $health.status)
Write-Host ("  command endpoint id: " + [string]$commandPayload.id)
Write-Host ("  activity poll computer: " + [string]$activityAfter.lastCommandPoll.computer)
Write-Host ("  result file: " + $resultFile.FullName)
Write-Host ("  report file: " + $reportFile.FullName)
