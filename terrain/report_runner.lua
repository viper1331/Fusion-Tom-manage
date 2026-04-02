local Harness = assert(dofile("terrain/harness.lua"))

local Runner = {}

local function readConfig()
  local ok, cfg = pcall(dofile, "fusion_config.lua")
  if ok and type(cfg) == "table" then
    return cfg
  end
  return {}
end

local function collectNamesBySubstring(token)
  local out = {}
  local names = peripheral.getNames()
  table.sort(names)
  for _, name in ipairs(names) do
    if string.find(name, token, 1, true) then
      out[#out + 1] = name
    end
  end
  return out
end

local function buildContext(overrides)
  local cfg = readConfig()
  overrides = type(overrides) == "table" and overrides or {}
  return {
    cfg = cfg,
    expectedVersion = overrides.expectedVersion,
    tmGpuNames = collectNamesBySubstring("tm_gpu"),
    monitorNames = collectNamesBySubstring("monitor"),
  }
end

local function runSuiteFile(path, harness, context)
  local ok, suiteOrErr = pcall(dofile, path)
  if not ok then
    harness:fail("suite_load:" .. path, tostring(suiteOrErr))
    return false
  end

  if type(suiteOrErr) ~= "table" or type(suiteOrErr.run) ~= "function" then
    harness:fail("suite_shape:" .. path, "suite invalid")
    return false
  end

  local success, err = pcall(suiteOrErr.run, harness, context)
  if not success then
    harness:fail("suite_run:" .. path, tostring(err))
    return false
  end

  return true
end

function Runner.runAll(overrides)
  local context = buildContext(overrides)
  local harness = Harness.new("terrain_auto", "Fusion-Tom-manage")
  local suites = {
    "terrain/suites/smoke.lua",
    "terrain/suites/update_validation.lua",
    "terrain/suites/peripherals.lua",
  }

  for _, path in ipairs(suites) do
    runSuiteFile(path, harness, context)
  end

  return harness:finish({
    expectedVersion = context.expectedVersion,
    tmGpuCount = #context.tmGpuNames,
    monitorCount = #context.monitorNames,
  })
end

return Runner
