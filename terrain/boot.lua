local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return tostring(os.epoch and os.epoch("utc") or 0)
end

local function appendBootLog(message)
  local fh = fs.open("/terrain_agent.startup.log", "a")
  if fh then
    fh.writeLine("[" .. nowText() .. "] " .. tostring(message))
    fh.close()
  end
end

local function readLuaTable(path)
  local ok, value = pcall(dofile, path)
  if ok and type(value) == "table" then
    return value
  end
  return {}
end

local function mergeTable(base, extra)
  local merged = {}
  for key, value in pairs(base or {}) do
    merged[key] = value
  end
  for key, value in pairs(extra or {}) do
    merged[key] = value
  end
  return merged
end

local function normalizeRuntimeMode(value)
  local raw = string.lower(tostring(value or ""))
  if raw == "daemon" then
    return "daemon"
  end
  return "runtime_gated"
end

local function resolveRuntimeMode()
  local defaults = readLuaTable("terrain/agent_config.lua")
  local fusion = readLuaTable("fusion_config.lua")
  local fromFusion = type(fusion.terrainAgent) == "table" and fusion.terrainAgent or {}
  local cfg = mergeTable(defaults, fromFusion)
  return normalizeRuntimeMode(cfg.runtimeMode)
end

local runtimeMode = resolveRuntimeMode()
local hostedMode = (rawget(_G, "__fusionTerrainHosted") == true)
if runtimeMode == "runtime_gated" and not hostedMode then
  appendBootLog("boot: runtime-gated mode without host, refusing standalone daemon start")
  return
end

appendBootLog("boot: loading terrain/agent_daemon.lua")
local okAgent, agentOrErr = pcall(dofile, "terrain/agent_daemon.lua")
if not okAgent then
  appendBootLog("boot: load failed err=" .. tostring(agentOrErr))
  error(agentOrErr)
end

if type(agentOrErr) ~= "table" or type(agentOrErr.runLoop) ~= "function" then
  appendBootLog("boot: invalid daemon module")
  error("invalid terrain agent daemon module")
end

appendBootLog("boot: runLoop start")
local okRun, runErr = pcall(agentOrErr.runLoop)
if not okRun then
  appendBootLog("boot: runLoop crash err=" .. tostring(runErr))
  error(runErr)
end
