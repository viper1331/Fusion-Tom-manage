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
  return cfg
end

if fs.exists("terrain/boot.lua") then
  local cfg = resolveTerrainAgentConfig()
  if cfg.enabled == true and cfg.autoStart ~= false and shell and type(shell.run) == "function" then
    shell.run("terrain/boot.lua")
  end
end
