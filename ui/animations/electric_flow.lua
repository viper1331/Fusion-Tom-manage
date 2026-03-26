local M = {}

local function pulseWave(frame, period)
  local safePeriod = math.max(2, tonumber(period) or 2)
  local t = frame % safePeriod
  local half = safePeriod / 2
  if t < half then
    return t / half
  end
  return (safePeriod - t) / half
end

local function resolveAnimationMode(data)
  if not data or not data.formed then
    return "offline"
  end

  local relayPulse = data.relayStates and data.relayStates.laserCharge
  local ampPct = tonumber(data.laserAmplifierPct) or 0
  local inductionActive = (data.inductionPresent and data.inductionFormed) or (data.readers and data.readers.active and data.readers.active.active)

  if relayPulse then
    return "firing"
  end

  if not data.ignited then
    if data.hohlraumLoaded and ampPct >= 0.99 then
      return "ready"
    end

    if inductionActive and ampPct > 0.05 and ampPct < 0.99 then
      return "charging"
    end

    return "standby"
  end

  if inductionActive and ampPct < 0.95 then
    return "charging"
  end

  return "running"
end

local function resolveDensity(ui)
  if ui and ui.micro then
    return 0.50
  end
  if ui and ui.compact then
    return 0.75
  end
  return 1.00
end

local function resolveFlowIntensity(data, mode)
  local base = 0.35
  if mode == "standby" then
    base = 0.30
  elseif mode == "charging" then
    base = 0.78
  elseif mode == "ready" then
    base = 0.92
  elseif mode == "firing" then
    base = 1.25
  elseif mode == "running" then
    base = 0.56
  end

  local ampPct = tonumber(data and data.laserAmplifierPct) or 0
  local production = tonumber(data and data.productionRate) or 0
  local plasma = tonumber(data and data.plasmaMK) or 0

  base = base + math.min(0.20, ampPct * 0.20)
  base = base + math.min(0.16, production / 18000000)
  base = base + math.min(0.18, plasma / 220)

  if data and data.alerts and data.alerts ~= "none" then
    base = base * 0.90
  end

  if base < 0.16 then
    return 0.16
  end
  if base > 1.45 then
    return 1.45
  end
  return base
end

local function getFlowStyle(mode)
  local style = {
    baseGlow = 0x12006892,
    particle = 0xFF6EDFFF,
    trail = 0x665BCFFF,
    marker = 0x667CD9FF,
    speed = 10,
    count = 2,
  }

  if mode == "standby" then
    style.baseGlow = 0x10005070
    style.particle = 0xAA58BFE8
    style.trail = 0x4450A4CC
    style.marker = 0x3358B5E0
    style.speed = 8
    style.count = 1
  elseif mode == "charging" then
    style.baseGlow = 0x1A00A0D8
    style.particle = 0xFF7CEAFF
    style.trail = 0x6674DFFF
    style.marker = 0x6687EDFF
    style.speed = 14
    style.count = 3
  elseif mode == "ready" then
    style.baseGlow = 0x1840D8FF
    style.particle = 0xFFE7FBFF
    style.trail = 0x66A8EEFF
    style.marker = 0x88C6F4FF
    style.speed = 16
    style.count = 2
  elseif mode == "firing" then
    style.baseGlow = 0x28D5F5FF
    style.particle = 0xFFFFFFFF
    style.trail = 0x88D8F6FF
    style.marker = 0xAAFFFFFF
    style.speed = 22
    style.count = 4
  elseif mode == "running" then
    style.baseGlow = 0x1200709F
    style.particle = 0xFF76D8F5
    style.trail = 0x5579C9E8
    style.marker = 0x4477C7E2
    style.speed = 11
    style.count = 2
  end

  return style
end

local function drawHorizontalParticleFlow(args, spec)
  local x1 = spec.x1
  local x2 = spec.x2
  if x2 < x1 then
    x1, x2 = x2, x1
  end

  local mode = spec.mode
  if mode == "offline" then
    return
  end

  local thickness = math.max(1, spec.thickness or 1)
  local y = spec.y
  local reverse = spec.reverse == true
  local gpu = args.gpu
  local frame = (args.state and args.state.animTick) or 0
  local density = resolveDensity(args.ui)
  local intensity = spec.intensity or 1
  local style = getFlowStyle(mode)

  local lineW = math.max(1, x2 - x1 + 1)
  gpu.filledRectangle(x1, y - math.floor(thickness / 2), lineW, thickness, style.baseGlow)

  local travel = math.max(4, x2 - x1)
  local packetW = math.max(1, math.floor(thickness * (args.ui and args.ui.micro and 0.75 or 0.95)))
  local packetH = math.max(1, thickness)
  local trailSteps = (args.ui and args.ui.micro) and 1 or 2
  local trailStep = math.max(1, math.floor(packetW * 0.90))
  local speed = math.max(1, math.floor(style.speed * intensity))
  local count = math.max(1, math.floor(style.count * density + 0.5))

  for i = 1, count do
    local stride = math.max(3, math.floor(travel / count))
    local phase = ((frame * speed) + (i * stride)) % travel
    local px = reverse and (x2 - phase) or (x1 + phase)
    local py = y - math.floor(packetH / 2)
    local direction = reverse and 1 or -1

    for t = trailSteps, 1, -1 do
      local tx = px + (direction * t * trailStep)
      if tx >= x1 and tx <= x2 then
        gpu.filledRectangle(tx, py, packetW, packetH, style.trail)
      end
    end

    gpu.filledRectangle(px, py, packetW, packetH, style.particle)

    if mode == "firing" and ((frame + i) % 2 == 0) then
      gpu.filledRectangle(px, py, math.max(1, packetW - 1), math.max(1, packetH - 1), 0xCCFFFFFF)
    end
  end

  if mode == "ready" or mode == "running" then
    if (math.floor(frame / 5) % 2) == 0 then
      local mx = reverse and x1 or x2
      gpu.filledRectangle(mx - 1, y - 2, 4, 5, style.marker)
    end
  elseif mode == "firing" and (frame % 3 == 0) then
    gpu.filledRectangle(x1, y - math.max(1, math.floor(thickness / 2)), lineW, math.max(1, thickness + 1), 0x30FFFFFF)
  end
end

local function drawVerticalParticleFlow(args, spec)
  local y1 = spec.y1
  local y2 = spec.y2
  if y2 < y1 then
    y1, y2 = y2, y1
  end

  local mode = spec.mode
  if mode == "offline" then
    return
  end

  local x = spec.x
  local thickness = math.max(1, spec.thickness or 1)
  local reverse = spec.reverse == true
  local gpu = args.gpu
  local frame = (args.state and args.state.animTick) or 0
  local density = resolveDensity(args.ui)
  local intensity = spec.intensity or 1
  local style = getFlowStyle(mode)

  local baseGlow = spec.glow or style.baseGlow
  local packetColor = spec.color or style.particle
  local trailColor = spec.trail or style.trail
  local speed = math.max(1, math.floor((spec.speed or style.speed) * intensity))
  local count = math.max(1, math.floor((spec.count or style.count) * density + 0.5))

  local lineH = math.max(1, y2 - y1 + 1)
  gpu.filledRectangle(x - math.floor(thickness / 2), y1, thickness, lineH, baseGlow)

  local travel = math.max(4, y2 - y1)
  local packetW = math.max(1, thickness)
  local packetH = math.max(2, math.floor(thickness * (args.ui and args.ui.micro and 1.1 or 1.5)))
  local trailSteps = (args.ui and args.ui.micro) and 1 or 2
  local trailStep = math.max(1, packetH)

  for i = 1, count do
    local stride = math.max(3, math.floor(travel / count))
    local phase = ((frame * speed) + (i * stride)) % travel
    local py = reverse and (y2 - phase) or (y1 + phase)
    local px = x - math.floor(packetW / 2)
    local direction = reverse and 1 or -1

    for t = trailSteps, 1, -1 do
      local ty = py + (direction * t * trailStep)
      if ty >= y1 and ty <= y2 then
        gpu.filledRectangle(px, ty, packetW, packetH, trailColor)
      end
    end

    gpu.filledRectangle(px, py, packetW, packetH, packetColor)
  end
end

function M.resolveMode(data)
  return resolveAnimationMode(data)
end

function M.drawModuleFlux(args, x, y, w, h, data)
  local mode = resolveAnimationMode(data)
  if mode == "offline" then
    return
  end

  local cableY = y + math.floor(h * 0.50)
  local thickness = math.max(2, math.floor(h * 0.12))
  local intensity = resolveFlowIntensity(data, mode)

  local leftOuter = x + math.floor(w * 0.095)
  local leftInner = x + math.floor(w * 0.295)
  local rightInner = x + math.floor(w * 0.695)
  local rightOuter = x + math.floor(w * 0.900)

  drawHorizontalParticleFlow(args, {
    x1 = leftOuter,
    x2 = leftInner,
    y = cableY,
    thickness = thickness,
    mode = mode,
    reverse = false,
    intensity = intensity,
  })

  drawHorizontalParticleFlow(args, {
    x1 = rightInner,
    x2 = rightOuter,
    y = cableY,
    thickness = thickness,
    mode = mode,
    reverse = true,
    intensity = intensity,
  })
end

function M.drawReactorRightFlux(args, x, y, w, h, data)
  local mode = resolveAnimationMode(data)
  if mode == "offline" then
    return
  end

  local cableY = y + math.floor(h * 0.516)
  local thickness = math.max(2, math.floor(h * 0.018))
  local startX = x + math.floor(w * 0.748)
  local endX = x + math.floor(w * 0.915)
  local intensity = resolveFlowIntensity(data, mode)

  if mode == "running" then
    intensity = intensity * (0.88 + (pulseWave((args.state and args.state.animTick) or 0, 18) * 0.24))
  end

  drawHorizontalParticleFlow(args, {
    x1 = startX,
    x2 = endX,
    y = cableY,
    thickness = thickness,
    mode = mode,
    reverse = false,
    intensity = intensity,
  })
end

function M.drawReactorBottomFlux(args, x, y, w, h, data)
  if not data or not data.formed then
    return
  end

  local mode = resolveAnimationMode(data)
  if mode == "offline" then
    return
  end

  local topY = y + math.floor(h * 0.815)
  local bottomY = y + math.floor(h * 0.955)
  local thickness = math.max(2, math.floor(w * 0.010))
  local intensity = resolveFlowIntensity(data, mode)

  local channels = {
    { ratio = 0.334, color = 0xFF4DE06D, glow = 0x224DE06D, trail = 0x664DE06D, speed = 6, count = 2, enabled = data.readers and data.readers.deuterium and data.readers.deuterium.ok },
    { ratio = 0.455, color = 0xFFFFCC55, glow = 0x22FFCC55, trail = 0x66FFCC55, speed = 5, count = 2, enabled = (tonumber(data.dtPct) or 0) > 0 },
    { ratio = 0.562, color = 0xFF5BE8FF, glow = 0x225BE8FF, trail = 0x665BE8FF, speed = 7, count = 2, enabled = data.readers and data.readers.tritium and data.readers.tritium.ok },
  }

  for _, channel in ipairs(channels) do
    if channel.enabled then
      local cx = x + math.floor(w * channel.ratio)
      drawVerticalParticleFlow(args, {
        x = cx,
        y1 = topY,
        y2 = bottomY,
        thickness = thickness,
        mode = mode,
        reverse = true,
        intensity = intensity,
        color = channel.color,
        glow = channel.glow,
        trail = channel.trail,
        speed = channel.speed,
        count = channel.count,
      })
    end
  end
end

return M
