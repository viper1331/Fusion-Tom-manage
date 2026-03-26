local M = {}
local GpuSafe = assert(dofile("ui/helpers/gpu_safe.lua"))

local CALIBRATION = {
  centerXRatio = 0.438,
  centerYRatio = 0.458,
  compactScale = 0.82,
  microScale = 0.68,
  baseRadiusXRatio = 0.0098,
  baseRadiusYRatio = 0.0140,
}

local function pulseWave(frame, period)
  local safePeriod = math.max(2, tonumber(period) or 2)
  local t = frame % safePeriod
  local half = safePeriod / 2
  if t < half then
    return t / half
  end
  return (safePeriod - t) / half
end

local function clamp01(value)
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
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
  local production = tonumber(data and data.productionRate) or 0
  local plasma = tonumber(data and data.plasmaMK) or 0
  local caseMK = tonumber(data and data.caseMK) or 0

  if production >= 12000000 then
    return true
  end
  if plasma >= 120 then
    return true
  end
  if caseMK >= 10 then
    return true
  end
  return false
end

local function resolveCoreState(data)
  if not data or not data.formed then
    return "offline"
  end

  if isScramMode(data) then
    return "scram"
  end

  if not data.ignited then
    local relayPulse = data.relayStates and data.relayStates.laserCharge
    local ampPct = tonumber(data.laserAmplifierPct) or 0
    if relayPulse or ampPct >= 0.70 then
      return "ignition"
    end
    return "formed"
  end

  if hasWarning(data) then
    return "warning"
  end

  if isHighLoad(data) then
    return "high_load"
  end

  return "running"
end

local function drawSoftEllipse(args, cx, cy, radiusX, radiusY, color)
  local rx = math.max(1, math.floor(radiusX))
  local ry = math.max(1, math.floor(radiusY))
  for dy = -ry, ry do
    local yNorm = dy / ry
    local span = math.floor(rx * math.sqrt(math.max(0, 1 - (yNorm * yNorm))))
    if span > 0 then
      GpuSafe.filledRect(args, cx - span, cy + dy, span * 2 + 1, 1, color)
    end
  end
end

local function buildStateStyle(data, stateName, frame)
  local style = {
    outer = 0x18004A72,
    mid = 0x284FCBFF,
    inner = 0x44CFF6FF,
    core = 0xFFE7FBFF,
    spark = 0xFFB5F3FF,
    sparkCount = 4,
    pulsePeriod = 18,
    haloBoost = 1.00,
    flicker = 0.10,
  }

  if stateName == "offline" then
    style.outer = 0x08000000
    style.mid = 0x0E142235
    style.inner = 0x121F3148
    style.core = 0x30182430
    style.spark = 0x00000000
    style.sparkCount = 0
    style.pulsePeriod = 26
    style.haloBoost = 0.40
    style.flicker = 0.02
  elseif stateName == "formed" then
    style.outer = 0x0E1A2345
    style.mid = 0x16435E8A
    style.inner = 0x2471A8D5
    style.core = 0x886BBBEA
    style.spark = 0x6682D8FF
    style.sparkCount = 2
    style.pulsePeriod = 22
    style.haloBoost = 0.60
    style.flicker = 0.05
  elseif stateName == "ignition" then
    local ampPct = clamp01(tonumber(data and data.laserAmplifierPct) or 0)
    style.outer = 0x1C2A3A80
    style.mid = 0x2E4A6BCE
    style.inner = 0x5083D7FF
    style.core = 0xFFF6FDFF
    style.spark = 0xFFC8F4FF
    style.sparkCount = 5
    style.pulsePeriod = 12
    style.haloBoost = 0.85 + (ampPct * 0.55)
    style.flicker = 0.12 + (ampPct * 0.12)
  elseif stateName == "running" then
    style.outer = 0x1A302F8E
    style.mid = 0x2A568AE0
    style.inner = 0x568ADFFF
    style.core = 0xFFFFFFFF
    style.spark = 0xFFCCF6FF
    style.sparkCount = 5
    style.pulsePeriod = 14
    style.haloBoost = 1.00
    style.flicker = 0.14
  elseif stateName == "high_load" then
    style.outer = 0x224040AA
    style.mid = 0x344E84F0
    style.inner = 0x5E87E7FF
    style.core = 0xFFFFFFFF
    style.spark = 0xFFFFFFFF
    style.sparkCount = 7
    style.pulsePeriod = 10
    style.haloBoost = 1.28
    style.flicker = 0.18
  elseif stateName == "warning" then
    local unstable = ((frame * 13) % 9) / 9
    style.outer = 0x244A2A98
    style.mid = 0x2E6A50D6
    style.inner = 0x5A9FE8FF
    style.core = 0xFFF5FDFF
    style.spark = 0xFFE2F8FF
    style.sparkCount = 6
    style.pulsePeriod = 9
    style.haloBoost = 1.08 + (unstable * 0.30)
    style.flicker = 0.22
  elseif stateName == "scram" then
    local decay = 1 - (((frame * 3) % 16) / 16)
    style.outer = 0x120A1228
    style.mid = 0x1A162B52
    style.inner = 0x223E699A
    style.core = 0x883E8AC2
    style.spark = 0x553A86B6
    style.sparkCount = 2
    style.pulsePeriod = 7
    style.haloBoost = 0.32 + (decay * 0.38)
    style.flicker = 0.08
  end

  return style
end

function M.resolveState(data)
  return resolveCoreState(data)
end

function M.draw(args, x, y, w, h, data)
  local gpu = args.gpu
  if not gpu then
    return
  end

  local frame = (args.state and args.state.animTick) or 0
  local coreState = resolveCoreState(data)
  local style = buildStateStyle(data, coreState, frame)
  local ui = args.ui or {}
  local visual = args.state and args.state.visual

  local scale = 1.00
  if ui.micro then
    scale = CALIBRATION.microScale
  elseif ui.compact then
    scale = CALIBRATION.compactScale
  end
  if visual and visual.effectLevel == "lite" then
    scale = scale * 0.92
  elseif visual and visual.effectLevel == "minimal" then
    scale = scale * 0.80
  end

  local cx = x + math.floor(w * CALIBRATION.centerXRatio)
  local cy = y + math.floor(h * CALIBRATION.centerYRatio)

  local baseRadiusX = math.max(2, math.floor(w * CALIBRATION.baseRadiusXRatio * scale))
  local baseRadiusY = math.max(3, math.floor(h * CALIBRATION.baseRadiusYRatio * scale))
  local pulse = pulseWave(frame + 3, style.pulsePeriod)
  local drift = (((frame * 11) % 17) / 17) * style.flicker
  local haloFactor = (0.90 + (pulse * 0.18) + drift) * style.haloBoost

  local outerRx = math.max(3, math.floor(baseRadiusX * 2.30 * haloFactor))
  local outerRy = math.max(4, math.floor(baseRadiusY * 2.35 * haloFactor))
  local midRx = math.max(2, math.floor(baseRadiusX * 1.65 * haloFactor))
  local midRy = math.max(3, math.floor(baseRadiusY * 1.70 * haloFactor))
  local innerRx = math.max(2, math.floor(baseRadiusX * 1.20 * haloFactor))
  local innerRy = math.max(2, math.floor(baseRadiusY * 1.25 * haloFactor))

  drawSoftEllipse(args, cx, cy, outerRx, outerRy, style.outer)
  drawSoftEllipse(args, cx, cy, midRx, midRy, style.mid)
  drawSoftEllipse(args, cx, cy, innerRx, innerRy, style.inner)

  local coreRx = math.max(1, math.floor(innerRx * (ui.micro and 0.42 or 0.48)))
  local coreRy = math.max(1, math.floor(innerRy * (ui.micro and 0.45 or 0.52)))
  drawSoftEllipse(args, cx, cy, coreRx, coreRy, style.core)
  drawSoftEllipse(args, cx, cy - 1, math.max(1, coreRx - 1), math.max(1, coreRy - 1), 0xAAFFFFFF)

  if style.sparkCount > 0 then
    local sparkRadiusX = math.max(1, math.floor(innerRx * 1.08))
    local sparkRadiusY = math.max(1, math.floor(innerRy * 1.12))
    local sparkSize = ui.micro and 1 or 2
    if visual and visual.effectLevel == "lite" then
      sparkSize = 1
    end

    local sparkCount = style.sparkCount
    if visual and visual.effectLevel == "lite" then
      sparkCount = math.max(1, math.floor(sparkCount * 0.65))
    elseif visual and visual.effectLevel == "minimal" then
      sparkCount = math.max(0, math.floor(sparkCount * 0.35))
    end

    for i = 1, sparkCount do
      local angle = ((frame * 0.17) + (i * 0.92)) * 1.27
      local jitter = 0.75 + pulseWave(frame + (i * 3), style.pulsePeriod + i) * 0.45
      local sx = cx + math.floor(math.cos(angle) * sparkRadiusX * jitter)
      local sy = cy + math.floor(math.sin(angle) * sparkRadiusY * jitter)
      GpuSafe.filledRect(args, sx, sy, sparkSize, sparkSize, style.spark)
    end
  end

  if coreState == "warning" and (frame % 3 == 0) then
    drawSoftEllipse(args, cx, cy, math.max(2, coreRx + 1), math.max(2, coreRy + 1), 0x2AFFFFFF)
  elseif coreState == "ignition" and (frame % 4 <= 1) then
    drawSoftEllipse(args, cx, cy - 1, math.max(1, coreRx - 1), 1, 0x48FFFFFF)
  elseif coreState == "scram" then
    drawSoftEllipse(args, cx, cy + math.max(1, coreRy), math.max(1, coreRx - 1), 1, 0x402E5A84)
  end
end

return M
