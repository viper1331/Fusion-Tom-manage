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

local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return tostring(os.epoch and os.epoch("utc") or 0)
end

local function appendTerrainStartupLog(message)
  local fh = fs.open("/terrain_agent.startup.log", "a")
  if not fh then
    return
  end
  fh.writeLine("[" .. nowText() .. "] " .. tostring(message))
  fh.close()
end

local function resolveTerrainAgentConfig()
  local defaults = readLuaTable("terrain/agent_config.lua")
  local fusion = readLuaTable("fusion_config.lua")
  local fromFusion = type(fusion.terrainAgent) == "table" and fusion.terrainAgent or {}
  local cfg = mergeTable(defaults, fromFusion)
  if cfg.enabled == nil then
    cfg.enabled = false
  end
  if cfg.autoStart == nil then
    cfg.autoStart = true
  end
  local mode = string.lower(tostring(cfg.runtimeMode or ""))
  if mode ~= "daemon" and mode ~= "runtime_gated" then
    mode = "runtime_gated"
  end
  cfg.runtimeMode = mode
  return cfg
end

if fs.exists("terrain/boot.lua") then
  local cfg = resolveTerrainAgentConfig()
  appendTerrainStartupLog("startup: terrain boot present, enabled=" .. tostring(cfg.enabled) .. " autoStart=" .. tostring(cfg.autoStart) .. " mode=" .. tostring(cfg.runtimeMode))
  if cfg.enabled == true and cfg.autoStart ~= false and cfg.runtimeMode == "daemon" and shell and type(shell.run) == "function" then
    local ok, err = pcall(shell.run, "terrain/boot.lua")
    appendTerrainStartupLog("startup: terrain boot launch=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
  elseif cfg.enabled == true and cfg.runtimeMode == "runtime_gated" then
    appendTerrainStartupLog("startup: runtime-gated mode, boot daemon deferred to start.lua runtime")
  else
    appendTerrainStartupLog("startup: terrain daemon not launched")
  end
else
  appendTerrainStartupLog("startup: terrain/boot.lua missing")
end
