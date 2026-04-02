local Orchestrator = assert(dofile("core/update/orchestrator.lua"))
local ReportRunner = assert(dofile("terrain/report_runner.lua"))

local Agent = {}

local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return tostring(os.epoch and os.epoch("utc") or 0)
end

local function readLuaConfig(path)
  local ok, cfg = pcall(dofile, path)
  if ok and type(cfg) == "table" then
    return cfg
  end
  return {}
end

local function merge(base, extra)
  local out = {}
  for k, v in pairs(base or {}) do
    out[k] = v
  end
  for k, v in pairs(extra or {}) do
    out[k] = v
  end
  return out
end

local function loadConfig()
  local base = readLuaConfig("terrain/agent_config.lua")
  local fusion = readLuaConfig("fusion_config.lua")
  local terrainCfg = type(fusion.terrainAgent) == "table" and fusion.terrainAgent or {}
  local cfg = merge(base, terrainCfg)
  if cfg.computerName == "" or cfg.computerName == nil then
    cfg.computerName = os.getComputerLabel() or ("computer_" .. tostring(os.getComputerID()))
  end
  return cfg
end

local function appendLog(message)
  local fh = fs.open("/terrain_agent.log", "a")
  if fh then
    fh.writeLine("[" .. nowText() .. "] " .. tostring(message))
    fh.close()
  end
end

local function writeText(path, text)
  local fh = fs.open(path, "w")
  if fh then
    fh.write(text or "")
    fh.close()
  end
end

local function checkUrl(url)
  if not http or type(http.checkURL) ~= "function" then
    return false, "http unavailable"
  end
  local ok, allowed, err = pcall(http.checkURL, url)
  if not ok then
    return false, tostring(allowed)
  end
  return allowed == true, err
end

local function httpGetJson(url)
  local response, err = http.get(url)
  if not response then
    return nil, err or "http get failed"
  end
  local body = response.readAll() or ""
  response.close()
  local ok, data = pcall(textutils.unserializeJSON, body)
  if not ok or type(data) ~= "table" then
    return nil, "invalid json"
  end
  return data
end

local function httpPostJson(url, data)
  local payload = textutils.serializeJSON(data)
  local response, err = http.post(url, payload, {
    ["Content-Type"] = "application/json",
  })
  if not response then
    return false, err or "http post failed"
  end
  response.readAll()
  response.close()
  return true
end

local function readVersion()
  if not fs.exists("fusion.version") then
    return nil
  end
  local fh = fs.open("fusion.version", "r")
  if not fh then
    return nil
  end
  local version = fh.readAll() or ""
  fh.close()
  version = tostring(version):gsub("^%s+", ""):gsub("%s+$", "")
  return version
end

local function writeHeartbeat(cfg)
  writeText(cfg.heartbeatFile, nowText())
end

local function urlEncode(value)
  if textutils and type(textutils.urlEncode) == "function" then
    return textutils.urlEncode(value)
  end
  return tostring(value or "")
end

local function commandUrl(cfg)
  return cfg.collectorBaseUrl .. cfg.commandEndpoint .. "?computer=" .. urlEncode(cfg.computerName)
end

local function resultUrl(cfg)
  return cfg.collectorBaseUrl .. cfg.resultEndpoint
end

local function reportUrl(cfg)
  return cfg.collectorBaseUrl .. cfg.reportEndpoint
end

local function emitResult(cfg, payload)
  payload.computerName = cfg.computerName
  payload.sentAt = nowText()
  writeText(cfg.resultFile, textutils.serializeJSON(payload))
  local ok, err = httpPostJson(resultUrl(cfg), payload)
  if not ok then
    appendLog("result post failed: " .. tostring(err))
  end
end

local function emitReport(cfg, payload)
  payload.computerName = cfg.computerName
  payload.sentAt = nowText()
  writeText(cfg.reportFile, textutils.serializeJSON(payload))
  local ok, err = httpPostJson(reportUrl(cfg), payload)
  if not ok then
    appendLog("report post failed: " .. tostring(err))
  end
end

local function runSync()
  local fusionCfg = readLuaConfig("fusion_config.lua")
  return Orchestrator.sync(fusionCfg, appendLog)
end

local function runTests(cfg, expectedVersion)
  local report = ReportRunner.runAll({
    expectedVersion = expectedVersion,
  })
  emitReport(cfg, report)
  return report
end

local function handleCommand(cfg, command)
  local kind = tostring(command.command or "")
  local commandId = tostring(command.id or "")
  appendLog("command received: " .. kind .. " id=" .. commandId)
  writeText(cfg.commandFile, textutils.serialize(command))

  if kind == "noop" or kind == "" then
    emitResult(cfg, {
      ok = true,
      command = kind,
      id = commandId,
      detail = "noop",
      localVersion = readVersion(),
    })
    return
  end

  if kind == "sync_only" then
    local result = runSync()
    emitResult(cfg, {
      ok = result.ok,
      command = kind,
      id = commandId,
      detail = result.detail,
      localVersion = result.localVersionAfter or result.localVersionBefore,
      remoteVersion = result.remoteVersion,
      remoteCommit = result.remoteCommit,
    })
    return
  end

  if kind == "test_only" then
    local report = runTests(cfg, command.expectedVersion)
    emitResult(cfg, {
      ok = true,
      command = kind,
      id = commandId,
      detail = "tests complete",
      localVersion = readVersion(),
      reportLabel = report.label,
    })
    return
  end

  if kind == "sync_and_test" then
    local syncResult = runSync()
    emitResult(cfg, {
      ok = syncResult.ok,
      command = "sync_only",
      id = commandId,
      detail = syncResult.detail,
      localVersion = syncResult.localVersionAfter or syncResult.localVersionBefore,
      remoteVersion = syncResult.remoteVersion,
      remoteCommit = syncResult.remoteCommit,
    })

    if syncResult.ok then
      local expectedVersion = syncResult.localVersionAfter or syncResult.remoteVersion or command.expectedVersion
      local report = runTests(cfg, expectedVersion)
      emitResult(cfg, {
        ok = true,
        command = "sync_and_test",
        id = commandId,
        detail = "sync and test complete",
        localVersion = readVersion(),
        reportLabel = report.label,
      })
    end
    return
  end

  emitResult(cfg, {
    ok = false,
    command = kind,
    id = commandId,
    detail = "unknown command",
    localVersion = readVersion(),
  })
end

function Agent.runLoop()
  local cfg = loadConfig()
  local ok, err = checkUrl(cfg.collectorBaseUrl .. cfg.commandEndpoint)
  appendLog("daemon start: collector=" .. tostring(cfg.collectorBaseUrl) .. " computer=" .. tostring(cfg.computerName))
  if not ok then
    appendLog("collector URL not allowed: " .. tostring(err))
  end

  while true do
    writeHeartbeat(cfg)

    if ok then
      local command, commandErr = httpGetJson(commandUrl(cfg))
      if command then
        handleCommand(cfg, command)
      elseif commandErr then
        appendLog("command poll failed: " .. tostring(commandErr))
      end
    end

    sleep(tonumber(cfg.pollSeconds) or 5)
  end
end

return Agent
