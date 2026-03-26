local M = {}

local function nowMs()
  if os.epoch then
    return os.epoch("utc")
  end

  return math.floor((os.clock() or 0) * 1000)
end

local function safeNumber(v, default)
  if type(v) == "number" then
    return v
  end
  return default or 0
end

local function safeBool(v)
  return v == true
end

local function formatCompactNumber(n, round)
  if type(n) ~= "number" then
    return tostring(n or "n/a")
  end

  local abs = math.abs(n)

  if abs >= 1e15 then
    return string.format("%.2fP", n / 1e15)
  elseif abs >= 1e12 then
    return string.format("%.2fT", n / 1e12)
  elseif abs >= 1e9 then
    return string.format("%.2fG", n / 1e9)
  elseif abs >= 1e6 then
    return string.format("%.2fM", n / 1e6)
  elseif abs >= 1e3 then
    return string.format("%.2fk", n / 1e3)
  end

  return tostring(round(n, 2))
end

local function formatRate(n, suffix, round)
  return formatCompactNumber(safeNumber(n, 0), round) .. (suffix or "")
end

local function formatEnergy(n, round)
  return formatCompactNumber(safeNumber(n, 0), round) .. " FE"
end

local function formatTemperatureMK(kelvin)
  local mk = safeNumber(kelvin, 0) / 1000000
  return mk, string.format("%.1f MK", mk)
end

function M.create(args)
  local devices = args.devices
  local control = args.control
  local state = args.state
  local colors = args.colors
  local clamp = args.clamp
  local round = args.round

  local wrappedCache = {}
  local modem = nil

  local function refreshWrapped(name)
    if type(name) ~= "string" or name == "" then
      return nil
    end

    local ok, obj = pcall(peripheral.wrap, name)
    if ok and obj then
      wrappedCache[name] = obj
      return obj
    end

    wrappedCache[name] = false
    return nil
  end

  local function getWrapped(name)
    local cached = wrappedCache[name]
    if cached == false then
      if peripheral.isPresent and peripheral.isPresent(name) then
        return refreshWrapped(name)
      end
      return nil
    end

    if cached then
      return cached
    end

    return refreshWrapped(name)
  end

  local function getModem()
    if modem then
      return modem
    end

    modem = getWrapped(devices.modem)
    if modem and type(modem.getNamesRemote) == "function" then
      return modem
    end

    modem = nil
    return nil
  end

  local function invalidateWrapped(name)
    if type(name) ~= "string" or name == "" then
      return
    end

    wrappedCache[name] = nil
  end

  local function safeCall(name, method, ...)
    if type(name) ~= "string" or name == "" then
      return false, "invalid device"
    end

    local obj = getWrapped(name)
    if obj and type(obj[method]) == "function" then
      local ok, result1, result2, result3, result4, result5 = pcall(obj[method], ...)
      if ok then
        return true, result1, result2, result3, result4, result5
      end
    end

    local back = getModem()
    if back and type(back.callRemote) == "function" then
      local ok, result1, result2, result3, result4, result5 = pcall(back.callRemote, name, method, ...)
      if ok then
        return true, result1, result2, result3, result4, result5
      end
    end

    return false, nil
  end

  local function devicePresent(name)
    if getWrapped(name) then
      return true
    end

    local back = getModem()
    if back and type(back.isPresentRemote) == "function" then
      local ok, result = pcall(back.isPresentRemote, name)
      if ok then
        return result == true
      end
    end

    return false
  end

  local function readReaderData(name)
    local ok, data = safeCall(name, "getBlockData")
    if not ok or type(data) ~= "table" then
      return {
        ok = false,
        present = devicePresent(name),
        amount = 0,
        amountText = "n/a",
        id = "n/a",
        active = false,
      }
    end

    local amount = 0
    local chemId = "n/a"

    if type(data.chemical_tanks) == "table" and type(data.chemical_tanks[1]) == "table" then
      local stored = data.chemical_tanks[1].stored
      if type(stored) == "table" then
        amount = safeNumber(stored.amount, 0)
        chemId = stored.id or chemId
      end
    end

    if amount == 0 and type(data.chemical_amount) == "number" then
      amount = data.chemical_amount
      chemId = data.chemical_id or chemId
    end

    local isCreative = amount >= 9e18
    local amountText = isCreative and "creative" or formatCompactNumber(amount, round)
    local active = (data.active_state == 1) or (data.active == true)

    return {
      ok = true,
      present = true,
      id = chemId,
      amount = amount,
      amountText = amountText,
      active = active,
      redstone = safeNumber(data.redstone, 0),
      currentRedstone = safeNumber(data.current_redstone, 0),
      raw = data,
    }
  end

  local function getHohlraumLoaded()
    local ok, item = safeCall(devices.logic, "getHohlraum")
    if ok and type(item) == "table" then
      local name = item.name or ""
      local count = safeNumber(item.count, 0)
      if name ~= "" and name ~= "minecraft:air" and count > 0 then
        return true
      end
    end

    local okList, items = safeCall(devices.fusionController, "list")
    if okList and type(items) == "table" then
      for _, item in pairs(items) do
        if type(item) == "table" and item.name == "mekanismgenerators:hohlraum" and safeNumber(item.count, 0) > 0 then
          return true
        end
      end
    end

    return false
  end

  local function buildAlerts(data)
    local alerts = {}

    if not data.logicPresent then
      alerts[#alerts + 1] = "logic adapter offline"
    end
    if not data.formed then
      alerts[#alerts + 1] = "structure invalid"
    end
    if data.formed and not data.hohlraumLoaded then
      alerts[#alerts + 1] = "hohlraum missing"
    end
    if data.formed and data.laserAmplifierPct < 0.2 then
      alerts[#alerts + 1] = "laser low"
    end
    if data.formed and data.dtPct < 5 and data.ignited then
      alerts[#alerts + 1] = "dt low"
    end
    if data.maintenance then
      alerts[#alerts + 1] = "maintenance"
    end

    if #alerts == 0 then
      return "none", alerts
    end

    return alerts[1], alerts
  end

  local function resolveStatus(data)
    if not data.logicPresent or not data.formed then
      return "OFFLINE", "OFFLINE / NOT FORMED"
    end

    if data.maintenance then
      return "WARNING", "FORMED / MAINTENANCE"
    end

    if data.ignited then
      if data.alerts ~= "none" then
        return "WARNING", "FORMED / ONLINE / CHECK"
      end
      return "STABLE", "FORMED / ONLINE / SAFE"
    end

    if data.hohlraumLoaded and data.laserAmplifierPct >= 0.99 then
      return "FORMED", "FORMED / READY / LASER"
    end

    return "FORMED", "FORMED / STANDBY"
  end

  local function pollLiveData(force)
    local now = nowMs()
    local pollIntervalMs = tonumber(control.telemetryPollMs) or 500
    if not force and state.live.cache and (now - state.live.lastPoll) < pollIntervalMs then
      return state.live.cache
    end

    local logicPresent = devicePresent(devices.logic)
    local inductionPresent = devicePresent(devices.induction)
    local amplifierPresent = devicePresent(devices.laserAmplifier)
    local laserPresent = devicePresent(devices.laser)

    local formed = false
    local ignited = false
    local logicMode = "OFFLINE"
    local injectionRate = 0
    local productionRate = 0
    local plasmaRaw = 0
    local caseRaw = 0

    local ok, value = safeCall(devices.logic, "isFormed")
    if ok then formed = safeBool(value) end

    ok, value = safeCall(devices.logic, "isIgnited")
    if ok then ignited = safeBool(value) end

    ok, value = safeCall(devices.logic, "getLogicMode")
    if ok then logicMode = tostring(value or "UNKNOWN") end

    ok, value = safeCall(devices.logic, "getInjectionRate")
    if ok then injectionRate = safeNumber(value, 0) end

    ok, value = safeCall(devices.logic, "getProductionRate")
    if ok then productionRate = safeNumber(value, 0) end

    ok, value = safeCall(devices.logic, "getPlasmaTemperature")
    if ok then plasmaRaw = safeNumber(value, 0) end

    ok, value = safeCall(devices.logic, "getCaseTemperature")
    if ok then caseRaw = safeNumber(value, 0) end

    local dtPct = 0
    local dPct = 0
    local tPct = 0
    local waterPct = 0
    local steamPct = 0
    local dtNeeded = 0
    local dNeeded = 0
    local tNeeded = 0
    local activeCooled = false
    local environmentalLoss = 0
    local transferLoss = 0

    ok, value = safeCall(devices.logic, "getDTFuelFilledPercentage")
    if ok then dtPct = safeNumber(value, 0) * 100 end

    ok, value = safeCall(devices.logic, "getDeuteriumFilledPercentage")
    if ok then dPct = safeNumber(value, 0) * 100 end

    ok, value = safeCall(devices.logic, "getTritiumFilledPercentage")
    if ok then tPct = safeNumber(value, 0) * 100 end

    ok, value = safeCall(devices.logic, "getWaterFilledPercentage")
    if ok then waterPct = safeNumber(value, 0) * 100 end

    ok, value = safeCall(devices.logic, "getSteamFilledPercentage")
    if ok then steamPct = safeNumber(value, 0) * 100 end

    ok, value = safeCall(devices.logic, "getDTFuelNeeded")
    if ok then dtNeeded = safeNumber(value, 0) end

    ok, value = safeCall(devices.logic, "getDeuteriumNeeded")
    if ok then dNeeded = safeNumber(value, 0) end

    ok, value = safeCall(devices.logic, "getTritiumNeeded")
    if ok then tNeeded = safeNumber(value, 0) end

    ok, value = safeCall(devices.logic, "isActiveCooledLogic")
    if ok then activeCooled = safeBool(value) end

    ok, value = safeCall(devices.logic, "getEnvironmentalLoss")
    if ok then environmentalLoss = safeNumber(value, 0) end

    ok, value = safeCall(devices.logic, "getTransferLoss")
    if ok then transferLoss = safeNumber(value, 0) end

    local energy = 0
    local energyMax = 0
    local energyPct = 0
    local lastInput = 0
    local lastOutput = 0
    local transferCap = 0
    local inductionMode = false
    local inductionFormed = false

    ok, value = safeCall(devices.induction, "getEnergy")
    if ok then energy = safeNumber(value, 0) end

    ok, value = safeCall(devices.induction, "getMaxEnergy")
    if ok then energyMax = safeNumber(value, 0) end

    ok, value = safeCall(devices.induction, "getEnergyFilledPercentage")
    if ok then energyPct = safeNumber(value, 0) * 100 end

    ok, value = safeCall(devices.induction, "getLastInput")
    if ok then lastInput = safeNumber(value, 0) end

    ok, value = safeCall(devices.induction, "getLastOutput")
    if ok then lastOutput = safeNumber(value, 0) end

    ok, value = safeCall(devices.induction, "getTransferCap")
    if ok then transferCap = safeNumber(value, 0) end

    ok, value = safeCall(devices.induction, "getMode")
    if ok then inductionMode = safeBool(value) end

    ok, value = safeCall(devices.induction, "isFormed")
    if ok then inductionFormed = safeBool(value) end

    local amplifierEnergy = 0
    local amplifierMax = 0
    local amplifierPct = 0
    local amplifierMode = "n/a"
    local amplifierDelay = 0

    ok, value = safeCall(devices.laserAmplifier, "getEnergy")
    if ok then amplifierEnergy = safeNumber(value, 0) end

    ok, value = safeCall(devices.laserAmplifier, "getMaxEnergy")
    if ok then amplifierMax = safeNumber(value, 0) end

    ok, value = safeCall(devices.laserAmplifier, "getEnergyFilledPercentage")
    if ok then amplifierPct = safeNumber(value, 0) end

    ok, value = safeCall(devices.laserAmplifier, "getRedstoneMode")
    if ok then amplifierMode = tostring(value or "n/a") end

    ok, value = safeCall(devices.laserAmplifier, "getDelay")
    if ok then amplifierDelay = safeNumber(value, 0) end

    local laserEnergy = 0
    local laserMax = 0
    local laserPct = 0

    ok, value = safeCall(devices.laser, "getEnergy")
    if ok then laserEnergy = safeNumber(value, 0) end

    ok, value = safeCall(devices.laser, "getMaxEnergy")
    if ok then laserMax = safeNumber(value, 0) end

    ok, value = safeCall(devices.laser, "getEnergyFilledPercentage")
    if ok then laserPct = safeNumber(value, 0) end

    local readerD = readReaderData(devices.readers.deuterium)
    local readerT = readReaderData(devices.readers.tritium)
    local readerDT = readReaderData(devices.readers.dtFuel)
    local readerActive = readReaderData(devices.readers.active)

    local plasmaMK, plasmaText = formatTemperatureMK(plasmaRaw)
    local caseMK, caseText = formatTemperatureMK(caseRaw)

    local data = {
      unitName = "FUSION REACTOR - UNIT 01",

      logicPresent = logicPresent,
      inductionPresent = inductionPresent,
      amplifierPresent = amplifierPresent,
      laserPresent = laserPresent,

      formed = formed,
      ignited = ignited,
      online = formed and ignited,
      maintenance = state.maintenance,

      logicMode = logicMode,
      injectionRateValue = injectionRate,
      injection = tostring(math.floor(injectionRate + 0.5)) .. " mB/t",
      productionRate = productionRate,
      productionText = formatRate(productionRate, " FE/t", round),

      plasmaRaw = plasmaRaw,
      plasmaMK = plasmaMK,
      plasmaText = plasmaText,

      caseRaw = caseRaw,
      caseMK = caseMK,
      caseText = caseText,

      energy = energy,
      energyMax = energyMax,
      energyPct = clamp(energyPct, 0, 100),
      energyText = formatEnergy(energy, round),
      energyMaxText = formatEnergy(energyMax, round),
      energyFlowIn = formatRate(lastInput, " FE/t", round),
      energyFlowOut = formatRate(lastOutput, " FE/t", round),
      transferCapText = formatRate(transferCap, " FE/t", round),
      inductionMode = inductionMode and "INPUT" or "OUTPUT",
      inductionFormed = inductionFormed,

      dPct = clamp(dPct, 0, 100),
      tPct = clamp(tPct, 0, 100),
      dtPct = clamp(dtPct, 0, 100),
      waterPct = clamp(waterPct, 0, 100),
      steamPct = clamp(steamPct, 0, 100),
      dNeeded = dNeeded,
      tNeeded = tNeeded,
      dtNeeded = dtNeeded,

      activeCooled = activeCooled,
      environmentalLossText = formatRate(environmentalLoss, " FE/t", round),
      transferLossText = formatRate(transferLoss, " FE/t", round),

      laserAmplifierEnergy = amplifierEnergy,
      laserAmplifierMax = amplifierMax,
      laserAmplifierPct = amplifierPct,
      laserAmplifierText = formatEnergy(amplifierEnergy, round),
      laserAmplifierMode = amplifierMode,
      laserAmplifierDelay = amplifierDelay,

      laserEnergy = laserEnergy,
      laserMax = laserMax,
      laserPct = laserPct,
      laserText = formatEnergy(laserEnergy, round),

      hohlraumLoaded = getHohlraumLoaded(),

      readers = {
        deuterium = readerD,
        tritium = readerT,
        dtFuel = readerDT,
        active = readerActive,
      },

      relayStates = state.live.relayStates,
      relayConfig = control.relaySides,
    }

    data.laserReady = amplifierPresent and amplifierPct >= 0.99
    data.activeReader = readerActive.active and "ACTIVE" or "IDLE"
    data.activeReaderColor = readerActive.active and colors.green or colors.muted

    data.alerts, data.alertList = buildAlerts(data)
    data.status, data.stateText = resolveStatus(data)

    state.live.cache = data
    state.live.lastPoll = now
    return data
  end

  return {
    safeCall = safeCall,
    pollLiveData = pollLiveData,
    invalidateWrapped = invalidateWrapped,
  }
end

return M
