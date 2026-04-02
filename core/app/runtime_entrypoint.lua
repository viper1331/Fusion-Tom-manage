local M = {}

local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return tostring(os.epoch and os.epoch("utc") or 0)
end

local function appendStartupLog(message)
  local fh = fs.open("/terrain_agent.startup.log", "a")
  if not fh then
    return
  end
  fh.writeLine("[" .. nowText() .. "] " .. tostring(message))
  fh.close()
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

local function resolveTerrainConfig(configPath, defaultsPath)
  local defaults = readLuaTable(defaultsPath or "terrain/agent_config.lua")
  local fusion = readLuaTable(configPath or "fusion_config.lua")
  local fromFusion = type(fusion.terrainAgent) == "table" and fusion.terrainAgent or {}
  local cfg = mergeTable(defaults, fromFusion)
  cfg.enabled = cfg.enabled == true
  cfg.autoStart = cfg.autoStart ~= false
  cfg.runtimeMode = normalizeRuntimeMode(cfg.runtimeMode)
  return cfg
end

local function runScript(path, args)
  args = type(args) == "table" and args or {}
  if shell and type(shell.run) == "function" then
    return shell.run(path, unpack(args))
  end
  return dofile(path)
end

function M.run(args)
  args = type(args) == "table" and args or {}
  local entrypoint = tostring(args.entrypoint or "start_menu_pages_live_v7_impl.lua")
  local terrainBoot = tostring(args.terrainBoot or "terrain/boot.lua")

  local terrainCfg = resolveTerrainConfig(args.configPath, args.defaultsPath)
  appendStartupLog("entrypoint: launch mode=" .. tostring(terrainCfg.runtimeMode) .. " enabled=" .. tostring(terrainCfg.enabled))

  if terrainCfg.enabled == true and terrainCfg.runtimeMode == "runtime_gated" then
    appendStartupLog("entrypoint: runtime-gated mode active")
    local terrainDelay = math.max(1, tonumber(terrainCfg.pollSeconds) or 5)

    local function runFusion()
      local ok, err = pcall(runScript, entrypoint, {})
      appendStartupLog("entrypoint: fusion stop ok=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(err))))
      if not ok then
        error(err)
      end
    end

    local function runTerrainWorker()
      appendStartupLog("entrypoint: terrain worker start")
      while true do
        local ok, bootErr = pcall(runScript, terrainBoot, { "--hosted" })
        appendStartupLog("entrypoint: terrain worker cycle ok=" .. tostring(ok) .. (ok and "" or (" err=" .. tostring(bootErr))))
        sleep(math.min(terrainDelay, 2))
      end
    end

    parallel.waitForAny(runFusion, runTerrainWorker)
    return
  end

  appendStartupLog("entrypoint: fusion standalone mode")
  runScript(entrypoint, {})
end

return M
