local M = {}

local OVERVIEW_VALIDATION_SCENARIOS = {
  offline = {
    logicPresent = false,
    formed = false,
    ignited = false,
    status = "OFFLINE",
    stateText = "OFFLINE / NOT FORMED",
    logicMode = "OFFLINE",
    alerts = "logic adapter offline",
    productionRate = 0,
    caseMK = 0.2,
    plasmaMK = 0.3,
    dtPct = 0.0,
    dPct = 0.0,
    tPct = 0.0,
    laserAmplifierPct = 0.0,
    hohlraumLoaded = false,
    flow = { tritium = false, dtFuel = false, deuterium = false },
  },
  formed = {
    logicPresent = true,
    formed = true,
    ignited = false,
    status = "FORMED",
    stateText = "FORMED / STANDBY",
    logicMode = "STANDBY",
    alerts = "none",
    productionRate = 0,
    caseMK = 4.2,
    plasmaMK = 8.7,
    dtPct = 1.5,
    dPct = 12.0,
    tPct = 10.0,
    laserAmplifierPct = 0.35,
    hohlraumLoaded = true,
    flow = { tritium = false, dtFuel = false, deuterium = false },
  },
  ignited = {
    logicPresent = true,
    formed = true,
    ignited = true,
    status = "STABLE",
    stateText = "FORMED / ONLINE / SAFE",
    logicMode = "IGNITION",
    alerts = "none",
    productionRate = 2200000,
    caseMK = 22.4,
    plasmaMK = 74.8,
    dtPct = 42.0,
    dPct = 61.0,
    tPct = 58.0,
    laserAmplifierPct = 1.0,
    hohlraumLoaded = true,
    flow = { tritium = true, dtFuel = true, deuterium = true },
  },
  running = {
    logicPresent = true,
    formed = true,
    ignited = true,
    status = "STABLE",
    stateText = "FORMED / ONLINE / SAFE",
    logicMode = "RUNNING",
    alerts = "none",
    productionRate = 9800000,
    caseMK = 39.6,
    plasmaMK = 112.4,
    dtPct = 74.0,
    dPct = 77.0,
    tPct = 79.0,
    laserAmplifierPct = 0.92,
    hohlraumLoaded = true,
    flow = { tritium = true, dtFuel = true, deuterium = true },
  },
  warning = {
    logicPresent = true,
    formed = true,
    ignited = true,
    status = "WARNING",
    stateText = "FORMED / ONLINE / CHECK",
    logicMode = "RUNNING",
    alerts = "dt low",
    productionRate = 6400000,
    caseMK = 44.1,
    plasmaMK = 129.3,
    dtPct = 2.3,
    dPct = 38.0,
    tPct = 33.0,
    laserAmplifierPct = 0.82,
    hohlraumLoaded = true,
    flow = { tritium = true, dtFuel = false, deuterium = true },
  },
  scram = {
    logicPresent = true,
    formed = true,
    ignited = false,
    status = "SCRAM",
    stateText = "FORMED / SCRAM",
    logicMode = "SCRAM",
    alerts = "scram active",
    productionRate = 0,
    caseMK = 18.9,
    plasmaMK = 52.0,
    dtPct = 0.5,
    dPct = 8.0,
    tPct = 7.0,
    laserAmplifierPct = 0.0,
    hohlraumLoaded = false,
    flow = { tritium = false, dtFuel = false, deuterium = false },
  },
}

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[k] = deepCopy(v)
  end
  return out
end

local function nonEmptyString(value)
  if type(value) ~= "string" then
    return nil
  end
  if string.find(value, "%S") then
    return value
  end
  return nil
end

function M.normalizeSource(value)
  local raw = string.lower(nonEmptyString(value) or "")
  if raw == "simulate" or raw == "simulated" or raw == "simulation" then
    return "simulate"
  end
  return "terrain"
end

function M.normalizeScenario(value)
  local raw = string.lower(nonEmptyString(value) or "")
  if raw == "formed" then
    return "formed"
  end
  if raw == "ignited" then
    return "ignited"
  end
  if raw == "running" then
    return "running"
  end
  if raw == "warning" then
    return "warning"
  end
  if raw == "scram" then
    return "scram"
  end
  return "offline"
end

local function formatValidationMkText(value)
  return string.format("%.1f MK", tonumber(value) or 0)
end

function M.applyScenario(baseData, scenario, options)
  local profile = OVERVIEW_VALIDATION_SCENARIOS[M.normalizeScenario(scenario)] or OVERVIEW_VALIDATION_SCENARIOS.offline
  local data = deepCopy(baseData or {})
  local flow = profile.flow or {}
  local colors = type(options) == "table" and options.colors or nil

  data.logicPresent = profile.logicPresent == true
  data.formed = profile.formed == true
  data.ignited = profile.ignited == true
  data.online = data.formed and data.ignited
  data.status = profile.status
  data.stateText = profile.stateText
  data.logicMode = profile.logicMode
  data.alerts = profile.alerts
  data.alertList = (profile.alerts == "none") and {} or { profile.alerts }
  data.productionRate = tonumber(profile.productionRate) or 0
  data.productionText = tostring(math.floor((data.productionRate or 0) + 0.5)) .. " FE/t"
  data.caseMK = tonumber(profile.caseMK) or 0
  data.plasmaMK = tonumber(profile.plasmaMK) or 0
  data.caseRaw = data.caseMK * 1000000
  data.plasmaRaw = data.plasmaMK * 1000000
  data.caseText = formatValidationMkText(data.caseMK)
  data.plasmaText = formatValidationMkText(data.plasmaMK)
  data.dtPct = tonumber(profile.dtPct) or 0
  data.dPct = tonumber(profile.dPct) or 0
  data.tPct = tonumber(profile.tPct) or 0
  data.laserAmplifierPct = tonumber(profile.laserAmplifierPct) or 0
  data.laserReady = data.laserAmplifierPct >= 0.99
  data.hohlraumLoaded = profile.hohlraumLoaded == true
  data.maintenance = false

  data.readers = type(data.readers) == "table" and data.readers or {}
  local function assignReader(reader, isOpen, pctValue)
    local out = type(reader) == "table" and reader or {}
    out.ok = true
    out.active = isOpen
    out.amount = isOpen and math.max(1, math.floor((pctValue or 0) * 10)) or 0
    out.currentRedstone = isOpen and 15 or 0
    out.redstone = isOpen and 15 or 0
    return out
  end
  data.readers.tritium = assignReader(data.readers.tritium, flow.tritium == true, data.tPct)
  data.readers.dtFuel = assignReader(data.readers.dtFuel, flow.dtFuel == true, data.dtPct)
  data.readers.deuterium = assignReader(data.readers.deuterium, flow.deuterium == true, data.dPct)
  data.readers.active = type(data.readers.active) == "table" and data.readers.active or {}
  data.readers.active.ok = true
  data.readers.active.active = data.ignited

  local green = colors and colors.green or 0xFF4FE070
  local muted = colors and colors.muted or 0xFF8A8A8A
  data.activeReader = data.readers.active.active and "ACTIVE" or "IDLE"
  data.activeReaderColor = data.readers.active.active and green or muted

  data.relayStates = type(data.relayStates) == "table" and data.relayStates or {}
  data.relayStates.tritiumTank = flow.tritium == true
  data.relayStates.deuteriumTank = flow.deuterium == true
  data.relayStates.laserCharge = false
  data.relayStates.aux = false

  return data
end

return M