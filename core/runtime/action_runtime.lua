local M = {}

local TERRAIN_ACTION_IDS = {
  START = true,
  STOP = true,
  SCRAM = true,
  FIRE_LASER = true,
  MANUAL_FUEL = true,
}

local UI_STATE_ACTION_IDS = {
  AUTO = true,
  FILL_HOHLRAUM = true,
  MAINTENANCE = true,
  PROFILE_PREV = true,
  PROFILE_NEXT = true,
}

function M.create(args)
  local devices = args.devices
  local control = args.control
  local state = args.state
  local safeCall = args.safeCall
  local firstLine = args.firstLine
  local clamp = args.clamp
  local logger = args.logger

  local function logWithLevel(level, category, message, context)
    if not logger then
      return
    end

    local method = string.lower(tostring(level or "info"))
    local fn = logger[method]
    if type(fn) == "function" then
      fn(category, message, context, "runtime")
      return
    end

    if type(logger.info) == "function" then
      logger.info(category, message, context, "runtime")
    end
  end

  local function classifyAction(action)
    if TERRAIN_ACTION_IDS[action] then
      return "terrain"
    end
    if UI_STATE_ACTION_IDS[action] then
      return "ui_state"
    end
    return "other"
  end

  local function relaySideConfigured(key)
    local side = control.relaySides[key]
    if type(side) == "string" and side ~= "" then
      return side
    end
    return nil
  end

  local function setRelayState(key, enabled)
    local relayName = devices.relays[key]
    local side = relaySideConfigured(key)

    if not relayName then
      logWithLevel("WARN", "ACTIONS", "relay missing", {
        relay = tostring(key),
        enabled = enabled == true,
      })
      return false, "relay " .. tostring(key) .. " missing"
    end

    if not side then
      logWithLevel("WARN", "ACTIONS", "relay side missing", {
        relay = tostring(key),
        device = tostring(relayName),
      })
      return false, "relay side missing for " .. tostring(key)
    end

    local ok = safeCall(relayName, "setOutput", side, enabled)
    if not ok then
      logWithLevel("ERROR", "ACTIONS", "relay setOutput failed", {
        relay = tostring(key),
        device = tostring(relayName),
        side = tostring(side),
        enabled = enabled == true,
      })
      return false, "setOutput failed: " .. tostring(key)
    end

    safeCall(relayName, "setAnalogOutput", side, enabled and control.relayAnalogStrength or 0)
    state.live.relayStates[key] = enabled
    logWithLevel("INFO", "ACTIONS", "relay state updated", {
      relay = tostring(key),
      device = tostring(relayName),
      side = tostring(side),
      enabled = enabled == true,
      analog = enabled and tonumber(control.relayAnalogStrength or 0) or 0,
    })
    return true, (enabled and "enabled " or "disabled ") .. tostring(key)
  end

  local function pulseRelay(key, duration)
    local relayName = devices.relays[key]
    local side = relaySideConfigured(key)

    if not relayName then
      logWithLevel("WARN", "ACTIONS", "pulse relay missing", {
        relay = tostring(key),
      })
      return false, "relay " .. tostring(key) .. " missing"
    end

    if not side then
      logWithLevel("WARN", "ACTIONS", "pulse relay side missing", {
        relay = tostring(key),
        device = tostring(relayName),
      })
      return false, "relay side missing for " .. tostring(key)
    end

    local ok, msg = setRelayState(key, true)
    if not ok then
      return false, msg
    end

    local timerId = os.startTimer(duration or control.laserPulseSeconds)
    state.live.pendingTimers[timerId] = {
      relayKey = key,
      side = side,
    }
    logWithLevel("INFO", "ACTIONS", "relay pulse scheduled", {
      relay = tostring(key),
      side = tostring(side),
      duration = tonumber(duration or control.laserPulseSeconds) or 0,
      timer = tostring(timerId),
    })
    return true, "pulse " .. tostring(key)
  end

  local function openFuelFeed(enable)
    local messages = {}
    local okAny = false

    local ok1, msg1 = setRelayState("deuteriumTank", enable)
    messages[#messages + 1] = firstLine(msg1)
    okAny = okAny or ok1

    local ok2, msg2 = setRelayState("tritiumTank", enable)
    messages[#messages + 1] = firstLine(msg2)
    okAny = okAny or ok2

    if enable and okAny then
      state.manualFuel = true
    elseif (not enable) and okAny then
      state.manualFuel = false
    end

    logWithLevel(okAny and "INFO" or "WARN", "ACTIONS", "fuel feed toggle", {
      enabled = enable == true,
      ok = okAny == true,
      detail = table.concat(messages, " | "),
    })

    return okAny, table.concat(messages, " | ")
  end

  local function processPendingTimer(timerId)
    local pending = state.live.pendingTimers[timerId]
    if not pending then
      return false
    end

    state.live.pendingTimers[timerId] = nil
    setRelayState(pending.relayKey, false)
    logWithLevel("INFO", "ACTIONS", "pending timer executed", {
      timer = tostring(timerId),
      relay = tostring(pending.relayKey),
      side = tostring(pending.side or "n/a"),
    })
    return true
  end

  local function executeCommand(action)
    local actionClass = classifyAction(action)
    logWithLevel("INFO", "ACTIONS", "action received", {
      action = tostring(action),
      class = tostring(actionClass),
    })

    if action == "AUTO" then
      -- UI-only toggle: kept for operator workflows, not bound to reactor logic.
      state.auto = not state.auto
      state.message = state.auto and "ui-state only: auto flag enabled" or "ui-state only: auto flag disabled"
      logWithLevel("INFO", "ACTIONS", "ui state toggled", {
        action = "AUTO",
        value = state.auto == true,
      })
      return true
    end

    if action == "START" then
      local okFuel, msgFuel = openFuelFeed(true)
      local okPulse, msgPulse = pulseRelay("laserCharge", control.laserPulseSeconds)

      if okFuel or okPulse then
        state.message = "start: " .. firstLine(msgFuel or "") .. " | " .. firstLine(msgPulse or "")
      else
        state.message = "start blocked: relay sides not configured"
      end
      logWithLevel((okFuel or okPulse) and "INFO" or "WARN", "ACTIONS", "start command processed", {
        okFuel = okFuel == true,
        okPulse = okPulse == true,
      })
      return true
    end

    if action == "STOP" then
      local okFuel, msgFuel = openFuelFeed(false)
      if okFuel then
        state.message = "stop: " .. firstLine(msgFuel)
      else
        state.message = "stop blocked: relay sides not configured"
      end
      logWithLevel(okFuel and "INFO" or "WARN", "ACTIONS", "stop command processed", {
        ok = okFuel == true,
      })
      return true
    end

    if action == "SCRAM" then
      local okFuel, msgFuel = openFuelFeed(false)
      local okLaser, msgLaser = setRelayState("laserCharge", false)
      if okFuel or okLaser then
        state.message = "scram: " .. firstLine(msgFuel or "") .. " | " .. firstLine(msgLaser or "")
      else
        state.message = "scram blocked: relay sides not configured"
      end
      logWithLevel((okFuel or okLaser) and "WARN" or "ERROR", "ACTIONS", "scram command processed", {
        okFuel = okFuel == true,
        okLaser = okLaser == true,
      })
      return true
    end

    if action == "FIRE_LASER" then
      local ok, msg = pulseRelay("laserCharge", control.laserPulseSeconds)
      state.message = ok and firstLine(msg) or ("laser blocked: " .. firstLine(msg))
      logWithLevel(ok and "INFO" or "WARN", "ACTIONS", "fire laser command processed", {
        ok = ok == true,
      })
      return true
    end

    if action == "FILL_HOHLRAUM" then
      state.message = "manual hohlraum required"
      logWithLevel("INFO", "ACTIONS", "hohlraum manual action requested")
      return true
    end

    if action == "MANUAL_FUEL" then
      local target = not state.manualFuel
      local ok, msg = openFuelFeed(target)
      state.message = ok and firstLine(msg) or ("fuel blocked: " .. firstLine(msg))
      logWithLevel(ok and "INFO" or "WARN", "ACTIONS", "manual fuel command processed", {
        enabled = target == true,
        ok = ok == true,
      })
      return true
    end

    if action == "MAINTENANCE" then
      state.maintenance = not state.maintenance
      state.message = state.maintenance and "maintenance enabled" or "maintenance disabled"
      logWithLevel("INFO", "ACTIONS", "maintenance toggled", {
        enabled = state.maintenance == true,
      })
      return true
    end

    if action == "PROFILE_PREV" then
      -- UI-only selector: reserved for future ignition profile bindings.
      state.ignitionProfile = clamp(state.ignitionProfile - 1, 1, 5)
      state.message = "ui-state only: profile p" .. tostring(state.ignitionProfile)
      logWithLevel("INFO", "ACTIONS", "ignition profile changed", {
        direction = "prev",
        profile = tonumber(state.ignitionProfile) or 0,
      })
      return true
    end

    if action == "PROFILE_NEXT" then
      state.ignitionProfile = clamp(state.ignitionProfile + 1, 1, 5)
      state.message = "ui-state only: profile p" .. tostring(state.ignitionProfile)
      logWithLevel("INFO", "ACTIONS", "ignition profile changed", {
        direction = "next",
        profile = tonumber(state.ignitionProfile) or 0,
      })
      return true
    end

    logWithLevel("DEBUG", "ACTIONS", "action ignored", {
      action = tostring(action),
    })
    return false
  end

  return {
    classifyAction = classifyAction,
    relaySideConfigured = relaySideConfigured,
    setRelayState = setRelayState,
    pulseRelay = pulseRelay,
    openFuelFeed = openFuelFeed,
    processPendingTimer = processPendingTimer,
    executeCommand = executeCommand,
  }
end

return M
