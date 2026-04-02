param(
  [ValidateSet("sync_and_test", "sync_only", "test_only")]
  [string]$Command = "sync_and_test",
  [string]$BridgeBaseUrl = "http://127.0.0.1:8765",
  [string]$Computer = "",
  [string]$ExpectedVersion = "",
  [string]$FusionConfigPath = "fusion_config.lua",
  [string]$WriteCommandPath = "tools/write_command.ps1",
  [string]$DataRoot = "tools/terrain_bridge/data",
  [string]$SessionId = "",
  [int]$TimeoutSeconds = 300,
  [int]$PollSeconds = 2,
  [switch]$SkipPurge,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$AllowedTestComputer = "fusion_test_01"

function Normalize-Text {
  param([string]$Value)
  if ($null -eq $Value) {
    return ""
  }
  return $Value.Trim()
}

function Read-TerrainAgentConfigBlock {
  param([string]$ConfigPath)
  if (-not (Test-Path -LiteralPath $ConfigPath)) {
    return [pscustomobject]@{}
  }

  $content = Get-Content -Raw -LiteralPath $ConfigPath
  $match = [regex]::Match(
    $content,
    'terrainAgent\s*=\s*{(?<block>.*?)}',
    [System.Text.RegularExpressions.RegexOptions]::Singleline
  )
  if (-not $match.Success) {
    return [pscustomobject]@{}
  }

  $block = $match.Groups["block"].Value

  function Read-FieldValue {
    param([string]$Name)
    $fieldMatch = [regex]::Match($block, $Name + '\s*=\s*"(?<value>[^"]*)"')
    if ($fieldMatch.Success) {
      return [string]$fieldMatch.Groups["value"].Value
    }
    return ""
  }

  return [pscustomobject]@{
    computerName = Read-FieldValue -Name "computerName"
    testComputerName = Read-FieldValue -Name "testComputerName"
  }
}

function Resolve-TestComputer {
  param(
    [string]$ComputerName,
    [string]$ConfigPath
  )

  $manual = Normalize-Text -Value $ComputerName
  if ($manual -ne "") {
    return [pscustomobject]@{
      Name = $manual
      Source = "argument"
    }
  }

  $cfg = Read-TerrainAgentConfigBlock -ConfigPath $ConfigPath
  $testName = Normalize-Text -Value ([string]$cfg.testComputerName)
  if ($testName -ne "") {
    return [pscustomobject]@{
      Name = $testName
      Source = "fusion_config.terrainAgent.testComputerName"
    }
  }

  $computerName = Normalize-Text -Value ([string]$cfg.computerName)
  if ($computerName -ne "") {
    return [pscustomobject]@{
      Name = $computerName
      Source = "fusion_config.terrainAgent.computerName"
    }
  }

  return [pscustomobject]@{
    Name = $AllowedTestComputer
    Source = "default"
  }
}

function Resolve-ExpectedVersion {
  param([string]$Override)
  $manual = Normalize-Text -Value $Override
  if ($manual -ne "") {
    return [pscustomobject]@{
      Value = $manual
      Source = "argument"
    }
  }

  if (Test-Path -LiteralPath "fusion.version") {
    $fromFile = Normalize-Text -Value (Get-Content -Raw -LiteralPath "fusion.version")
    if ($fromFile -ne "") {
      return [pscustomobject]@{
        Value = $fromFile
        Source = "fusion.version"
      }
    }
  }

  return [pscustomobject]@{
    Value = ""
    Source = "empty"
  }
}

function Resolve-SessionId {
  param([string]$ProvidedSessionId)
  $manual = Normalize-Text -Value $ProvidedSessionId
  if ($manual -ne "") {
    return $manual
  }

  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $suffix = ([guid]::NewGuid().ToString("N")).Substring(0, 8)
  return ("terrain-test-" + $stamp + "-" + $suffix)
}

function Invoke-BridgeGetJson {
  param(
    [string]$BaseUrl,
    [string]$Path
  )
  $url = $BaseUrl.TrimEnd("/") + $Path
  return Invoke-RestMethod -Uri $url -Method Get -TimeoutSec 8
}

function Invoke-BridgePostWithStatus {
  param(
    [string]$BaseUrl,
    [string]$Path,
    [object]$Body
  )

  $url = $BaseUrl.TrimEnd("/") + $Path
  $jsonBody = $Body | ConvertTo-Json -Depth 12
  $statusCode = 0
  $payload = $null

  try {
    $response = Invoke-WebRequest -Uri $url -Method Post -ContentType "application/json" -Body $jsonBody -UseBasicParsing -TimeoutSec 8
    $statusCode = [int]$response.StatusCode
    if (-not [string]::IsNullOrWhiteSpace([string]$response.Content)) {
      $payload = $response.Content | ConvertFrom-Json
    }
  } catch {
    if ($_.Exception.Response) {
      $statusCode = [int]$_.Exception.Response.StatusCode
      $reader = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
      $rawBody = $reader.ReadToEnd()
      if (-not [string]::IsNullOrWhiteSpace($rawBody)) {
        try {
          $payload = $rawBody | ConvertFrom-Json
        } catch {
          $payload = [pscustomobject]@{ raw = $rawBody }
        }
      }
    } else {
      throw
    }
  }

  return [pscustomobject]@{
    StatusCode = $statusCode
    Payload = $payload
  }
}

function Purge-TargetCommandIfNeeded {
  param(
    [string]$ComputerName,
    [string]$CommandsRoot,
    [string]$BaseUrl,
    [switch]$DryRunMode
  )

  $commandPath = Join-Path $CommandsRoot ($ComputerName + ".json")
  if (-not (Test-Path -LiteralPath $commandPath)) {
    return [pscustomobject]@{
      Purged = $false
      Detail = "none"
      Id = ""
    }
  }

  $payload = Get-Content -Raw -LiteralPath $commandPath | ConvertFrom-Json
  $id = Normalize-Text -Value ([string]$payload.id)
  if ($id -eq "") {
    if ($DryRunMode) {
      return [pscustomobject]@{
        Purged = $true
        Detail = "dry-run remove-invalid"
        Id = ""
      }
    }
    Remove-Item -LiteralPath $commandPath -Force
    return [pscustomobject]@{
      Purged = $true
      Detail = "removed-invalid-id"
      Id = ""
    }
  }

  if ($DryRunMode) {
    return [pscustomobject]@{
      Purged = $true
      Detail = "dry-run ack"
      Id = $id
    }
  }

  $ack = Invoke-BridgePostWithStatus -BaseUrl $BaseUrl -Path "/command/ack" -Body @{
    computer = $ComputerName
    id = $id
  }
  $ackOk = ($ack.StatusCode -eq 200 -and $ack.Payload -and $ack.Payload.ok -eq $true)
  if (-not $ackOk) {
    $detail = if ($ack.Payload -and $ack.Payload.detail) { [string]$ack.Payload.detail } else { "status=$($ack.StatusCode)" }
    throw "RUNTIME::purge impossible pour $ComputerName id=$id detail=$detail"
  }

  return [pscustomobject]@{
    Purged = $true
    Detail = "ack"
    Id = $id
  }
}

function Send-CommandAndReadDispatch {
  param(
    [string]$ScriptPath,
    [string]$CommandName,
    [string]$ComputerName,
    [string]$ExpectedVersionValue,
    [string]$SessionTag,
    [switch]$DryRunMode
  )

  if ($DryRunMode) {
    return [pscustomobject]@{
      Id = [guid]::NewGuid().ToString("N")
      Computer = $ComputerName
      Command = $CommandName
      SessionId = $SessionTag
      ExpectedVersion = $ExpectedVersionValue
      CommandPath = Join-Path "tools/terrain_bridge/data/commands" ($ComputerName + ".json")
      Source = "dry-run"
    }
  }

  if (-not (Test-Path -LiteralPath $ScriptPath)) {
    throw "CONFIG::write_command introuvable: $ScriptPath"
  }

  $invokeArgs = @{
    Command = $CommandName
    Computer = $ComputerName
    SessionId = $SessionTag
    JsonOutput = $true
  }
  if ((Normalize-Text -Value $ExpectedVersionValue) -ne "") {
    $invokeArgs.ExpectedVersion = $ExpectedVersionValue
  }

  $raw = & $ScriptPath @invokeArgs 2>&1
  $jsonLine = $null
  for ($idx = $raw.Count - 1; $idx -ge 0; $idx--) {
    $line = [string]$raw[$idx]
    $trim = $line.Trim()
    if ($trim.StartsWith("{") -and $trim.Contains('"id"')) {
      $jsonLine = $trim
      break
    }
  }
  if ($null -eq $jsonLine) {
    $fullOutput = ($raw | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    throw "RUNTIME::write_command output invalide`n$fullOutput"
  }

  $dispatch = $jsonLine | ConvertFrom-Json
  if (-not $dispatch.ok) {
    throw "RUNTIME::write_command retour non ok"
  }
  return $dispatch
}

function Find-ArtifactsForCommand {
  param(
    [string]$ResultsRoot,
    [string]$ReportsRoot,
    [string]$ComputerName,
    [string]$CommandId
  )

  $result = @(Get-ChildItem -LiteralPath $ResultsRoot -File -Filter ($ComputerName + "-" + $CommandId + ".json") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)
  $report = @(Get-ChildItem -LiteralPath $ReportsRoot -File -Filter ($ComputerName + "-*-" + $CommandId + ".json") -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1)

  return [pscustomobject]@{
    ResultReady = $result.Count -ge 1
    ReportReady = $report.Count -ge 1
    ResultPath = if ($result.Count -ge 1) { $result[0].FullName } else { "" }
    ReportPath = if ($report.Count -ge 1) { $report[0].FullName } else { "" }
  }
}

function Count-BridgeEventsForId {
  param(
    [string]$BridgeLogPath,
    [string]$ComputerName,
    [string]$CommandId
  )

  if (-not (Test-Path -LiteralPath $BridgeLogPath)) {
    return [pscustomobject]@{
      Poll = 0
      Result = 0
      AckOk = 0
    }
  }

  $lines = Get-Content -LiteralPath $BridgeLogPath
  return [pscustomobject]@{
    Poll = ($lines | Select-String -SimpleMatch ("command_poll computer=" + $ComputerName + " id=" + $CommandId + " ")).Count
    Result = ($lines | Select-String -SimpleMatch ("result_post computer=" + $ComputerName + " id=" + $CommandId + " ")).Count
    AckOk = ($lines | Select-String -SimpleMatch ("command_ack computer=" + $ComputerName + " id=" + $CommandId + " ok=True detail=cleared")).Count
  }
}

function Save-RunSummary {
  param(
    [string]$SessionRoot,
    [hashtable]$Summary
  )

  if (-not (Test-Path -LiteralPath $SessionRoot)) {
    New-Item -ItemType Directory -Path $SessionRoot -Force | Out-Null
  }
  $summaryPath = Join-Path $SessionRoot "summary.json"
  ($Summary | ConvertTo-Json -Depth 12) + [Environment]::NewLine | Set-Content -LiteralPath $summaryPath -Encoding utf8
  return $summaryPath
}

$exitCode = 1

try {
  $bridgeHealth = Invoke-BridgeGetJson -BaseUrl $BridgeBaseUrl -Path "/health"
  if (-not $bridgeHealth.ok) {
    throw "RUNTIME::bridge indisponible /health"
  }

  $resolvedComputer = Resolve-TestComputer -ComputerName $Computer -ConfigPath $FusionConfigPath
  if ($resolvedComputer.Name -ne $AllowedTestComputer) {
    throw "CONFIG::machine invalide '$($resolvedComputer.Name)'. Cette commande est reservee a $AllowedTestComputer"
  }

  $versionInfo = Resolve-ExpectedVersion -Override $ExpectedVersion
  $runSessionId = Resolve-SessionId -ProvidedSessionId $SessionId

  $commandsRoot = Join-Path $DataRoot "commands"
  $resultsRoot = Join-Path $DataRoot "results"
  $reportsRoot = Join-Path $DataRoot "reports"
  $bridgeLogPath = Join-Path $DataRoot "bridge.log"
  $sessionsRoot = Join-Path $DataRoot "sessions"
  $sessionRoot = Join-Path $sessionsRoot $runSessionId

  $summary = @{
    sessionId = $runSessionId
    dryRun = [bool]$DryRun
    command = $Command
    computer = $resolvedComputer.Name
    computerSource = $resolvedComputer.Source
    expectedVersion = $versionInfo.Value
    expectedVersionSource = $versionInfo.Source
    bridgeBaseUrl = $BridgeBaseUrl
    startedAt = (Get-Date).ToString("s")
    purge = @{}
    dispatch = @{}
    artifacts = @{}
    events = @{}
    replayDetected = $false
    status = "running"
  }

  Write-Host "terrain test run (isolated)"
  Write-Host ("  sessionId: " + $runSessionId)
  Write-Host ("  computer: " + $resolvedComputer.Name + " (source=" + $resolvedComputer.Source + ")")
  Write-Host ("  command: " + $Command)
  if ($versionInfo.Value -ne "") {
    Write-Host ("  expectedVersion: " + $versionInfo.Value + " (source=" + $versionInfo.Source + ")")
  }
  Write-Host ("  mode: " + ($(if ($DryRun) { "dry-run" } else { "live" })))

  if (-not $SkipPurge) {
    $purge = Purge-TargetCommandIfNeeded -ComputerName $resolvedComputer.Name -CommandsRoot $commandsRoot -BaseUrl $BridgeBaseUrl -DryRunMode:$DryRun
    $summary.purge = @{
      executed = $true
      detail = $purge.Detail
      id = $purge.Id
    }
    Write-Host ("  purge: " + $purge.Detail + $(if ($purge.Id -ne "") { " id=" + $purge.Id } else { "" }))
  } else {
    $summary.purge = @{
      executed = $false
      detail = "skipped"
      id = ""
    }
    Write-Host "  purge: skipped"
  }

  $dispatch = Send-CommandAndReadDispatch -ScriptPath $WriteCommandPath -CommandName $Command -ComputerName $resolvedComputer.Name -ExpectedVersionValue $versionInfo.Value -SessionTag $runSessionId -DryRunMode:$DryRun
  $summary.dispatch = @{
    id = [string]$dispatch.id
    commandPath = [string]$dispatch.commandPath
    source = [string]$dispatch.source
  }

  Write-Host ("  dispatched id: " + [string]$dispatch.id)

  if ($DryRun) {
    $summary.status = "dry-run"
    $summary.finishedAt = (Get-Date).ToString("s")
    $summaryPath = Save-RunSummary -SessionRoot $sessionRoot -Summary $summary
    Write-Host ("  summary: " + $summaryPath)
    $exitCode = 0
    exit $exitCode
  }

  $deadline = (Get-Date).AddSeconds([Math]::Max(10, $TimeoutSeconds))
  $sleepSeconds = [Math]::Max(1, $PollSeconds)
  $resultReady = $false
  $reportReady = $false
  $resultPath = ""
  $reportPath = ""
  $events = $null

  while ((Get-Date) -lt $deadline) {
    $artifacts = Find-ArtifactsForCommand -ResultsRoot $resultsRoot -ReportsRoot $reportsRoot -ComputerName $resolvedComputer.Name -CommandId ([string]$dispatch.id
    )
    $events = Count-BridgeEventsForId -BridgeLogPath $bridgeLogPath -ComputerName $resolvedComputer.Name -CommandId ([string]$dispatch.id)
    $resultReady = $artifacts.ResultReady
    $reportReady = $artifacts.ReportReady
    $resultPath = $artifacts.ResultPath
    $reportPath = $artifacts.ReportPath

    if ($resultReady -and $reportReady -and $events.AckOk -ge 1) {
      break
    }
    Start-Sleep -Seconds $sleepSeconds
  }

  if (-not $resultReady -or -not $reportReady) {
    throw "TIMEOUT::run incomplet id=$([string]$dispatch.id) resultReady=$resultReady reportReady=$reportReady"
  }

  if ($events.AckOk -lt 1) {
    throw "TIMEOUT::ack manquant id=$([string]$dispatch.id)"
  }

  $replayDetected = ($events.Poll -gt 1 -or $events.Result -gt 1 -or $events.AckOk -gt 1)

  $summary.artifacts = @{
    result = $resultPath
    report = $reportPath
  }
  $summary.events = @{
    commandPoll = $events.Poll
    resultPost = $events.Result
    ackOk = $events.AckOk
  }
  $summary.replayDetected = $replayDetected
  $summary.status = $(if ($replayDetected) { "warning_replay" } else { "success" })
  $summary.finishedAt = (Get-Date).ToString("s")
  $summaryPath = Save-RunSummary -SessionRoot $sessionRoot -Summary $summary

  Write-Host "run status: SUCCESS"
  Write-Host ("  result: " + $resultPath)
  Write-Host ("  report: " + $reportPath)
  Write-Host ("  events: poll=" + $events.Poll + " result_post=" + $events.Result + " ack=" + $events.AckOk)
  Write-Host ("  replayDetected: " + $replayDetected)
  Write-Host ("  summary: " + $summaryPath)

  if ($replayDetected) {
    throw "REPLAY::evenements multiples detectes pour id=$([string]$dispatch.id)"
  }

  $exitCode = 0
  exit $exitCode
} catch {
  $raw = $_.Exception.Message
  $kind = "RUNTIME"
  $message = $raw
  if ($raw -match '^([A-Z_]+)::(.*)$') {
    $kind = $matches[1]
    $message = $matches[2]
  }

  switch ($kind) {
    "CONFIG" { $exitCode = 2 }
    "TIMEOUT" { $exitCode = 3 }
    "REPLAY" { $exitCode = 4 }
    default { $exitCode = 1 }
  }

  Write-Error ("[" + $kind + "] " + $message)
  exit $exitCode
}
