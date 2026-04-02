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

local function trim(value)
  value = tostring(value or "")
  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  return value
end

local function loadConfig()
  local base = readLuaConfig("terrain/agent_config.lua")
  local fusion = readLuaConfig("fusion_config.lua")
  local terrainCfg = type(fusion.terrainAgent) == "table" and fusion.terrainAgent or {}
  local cfg = merge(base, terrainCfg)
  if cfg.computerName == "" or cfg.computerName == nil then
    cfg.computerName = os.getComputerLabel() or ("computer_" .. tostring(os.getComputerID()))
  end
  if cfg.pendingResultFile == nil or cfg.pendingResultFile == "" then
    cfg.pendingResultFile = "/terrain_agent.pending_result.json"
  end
  if cfg.pendingReportFile == nil or cfg.pendingReportFile == "" then
    cfg.pendingReportFile = "/terrain_agent.pending_report.json"
  end
  if cfg.commandAckEndpoint == nil or cfg.commandAckEndpoint == "" then
    cfg.commandAckEndpoint = "/command/ack"
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
  if not fh then
    return false, "cannot open " .. tostring(path)
  end
  fh.write(text or "")
  fh.close()
  return true
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
  local ok, response, err = pcall(http.get, url)
  if not ok then
    return nil, "http get crash: " .. tostring(response)
  end
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
  local payload = textutils.serializeJSON(data or {})
  local ok, response, err = pcall(http.post, url, payload, {
    ["Content-Type"] = "application/json",
  })
  if not ok then
    return false, "http post crash: " .. tostring(response)
  end
  if not response then
    return false, err or "http post failed"
  end
  response.readAll()
  response.close()
  return true
end

local function decodeJsonFile(path)
  if not fs.exists(path) then
    return nil, "missing"
  end
  local fh = fs.open(path, "r")
  if not fh then
    return nil, "cannot open " .. tostring(path)
  end
  local raw = fh.readAll() or ""
  fh.close()
  if raw == "" then
    return nil, "empty"
  end
  local ok, data = pcall(textutils.unserializeJSON, raw)
  if ok and type(data) == "table" then
    return data
  end
  local okLua, luaData = pcall(textutils.unserialize, raw)
  if okLua and type(luaData) == "table" then
    return luaData
  end
  return nil, "invalid"
end

local function saveJsonFile(path, payload)
  local ok, serialized = pcall(textutils.serializeJSON, payload or {})
  if not ok or type(serialized) ~= "string" or serialized == "" then
    return false, "json serialize failed"
  end
  local writeOk, writeErr = writeText(path, serialized)
  if not writeOk then
    return false, writeErr
  end
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
  local ok, err = writeText(cfg.heartbeatFile, nowText())
  if not ok then
    appendLog("heartbeat write failed: " .. tostring(err))
  end
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

local function commandAckUrl(cfg)
  return cfg.collectorBaseUrl .. cfg.commandAckEndpoint
end

local function postPending(path, url, label)
  local payload = decodeJsonFile(path)
  if type(payload) ~= "table" then
    return false
  end
  local ok, err = httpPostJson(url, payload)
  if not ok then
    appendLog(label .. " pending post failed: " .. tostring(err))
    return false
  end
  if fs.exists(path) then
    fs.delete(path)
  end
  appendLog(label .. " pending post flushed")
  return true
end

local function flushPending(cfg)
  postPending(cfg.pendingResultFile, resultUrl(cfg), "result")
  postPending(cfg.pendingReportFile, reportUrl(cfg), "report")
end

local function emitResult(cfg, payload)
  payload = type(payload) == "table" and payload or {}
  payload.computerName = cfg.computerName
  payload.sentAt = nowText()
  local saved, saveErr = saveJsonFile(cfg.resultFile, payload)
  if not saved then
    appendLog("result local save failed: " .. tostring(saveErr))
  end
  local ok, err = httpPostJson(resultUrl(cfg), payload)
  if not ok then
    appendLog("result post failed: " .. tostring(err))
    local pendingSaved, pendingErr = saveJsonFile(cfg.pendingResultFile, payload)
    if not pendingSaved then
      appendLog("result pending save failed: " .. tostring(pendingErr))
    end
    return false, err
  end
  if fs.exists(cfg.pendingResultFile) then
    fs.delete(cfg.pendingResultFile)
  end
  return true
end

local function emitReport(cfg, payload)
  payload = type(payload) == "table" and payload or {}
  payload.computerName = cfg.computerName
  payload.sentAt = nowText()
  local saved, saveErr = saveJsonFile(cfg.reportFile, payload)
  if not saved then
    appendLog("report local save failed: " .. tostring(saveErr))
  end
  local ok, err = httpPostJson(reportUrl(cfg), payload)
  if not ok then
    appendLog("report post failed: " .. tostring(err))
    local pendingSaved, pendingErr = saveJsonFile(cfg.pendingReportFile, payload)
    if not pendingSaved then
      appendLog("report pending save failed: " .. tostring(pendingErr))
    end
    return false, err
  end
  if fs.exists(cfg.pendingReportFile) then
    fs.delete(cfg.pendingReportFile)
  end
  return true
end

local function readLastCommandId(path)
  local payload = decodeJsonFile(path)
  if type(payload) == "table" and payload.id ~= nil then
    return trim(payload.id)
  end
  return ""
end

local function saveCommandSnapshot(path, command)
  local snapshot = {
    id = trim(command and command.id or ""),
    command = trim(command and command.command or ""),
    expectedVersion = trim(command and command.expectedVersion or ""),
    receivedAt = nowText(),
  }
  local ok, err = saveJsonFile(path, snapshot)
  if not ok then
    appendLog("command snapshot save failed: " .. tostring(err))
  end
end

local function commandId(command)
  return trim(type(command) == "table" and command.id or "")
end

local function commandName(command)
  return trim(type(command) == "table" and command.command or "")
end

local function ackCommand(cfg, id)
  id = trim(id)
  if id == "" then
    return false, "missing id"
  end
  return httpPostJson(commandAckUrl(cfg), {
    computer = cfg.computerName,
    id = id,
  })
end

local function runSync()
  local fusionCfg = readLuaConfig("fusion_config.lua")
  local ok, resultOrErr = pcall(Orchestrator.sync, fusionCfg, appendLog)
  if not ok then
    return nil, "sync crashed: " .. tostring(resultOrErr)
  end
  if type(resultOrErr) ~= "table" then
    return nil, "sync returned invalid payload"
  end
  return resultOrErr
end

local function runTests(cfg, expectedVersion, id)
  local ok, reportOrErr = pcall(ReportRunner.runAll, {
    expectedVersion = expectedVersion,
  })
  if not ok then
    return nil, "tests crashed: " .. tostring(reportOrErr)
  end
  if type(reportOrErr) ~= "table" then
    return nil, "tests returned invalid payload"
  end
  local report = reportOrErr
  report.commandId = id
  local posted, reportErr = emitReport(cfg, report)
  if not posted then
    return report, "report upload failed: " .. tostring(reportErr)
  end
  return report
end

local function handleCommand(cfg, command)
  local kind = commandName(command)
  local id = commandId(command)
  local expectedVersion = trim(command and command.expectedVersion or "")
  appendLog("command received: " .. kind .. " id=" .. id)

  local result = {
    ok = false,
    command = kind,
    id = id,
    localVersion = readVersion(),
  }

  saveCommandSnapshot(cfg.commandFile, command)

  if kind == "noop" or kind == "" then
    result.ok = true
    result.detail = "noop"
    return result
  end

  if kind == "sync_only" then
    local syncResult, syncErr = runSync()
    if not syncResult then
      result.detail = syncErr or "sync failed"
      return result
    end
    result.ok = syncResult.ok == true
    result.detail = syncResult.detail or "sync complete"
    result.localVersion = syncResult.localVersionAfter or syncResult.localVersionBefore
    result.remoteVersion = syncResult.remoteVersion
    result.remoteCommit = syncResult.remoteCommit
    return result
  end

  if kind == "test_only" then
    local report, testErr = runTests(cfg, expectedVersion, id)
    if not report then
      result.detail = testErr or "tests failed"
      return result
    end
    result.ok = testErr == nil
    result.detail = testErr and ("tests complete with warnings: " .. tostring(testErr)) or "tests complete"
    result.localVersion = readVersion()
    result.reportLabel = report.label
    return result
  end

  if kind == "sync_and_test" then
    local syncResult, syncErr = runSync()
    if not syncResult then
      result.detail = syncErr or "sync failed"
      return result
    end
    result.remoteVersion = syncResult.remoteVersion
    result.remoteCommit = syncResult.remoteCommit

    if syncResult.ok ~= true then
      result.detail = "sync failed: " .. tostring(syncResult.detail or "unknown")
      result.localVersion = syncResult.localVersionAfter or syncResult.localVersionBefore or readVersion()
      return result
    end

    local testExpected = syncResult.localVersionAfter or syncResult.remoteVersion or expectedVersion
    local report, testErr = runTests(cfg, testExpected, id)
    result.ok = (testErr == nil)
    result.detail = testErr and ("sync ok, tests/report issue: " .. tostring(testErr)) or "sync and test complete"
    result.localVersion = readVersion()
    result.reportLabel = type(report) == "table" and report.label or nil
    return result
  end

  result.detail = "unknown command"
  return result
end

function Agent.runLoop()
  local cfg = loadConfig()
  appendLog("daemon start: collector=" .. tostring(cfg.collectorBaseUrl) .. " computer=" .. tostring(cfg.computerName))
  local lastProcessedId = readLastCommandId(cfg.commandFile)
  if lastProcessedId ~= "" then
    appendLog("resume from last command id=" .. lastProcessedId)
  end
  local previousConnectivity = nil
  local duplicateLoggedId = ""

  while true do
    writeHeartbeat(cfg)
    local isAllowed, checkErr = checkUrl(cfg.collectorBaseUrl .. cfg.commandEndpoint)
    if previousConnectivity == nil or previousConnectivity ~= isAllowed then
      appendLog("collector connectivity=" .. tostring(isAllowed) .. " reason=" .. tostring(checkErr or "ok"))
      previousConnectivity = isAllowed
    end

    if isAllowed then
      flushPending(cfg)
      local command, commandErr = httpGetJson(commandUrl(cfg))
      if command then
        local id = commandId(command)
        local kind = commandName(command)
        if id == "" then
          appendLog("command ignored: missing id command=" .. tostring(kind))
          emitResult(cfg, {
            ok = false,
            command = kind,
            id = "",
            detail = "invalid command: missing id",
            localVersion = readVersion(),
          })
        elseif id == lastProcessedId then
          if duplicateLoggedId ~= id then
            appendLog("command skipped duplicate id=" .. tostring(id))
            duplicateLoggedId = id
          end
        else
          duplicateLoggedId = ""
          local okHandle, resultOrErr = pcall(handleCommand, cfg, command)
          local finalResult
          if not okHandle then
            appendLog("command handler crash id=" .. tostring(id) .. " err=" .. tostring(resultOrErr))
            finalResult = {
              ok = false,
              command = kind,
              id = id,
              detail = "command handler crash: " .. tostring(resultOrErr),
              localVersion = readVersion(),
            }
          else
            finalResult = type(resultOrErr) == "table" and resultOrErr or {
              ok = false,
              command = kind,
              id = id,
              detail = "invalid handler result",
              localVersion = readVersion(),
            }
          end

          local _, postErr = emitResult(cfg, finalResult)
          if postErr then
            appendLog("command result queued id=" .. tostring(id) .. " err=" .. tostring(postErr))
          end

          local ackOk, ackErr = ackCommand(cfg, id)
          if not ackOk then
            appendLog("command ack failed id=" .. tostring(id) .. " err=" .. tostring(ackErr))
          else
            appendLog("command ack ok id=" .. tostring(id))
          end

          lastProcessedId = id
          appendLog("command completed id=" .. tostring(id) .. " ok=" .. tostring(finalResult.ok) .. " detail=" .. tostring(finalResult.detail))
        end
      elseif commandErr then
        appendLog("command poll failed: " .. tostring(commandErr))
      end
    end

    sleep(tonumber(cfg.pollSeconds) or 5)
  end
end

return Agent
