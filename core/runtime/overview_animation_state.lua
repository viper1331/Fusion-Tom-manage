local M = {}

local GAS_ORDER = {
  "tritium",
  "dtFuel",
  "deuterium",
}

local function toNumber(value, fallback)
  local n = tonumber(value)
  if n == nil then
    return fallback
  end
  return n
end

local function isReaderOpen(reader)
  if type(reader) ~= "table" or reader.ok ~= true then
    return nil, nil
  end

  if type(reader.active) == "boolean" then
    return reader.active, "active"
  end
  if type(reader.currentRedstone) == "number" then
    return reader.currentRedstone > 0, "currentRedstone"
  end
  if type(reader.redstone) == "number" then
    return reader.redstone > 0, "redstone"
  end
  if type(reader.amount) == "number" then
    return reader.amount > 0, "amount"
  end

  return nil, nil
end

local function resolveGasOpenState(data, key)
  local readers = type(data) == "table" and data.readers or nil
  local relayStates = type(data) == "table" and data.relayStates or nil

  if key == "tritium" then
    local open, source = isReaderOpen(readers and readers.tritium)
    if open ~= nil then
      return open, "reader.tritium." .. tostring(source)
    end
    if relayStates and relayStates.tritiumTank ~= nil then
      return relayStates.tritiumTank == true, "relay.tritiumTank"
    end
    return toNumber(data and data.tPct, 0) > 0.1, "inference.tPct"
  end

  if key == "deuterium" then
    local open, source = isReaderOpen(readers and readers.deuterium)
    if open ~= nil then
      return open, "reader.deuterium." .. tostring(source)
    end
    if relayStates and relayStates.deuteriumTank ~= nil then
      return relayStates.deuteriumTank == true, "relay.deuteriumTank"
    end
    return toNumber(data and data.dPct, 0) > 0.1, "inference.dPct"
  end

  local open, source = isReaderOpen(readers and readers.dtFuel)
  if open ~= nil then
    return open, "reader.dtFuel." .. tostring(source)
  end

  local triRelay = relayStates and relayStates.tritiumTank == true
  local deuRelay = relayStates and relayStates.deuteriumTank == true
  if relayStates and (relayStates.tritiumTank ~= nil or relayStates.deuteriumTank ~= nil) then
    return triRelay and deuRelay, "inference.relayPair"
  end

  local injection = toNumber(data and data.injectionRateValue, 0)
  local dtPct = toNumber(data and data.dtPct, 0)
  local ignited = data and data.ignited == true
  return ((ignited and dtPct > 0.1) or injection > 0), "inference.dtPct|injection"
end

local function hasWarning(data)
  if not data then
    return false
  end
  if data.status == "WARNING" then
    return true
  end
  return data.alerts and data.alerts ~= "none"
end

local function isScramMode(data)
  local mode = string.lower(tostring(data and data.logicMode or ""))
  return string.find(mode, "scram", 1, true) ~= nil
end

local function isHighLoad(data)
  local production = toNumber(data and data.productionRate, 0)
  local plasma = toNumber(data and data.plasmaMK, 0)
  local caseMK = toNumber(data and data.caseMK, 0)
  return production >= 12000000 or plasma >= 120 or caseMK >= 10
end

local function resolveCoreState(data)
  if not data or not data.logicPresent or not data.formed then
    return "off", "not_formed"
  end

  if isScramMode(data) then
    return "scram", "logic_mode_scram"
  end

  if not data.ignited then
    local relayPulse = data.relayStates and data.relayStates.laserCharge == true
    local ampPct = toNumber(data.laserAmplifierPct, 0)
    if relayPulse or ampPct >= 0.75 then
      return "ignition", relayPulse and "relay.laserCharge" or "amplifier_pct"
    end
    return "off", "not_ignited"
  end

  if hasWarning(data) then
    return "warning", "warning_state"
  end
  if isHighLoad(data) then
    return "high_load", "high_load"
  end
  return "running", "ignited"
end

local function resolveElectricState(data)
  if not data or not data.formed then
    return "off", "not_formed"
  end

  if data.relayStates and data.relayStates.laserCharge == true then
    return "firing", "relay.laserCharge"
  end

  local ampPct = toNumber(data.laserAmplifierPct, 0)
  local energyPct = toNumber(data.energyPct, 0)
  local laserReady = data and data.laserReady == true
  local inductionReady = data and data.inductionPresent and data.inductionFormed

  if laserReady or ampPct >= 0.99 then
    return "ready", laserReady and "laserReady" or "amplifier_pct"
  end

  if ampPct >= 0.08 or energyPct >= 5 or inductionReady then
    return "charging", ampPct >= 0.08 and "amplifier_pct" or (energyPct >= 5 and "induction_energy_pct" or "induction_formed")
  end

  if data.ignited then
    return "running", "ignited_low_charge"
  end

  return "idle", "formed_idle"
end

function M.resolveContext(data)
  local gas = {}
  for _, key in ipairs(GAS_ORDER) do
    local open, source = resolveGasOpenState(data, key)
    gas[key] = {
      open = open == true,
      source = source or "n/a",
    }
  end

  local coreState, coreReason = resolveCoreState(data)
  local electricState, electricReason = resolveElectricState(data)

  return {
    core = {
      state = coreState,
      reason = coreReason,
      formed = data and data.formed == true,
      ignited = data and data.ignited == true,
      plasmaMK = toNumber(data and data.plasmaMK, 0),
      status = tostring(data and data.status or "n/a"),
      alerts = tostring(data and data.alerts or "n/a"),
    },
    electric = {
      state = electricState,
      reason = electricReason,
      energyPct = toNumber(data and data.energyPct, 0),
      amplifierPct = toNumber(data and data.laserAmplifierPct, 0),
      laserReady = data and data.laserReady == true,
      ignited = data and data.ignited == true,
      inductionPresent = data and data.inductionPresent == true,
      inductionFormed = data and data.inductionFormed == true,
    },
    gas = gas,
  }
end

return M
