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
      return false, "relay " .. tostring(key) .. " missing"
    end

    if not side then
      return false, "relay side missing for " .. tostring(key)
    end

    local ok = safeCall(relayName, "setOutput", side, enabled)
    if not ok then
      return false, "setOutput failed: " .. tostring(key)
    end

    safeCall(relayName, "setAnalogOutput", side, enabled and control.relayAnalogStrength or 0)
    state.live.relayStates[key] = enabled
    return true, (enabled and "enabled " or "disabled ") .. tostring(key)
  end

  local function pulseRelay(key, duration)
    local relayName = devices.relays[key]
    local side = relaySideConfigured(key)

    if not relayName then
      return false, "relay " .. tostring(key) .. " missing"
    end

    if not side then
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

    return okAny, table.concat(messages, " | ")
  end

  local function processPendingTimer(timerId)
    local pending = state.live.pendingTimers[timerId]
    if not pending then
      return false
    end

    state.live.pendingTimers[timerId] = nil
    setRelayState(pending.relayKey, false)
    return true
  end

  local function executeCommand(action)
    if action == "AUTO" then
      -- UI-only toggle: kept for operator workflows, not bound to reactor logic.
      state.auto = not state.auto
      state.message = state.auto and "ui-state only: auto flag enabled" or "ui-state only: auto flag disabled"
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
      return true
    end

    if action == "STOP" then
      local okFuel, msgFuel = openFuelFeed(false)
      if okFuel then
        state.message = "stop: " .. firstLine(msgFuel)
      else
        state.message = "stop blocked: relay sides not configured"
      end
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
      return true
    end

    if action == "FIRE_LASER" then
      local ok, msg = pulseRelay("laserCharge", control.laserPulseSeconds)
      state.message = ok and firstLine(msg) or ("laser blocked: " .. firstLine(msg))
      return true
    end

    if action == "FILL_HOHLRAUM" then
      state.message = "manual hohlraum required"
      return true
    end

    if action == "MANUAL_FUEL" then
      local target = not state.manualFuel
      local ok, msg = openFuelFeed(target)
      state.message = ok and firstLine(msg) or ("fuel blocked: " .. firstLine(msg))
      return true
    end

    if action == "MAINTENANCE" then
      state.maintenance = not state.maintenance
      state.message = state.maintenance and "maintenance enabled" or "maintenance disabled"
      return true
    end

    if action == "PROFILE_PREV" then
      -- UI-only selector: reserved for future ignition profile bindings.
      state.ignitionProfile = clamp(state.ignitionProfile - 1, 1, 5)
      state.message = "ui-state only: profile p" .. tostring(state.ignitionProfile)
      return true
    end

    if action == "PROFILE_NEXT" then
      state.ignitionProfile = clamp(state.ignitionProfile + 1, 1, 5)
      state.message = "ui-state only: profile p" .. tostring(state.ignitionProfile)
      return true
    end

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
