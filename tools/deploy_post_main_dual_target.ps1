param(
  [ValidateSet("sync_and_test", "sync_only", "test_only")]
  [string]$Command = "sync_and_test",
  [string]$BridgeBaseUrl = "http://127.0.0.1:8765",
  [string]$TestComputer = "",
  [string]$PrimaryComputer = "",
  [string]$ExpectedVersion = "",
  [string]$FusionConfigPath = "fusion_config.lua",
  [string]$ActivityPath = "tools/terrain_bridge/data/activity.json",
  [string]$WriteCommandPath = "tools/write_command.ps1",
  [int]$TimeoutSeconds = 420,
  [int]$PollSeconds = 2,
  [switch]$SkipPurge,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Normalize-Text {
  param([string]$Value)
  if ($null -eq $Value) {
    return ""
  }
  return $Value.Trim()
}

function Test-UsableComputerName {
  param([string]$Name)
  $value = (Normalize-Text -Value $Name).ToLowerInvariant()
  if ([string]::IsNullOrWhiteSpace($value)) {
    return $false
  }
  if ($value -eq "unknown") {
    return $false
  }
  if ($value.StartsWith("bridge_self_test")) {
    return $false
  }
  if ($value.StartsWith("ack_probe")) {
    return $false
  }
  return $true
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
    param(
      [string]$Name
    )
    $fieldMatch = [regex]::Match($block, $Name + '\s*=\s*"(?<value>[^"]*)"')
    if ($fieldMatch.Success) {
      return [string]$fieldMatch.Groups["value"].Value
    }
    return ""
  }

  return [pscustomobject]@{
    computerName = Read-FieldValue -Name "computerName"
    testComputerName = Read-FieldValue -Name "testComputerName"
    primaryComputerName = Read-FieldValue -Name "primaryComputerName"
  }
}

function Read-BridgeActivityComputer {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return ""
  }
  try {
    $json = Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
    if ($null -ne $json -and $null -ne $json.lastCommandPoll) {
      $candidate = Normalize-Text -Value ([string]$json.lastCommandPoll.computer)
      if (Test-UsableComputerName -Name $candidate) {
        return $candidate
      }
    }
  } catch {
    return ""
  }
  return ""
}

function Resolve-ExpectedVersion {
  param([string]$Override)
  $override = Normalize-Text -Value $Override
  if ($override -ne "") {
    return [pscustomobject]@{
      Value = $override
      Source = "argument"
    }
  }

  if (Test-Path -LiteralPath "fusion.version") {
    $version = Normalize-Text -Value (Get-Content -Raw -LiteralPath "fusion.version")
    if ($version -ne "") {
      return [pscustomobject]@{
        Value = $version
        Source = "fusion.version"
      }
    }
  }

  return [pscustomobject]@{
    Value = ""
    Source = "empty"
  }
}

function Resolve-Targets {
  param(
    [string]$TestInput,
    [string]$PrimaryInput,
    [string]$ConfigPath,
    [string]$ActivityFile
  )

  $cfg = Read-TerrainAgentConfigBlock -ConfigPath $ConfigPath
  $activityComputer = Read-BridgeActivityComputer -Path $ActivityFile

  $testSources = @(
    [pscustomobject]@{ Value = Normalize-Text -Value $TestInput; Source = "argument" },
    [pscustomobject]@{ Value = Normalize-Text -Value $cfg.testComputerName; Source = "fusion_config.terrainAgent.testComputerName" },
    [pscustomobject]@{ Value = Normalize-Text -Value $cfg.computerName; Source = "fusion_config.terrainAgent.computerName" },
    [pscustomobject]@{ Value = Normalize-Text -Value $activityComputer; Source = "bridge_activity.lastCommandPoll" },
    [pscustomobject]@{ Value = "fusion_terrain_01"; Source = "default" }
  )

  $resolvedTest = $null
  foreach ($candidate in $testSources) {
    if (Test-UsableComputerName -Name $candidate.Value) {
      $resolvedTest = $candidate
      break
    }
  }
  if ($null -eq $resolvedTest) {
    throw "CONFIG::impossible de resoudre le computer de test"
  }

  $primarySources = @(
    [pscustomobject]@{ Value = Normalize-Text -Value $PrimaryInput; Source = "argument" },
    [pscustomobject]@{ Value = Normalize-Text -Value $cfg.primaryComputerName; Source = "fusion_config.terrainAgent.primaryComputerName" }
  )

  $resolvedPrimary = $null
  foreach ($candidate in $primarySources) {
    if (Test-UsableComputerName -Name $candidate.Value) {
      $resolvedPrimary = $candidate
      break
    }
  }

  if ($null -eq $resolvedPrimary) {
    throw "CONFIG::computer principal absent (utiliser -PrimaryComputer ou fusion_config.lua terrainAgent.primaryComputerName)"
  }

  if ($resolvedPrimary.Value -eq $resolvedTest.Value) {
    throw "CONFIG::computer test et principal identiques ($($resolvedTest.Value))"
  }

  return [pscustomobject]@{
    Test = $resolvedTest
    Primary = $resolvedPrimary
  }
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

function Purge-CommandIfNeeded {
  param(
    [string]$Computer,
    [string]$BridgeBaseUrl,
    [string]$CommandsRoot,
    [switch]$DryRunMode
  )

  $commandPath = Join-Path $CommandsRoot ($Computer + ".json")
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

  $ack = Invoke-BridgePostWithStatus -BaseUrl $BridgeBaseUrl -Path "/command/ack" -Body @{
    computer = $Computer
    id = $id
  }
  $ackOk = ($ack.StatusCode -eq 200 -and $ack.Payload -and $ack.Payload.ok -eq $true)
  if (-not $ackOk) {
    $detail = if ($ack.Payload -and $ack.Payload.detail) { [string]$ack.Payload.detail } else { "status=$($ack.StatusCode)" }
    throw "RUNTIME::purge impossible pour $Computer id=$id detail=$detail"
  }

  return [pscustomobject]@{
    Purged = $true
    Detail = "ack"
    Id = $id
  }
}

function Send-Command {
  param(
    [string]$CommandName,
    [string]$Computer,
    [string]$ExpectedVersion,
    [string]$WriteScriptPath,
    [switch]$DryRunMode
  )

  if ($DryRunMode) {
    return [pscustomobject]@{
      Computer = $Computer
      Id = [guid]::NewGuid().ToString("N")
      Command = $CommandName
      ExpectedVersion = $ExpectedVersion
      Source = "dry-run"
    }
  }

  if (-not (Test-Path -LiteralPath $WriteScriptPath)) {
    throw "CONFIG::write_command introuvable: $WriteScriptPath"
  }

  $args = @("-Command", $CommandName, "-Computer", $Computer)
  if ((Normalize-Text -Value $ExpectedVersion) -ne "") {
    $args += @("-ExpectedVersion", $ExpectedVersion)
  }

  $output = & $WriteScriptPath @args 2>&1
  if ($LASTEXITCODE -ne 0) {
    $details = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    throw "RUNTIME::write_command failed for $Computer`n$details"
  }

  $id = ""
  foreach ($line in $output) {
    $text = [string]$line
    if ($text -match '^\s*id:\s*([0-9a-fA-F]{16,})\s*$') {
      $id = $matches[1].ToLowerInvariant()
    }
  }

  if ($id -eq "") {
    $commandPath = Join-Path "tools/terrain_bridge/data/commands" ($Computer + ".json")
    if (Test-Path -LiteralPath $commandPath) {
      $cmdPayload = Get-Content -Raw -LiteralPath $commandPath | ConvertFrom-Json
      $id = Normalize-Text -Value ([string]$cmdPayload.id)
    }
  }

  if ($id -eq "") {
    throw "RUNTIME::impossible de lire l'id commande pour $Computer"
  }

  return [pscustomobject]@{
    Computer = $Computer
    Id = $id
    Command = $CommandName
    ExpectedVersion = $ExpectedVersion
    Source = "write_command"
  }
}

function Find-Artifacts {
  param(
    [string]$ResultsRoot,
    [string]$ReportsRoot,
    [string]$Computer,
    [string]$Id
  )

  $resultFiles = @(Get-ChildItem -LiteralPath $ResultsRoot -File -Filter ("*-" + $Id + ".json") -ErrorAction SilentlyContinue)
  $reportFiles = @(Get-ChildItem -LiteralPath $ReportsRoot -File -Filter ($Computer + "-*-" + $Id + ".json") -ErrorAction SilentlyContinue)

  return [pscustomobject]@{
    ResultCount = $resultFiles.Count
    ReportCount = $reportFiles.Count
    ResultFile = if ($resultFiles.Count -ge 1) { $resultFiles[0].FullName } else { "" }
    ReportFile = if ($reportFiles.Count -ge 1) { $reportFiles[0].FullName } else { "" }
  }
}

function Get-BridgeEventCounts {
  param(
    [string]$BridgeLogPath,
    [string]$Computer,
    [string]$Id
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
    Poll = ($lines | Select-String -SimpleMatch ("command_poll computer=" + $Computer + " id=" + $Id + " ")).Count
    Result = ($lines | Select-String -SimpleMatch ("result_post computer=" + $Computer + " id=" + $Id + " ")).Count
    AckOk = ($lines | Select-String -SimpleMatch ("command_ack computer=" + $Computer + " id=" + $Id + " ok=True detail=cleared")).Count
  }
}

function Wait-ForDualResults {
  param(
    [object[]]$Targets,
    [int]$TimeoutSecondsValue,
    [int]$PollSecondsValue,
    [string]$ResultsRoot,
    [string]$ReportsRoot,
    [string]$BridgeLogPath,
    [switch]$DryRunMode
  )

  if ($DryRunMode) {
    return [pscustomobject]@{
      Completed = $true
      Details = @()
      DryRun = $true
    }
  }

  $deadline = (Get-Date).AddSeconds([Math]::Max(10, $TimeoutSecondsValue))
  $pollDelay = [Math]::Max(1, $PollSecondsValue)
  $state = @{}

  foreach ($target in $Targets) {
    $state[$target.Computer] = [pscustomobject]@{
      Computer = $target.Computer
      Id = $target.Id
      ResultReady = $false
      ReportReady = $false
      ResultCount = 0
      ReportCount = 0
      ResultFile = ""
      ReportFile = ""
      PollCount = 0
      ResultPostCount = 0
      AckOkCount = 0
    }
  }

  while ((Get-Date) -lt $deadline) {
    $allDone = $true

    foreach ($target in $Targets) {
      $entry = $state[$target.Computer]
      $artifacts = Find-Artifacts -ResultsRoot $ResultsRoot -ReportsRoot $ReportsRoot -Computer $entry.Computer -Id $entry.Id
      $events = Get-BridgeEventCounts -BridgeLogPath $BridgeLogPath -Computer $entry.Computer -Id $entry.Id

      $entry.ResultCount = $artifacts.ResultCount
      $entry.ReportCount = $artifacts.ReportCount
      $entry.ResultFile = $artifacts.ResultFile
      $entry.ReportFile = $artifacts.ReportFile
      $entry.ResultReady = $artifacts.ResultCount -ge 1
      $entry.ReportReady = $artifacts.ReportCount -ge 1
      $entry.PollCount = $events.Poll
      $entry.ResultPostCount = $events.Result
      $entry.AckOkCount = $events.AckOk

      if (-not ($entry.ResultReady -and $entry.ReportReady)) {
        $allDone = $false
      }
    }

    if ($allDone) {
      break
    }

    Start-Sleep -Seconds $pollDelay
  }

  $missing = New-Object System.Collections.Generic.List[string]
  foreach ($target in $Targets) {
    $entry = $state[$target.Computer]
    if (-not $entry.ResultReady) {
      $missing.Add($entry.Computer + ": result manquant pour id " + $entry.Id)
    }
    if (-not $entry.ReportReady) {
      $missing.Add($entry.Computer + ": report manquant pour id " + $entry.Id)
    }
  }
  if ($missing.Count -gt 0) {
    throw "TIMEOUT::retours incomplets`n - " + ($missing -join "`n - ")
  }

  $replayIssues = New-Object System.Collections.Generic.List[string]
  foreach ($target in $Targets) {
    $entry = $state[$target.Computer]
    if ($entry.ResultCount -ne 1) {
      $replayIssues.Add($entry.Computer + ": result count=" + $entry.ResultCount + " id=" + $entry.Id)
    }
    if ($entry.ReportCount -ne 1) {
      $replayIssues.Add($entry.Computer + ": report count=" + $entry.ReportCount + " id=" + $entry.Id)
    }
    if ($entry.PollCount -ne 1) {
      $replayIssues.Add($entry.Computer + ": command_poll count=" + $entry.PollCount + " id=" + $entry.Id)
    }
    if ($entry.ResultPostCount -ne 1) {
      $replayIssues.Add($entry.Computer + ": result_post count=" + $entry.ResultPostCount + " id=" + $entry.Id)
    }
    if ($entry.AckOkCount -ne 1) {
      $replayIssues.Add($entry.Computer + ": command_ack ok count=" + $entry.AckOkCount + " id=" + $entry.Id)
    }
  }
  if ($replayIssues.Count -gt 0) {
    throw "REPLAY::cycles non idempotents detectes`n - " + ($replayIssues -join "`n - ")
  }

  return [pscustomobject]@{
    Completed = $true
    Details = @($state.Values)
    DryRun = $false
  }
}

$exitCode = 1

try {
  if (-not (Test-Path -LiteralPath $WriteCommandPath)) {
    throw "CONFIG::script write_command introuvable: $WriteCommandPath"
  }

  $bridgeHealth = Invoke-BridgeGetJson -BaseUrl $BridgeBaseUrl -Path "/health"
  if (-not $bridgeHealth.ok) {
    throw "RUNTIME::bridge indisponible /health"
  }

  $targets = Resolve-Targets -TestInput $TestComputer -PrimaryInput $PrimaryComputer -ConfigPath $FusionConfigPath -ActivityFile $ActivityPath
  $expected = Resolve-ExpectedVersion -Override $ExpectedVersion

  $commandsRoot = "tools/terrain_bridge/data/commands"
  $resultsRoot = "tools/terrain_bridge/data/results"
  $reportsRoot = "tools/terrain_bridge/data/reports"
  $bridgeLogPath = "tools/terrain_bridge/data/bridge.log"

  Write-Host "post-main dual-target deployment"
  Write-Host ("  test computer: " + $targets.Test.Value + " (source=" + $targets.Test.Source + ")")
  Write-Host ("  primary computer: " + $targets.Primary.Value + " (source=" + $targets.Primary.Source + ")")
  if ($expected.Value -ne "") {
    Write-Host ("  expected version: " + $expected.Value + " (source=" + $expected.Source + ")")
  }
  Write-Host ("  command: " + $Command)
  Write-Host ("  mode: " + ($(if ($DryRun) { "dry-run" } else { "live" })))

  if (-not $SkipPurge) {
    $purgeTest = Purge-CommandIfNeeded -Computer $targets.Test.Value -BridgeBaseUrl $BridgeBaseUrl -CommandsRoot $commandsRoot -DryRunMode:$DryRun
    $purgePrimary = Purge-CommandIfNeeded -Computer $targets.Primary.Value -BridgeBaseUrl $BridgeBaseUrl -CommandsRoot $commandsRoot -DryRunMode:$DryRun
    Write-Host ("  purge test: " + $purgeTest.Detail + $(if ($purgeTest.Id -ne "") { " id=" + $purgeTest.Id } else { "" }))
    Write-Host ("  purge primary: " + $purgePrimary.Detail + $(if ($purgePrimary.Id -ne "") { " id=" + $purgePrimary.Id } else { "" }))
  } else {
    Write-Host "  purge skipped"
  }

  $testDispatch = Send-Command -CommandName $Command -Computer $targets.Test.Value -ExpectedVersion $expected.Value -WriteScriptPath $WriteCommandPath -DryRunMode:$DryRun
  $primaryDispatch = Send-Command -CommandName $Command -Computer $targets.Primary.Value -ExpectedVersion $expected.Value -WriteScriptPath $WriteCommandPath -DryRunMode:$DryRun

  Write-Host ("  sent test id: " + $testDispatch.Id)
  Write-Host ("  sent primary id: " + $primaryDispatch.Id)

  $wait = Wait-ForDualResults -Targets @($testDispatch, $primaryDispatch) -TimeoutSecondsValue $TimeoutSeconds -PollSecondsValue $PollSeconds -ResultsRoot $resultsRoot -ReportsRoot $reportsRoot -BridgeLogPath $bridgeLogPath -DryRunMode:$DryRun

  if ($DryRun) {
    Write-Host "dry-run completed: aucune attente terrain executee"
    $exitCode = 0
    exit $exitCode
  }

  Write-Host "dual-target status: SUCCESS"
  foreach ($item in $wait.Details | Sort-Object Computer) {
    Write-Host ("  - " + $item.Computer + " id=" + $item.Id)
    Write-Host ("      result: " + $item.ResultFile)
    Write-Host ("      report: " + $item.ReportFile)
    Write-Host ("      events: poll=" + $item.PollCount + " result_post=" + $item.ResultPostCount + " ack=" + $item.AckOkCount)
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
