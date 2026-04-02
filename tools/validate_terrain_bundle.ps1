param(
  [string]$RepoRoot = "."
)

$ErrorActionPreference = "Stop"

$required = @(
  "core/update/orchestrator.lua",
  "bin/update_check.lua",
  "bin/update_sync.lua",
  "bin/update_apply.lua",
  "bin/update_rollback.lua",
  "bin/terrain_sync_and_test.lua",
  "bin/terrain_test_only.lua",
  "terrain/agent_config.lua",
  "terrain/harness.lua",
  "terrain/report_runner.lua",
  "terrain/agent_daemon.lua",
  "terrain/boot.lua",
  "terrain/suites/smoke.lua",
  "terrain/suites/update_validation.lua",
  "terrain/suites/peripherals.lua",
  "tools/publish_local_release.ps1",
  "tools/write_command.ps1",
  "tools/start_terrain_bridge.ps1",
  "tools/test_terrain_bridge.ps1",
  "tools/terrain_bridge/server.py",
  "startup.lua"
)

$missing = @()
foreach ($path in $required) {
  $target = Join-Path $RepoRoot $path
  if (-not (Test-Path -LiteralPath $target)) {
    $missing += $path
  }
}

if ($missing.Count -gt 0) {
  Write-Host "Terrain bundle validation FAILED"
  foreach ($path in $missing) {
    Write-Host ("  - missing: " + $path)
  }
  exit 1
}

Write-Host "Terrain bundle validation OK"
Write-Host ("  files checked: " + $required.Count)
