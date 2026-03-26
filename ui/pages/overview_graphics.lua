local M = {}

local function drawImageSafe(gpu, img, x, y)
  if not img then
    return
  end

  gpu.drawImage(x, y, img.ref())
end

local function pulseWave(frame, period)
  local t = frame % period
  local half = period / 2

  if t < half then
    return t / half
  end

  return (period - t) / half
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
    return "recharge"
  end

  return "running"
end

local function drawReactorCoreAnimationAt(args, x, y, w, h, data)
  local mode = resolveAnimationMode(data)
  if mode == "offline" then
    return
  end

  local gpu = args.gpu
  local frame = args.state.animTick or 0
  local slowPulse = pulseWave(frame, 20)
  local fastPulse = pulseWave(frame + 5, 10)

  local cx = x + math.floor(w * 0.438)
  local cy = y + math.floor(h * 0.462)

  local slitW = math.max(2, math.floor(w * 0.008))
  local slitGap = math.max(3, math.floor(w * 0.017))
  local slitBaseH = math.max(10, math.floor(h * 0.070))

  local outerGlow = 0x00000000
  local innerGlow = 0x00000000
  local coreMain = 0xFFFFAA3A
  local coreSide = 0xFFCC6A2A

  if mode == "standby" then
    outerGlow = 0x10000000
    innerGlow = 0x18FF9A22
    coreMain = 0xFF9C5A20
    coreSide = 0xFF6A3818
  elseif mode == "charging" or mode == "recharge" then
    outerGlow = 0x1400C8FF
    innerGlow = 0x205BE8FF
    coreMain = 0xFFE8C24A
    coreSide = 0xFFB88A32
  elseif mode == "ready" then
    outerGlow = 0x1A5BE8FF
    innerGlow = 0x22FFD76A
    coreMain = 0xFFFFD15A
    coreSide = 0xFFE09A3A
  elseif mode == "firing" then
    outerGlow = 0x28FFFFFF
    innerGlow = 0x40FFC85A
    coreMain = 0xFFFFFFFF
    coreSide = 0xFFFFB44A
  else
    outerGlow = 0x18000000
    innerGlow = 0x28FFB43A
    coreMain = 0xFFFFC24A
    coreSide = 0xFFE07C2C
  end

  local glowW = math.max(10, math.floor(w * 0.045) + math.floor(slowPulse * 3))
  local glowH = math.max(12, math.floor(h * 0.085) + math.floor(fastPulse * 4))
  local glowX = cx - math.floor(glowW / 2)
  local glowY = cy - math.floor(glowH / 2)

  if outerGlow ~= 0x00000000 then
    gpu.filledRectangle(glowX - 2, glowY - 2, glowW + 4, glowH + 4, outerGlow)
  end
  if innerGlow ~= 0x00000000 then
    gpu.filledRectangle(glowX, glowY, glowW, glowH, innerGlow)
  end

  for i = -1, 1 do
    local localPulse = ((frame + (i + 2) * 2) % 8)
    local slitH = slitBaseH + localPulse * math.max(1, math.floor(h * 0.005))
    local bx = cx + i * slitGap - math.floor(slitW / 2)
    local by = cy + math.floor(h * 0.012) - slitH

    gpu.filledRectangle(bx, by, slitW, slitH, i == 0 and coreMain or coreSide)

    if mode == "firing" then
      gpu.filledRectangle(bx, by - 1, slitW, 2, 0x88FFFFFF)
    end
  end
end

local function getEnergyFlowStyle(mode)
  local style = {
    baseGlow = 0x1600D8FF,
    packetColor = 0xFF5BE8FF,
    markerColor = 0x669FF2FF,
    count = 1,
    speed = 8,
  }

  if mode == "standby" then
    style.baseGlow = 0x1200D8FF
    style.packetColor = 0x8868E0FF
    style.markerColor = 0x4468E0FF
    style.count = 1
    style.speed = 12
  elseif mode == "charging" or mode == "recharge" then
    style.baseGlow = 0x2000D8FF
    style.packetColor = 0xFF5BE8FF
    style.markerColor = 0x885BE8FF
    style.count = 2
    style.speed = 8
  elseif mode == "ready" then
    style.baseGlow = 0x1848E0FF
    style.packetColor = 0xFF9FF2FF
    style.markerColor = 0x669FF2FF
    style.count = 1
    style.speed = 14
  elseif mode == "firing" then
    style.baseGlow = 0x24FFD070
    style.packetColor = 0xFFFFFFFF
    style.markerColor = 0x88FFFFFF
    style.count = 3
    style.speed = 5
  elseif mode == "running" then
    style.baseGlow = 0x1400D8FF
    style.packetColor = 0x66A8F8FF
    style.markerColor = 0x559FF2FF
    style.count = 1
    style.speed = 16
  end

  return style
end

local function drawHorizontalCableFlow(args, x1, x2, y, thickness, mode, reverse, styleScale)
  if x2 < x1 then
    x1, x2 = x2, x1
  end

  local gpu = args.gpu
  local frame = args.state.animTick or 0
  local style = getEnergyFlowStyle(mode)
  local travel = math.max(4, x2 - x1)
  local packetW = math.max(2, math.floor((styleScale or 8) * 0.85))
  local packetH = math.max(2, thickness + 1)

  gpu.filledRectangle(x1, y - math.floor(thickness / 2), x2 - x1 + 1, thickness, style.baseGlow)

  for i = 1, style.count do
    local stride = math.max(3, math.floor(travel / math.max(1, style.count)))
    local phase = ((frame * style.speed) + i * stride) % travel
    local px = reverse and (x2 - phase) or (x1 + phase)

    gpu.filledRectangle(px - 1, y - math.floor(packetH / 2) - 1, packetW + 2, packetH + 2, style.baseGlow)
    gpu.filledRectangle(px, y - math.floor(packetH / 2), packetW, packetH, style.packetColor)
  end

  if mode == "ready" or mode == "running" then
    local blink = (math.floor(frame / 6) % 2) == 0
    if blink then
      local mx = reverse and x1 or x2
      gpu.filledRectangle(mx - 1, y - 2, 4, 5, style.markerColor)
    end
  elseif mode == "firing" then
    local mx = reverse and x2 or x1
    gpu.filledRectangle(mx - 2, y - 3, 6, 7, style.markerColor)
  end
end

local function drawVerticalCableFlow(args, x, y1, y2, thickness, color, glow, speed, reverse, count)
  if y2 < y1 then
    y1, y2 = y2, y1
  end

  local gpu = args.gpu
  local frame = args.state.animTick or 0
  local travel = math.max(4, y2 - y1)
  local packetW = math.max(2, thickness + 1)
  local packetH = math.max(3, math.floor(travel * 0.14))

  gpu.filledRectangle(x - math.floor(thickness / 2), y1, thickness, y2 - y1 + 1, glow)

  for i = 1, (count or 2) do
    local stride = math.max(3, math.floor(travel / math.max(1, count or 2)))
    local phase = ((frame * speed) + i * stride) % travel
    local py = reverse and (y2 - phase) or (y1 + phase)

    gpu.filledRectangle(x - math.floor(packetW / 2) - 1, py - 1, packetW + 2, packetH + 2, glow)
    gpu.filledRectangle(x - math.floor(packetW / 2), py, packetW, packetH, color)
  end
end

local function drawModuleCableFluxAt(args, x, y, w, h, data)
  local mode = resolveAnimationMode(data)
  if mode == "offline" then
    return
  end

  local cableY = y + math.floor(h * 0.50)
  local thickness = math.max(2, math.floor(h * 0.12))

  local leftOuter = x + math.floor(w * 0.095)
  local leftInner = x + math.floor(w * 0.295)
  local rightInner = x + math.floor(w * 0.695)
  local rightOuter = x + math.floor(w * 0.900)

  drawHorizontalCableFlow(args, leftOuter, leftInner, cableY, thickness, mode, false, thickness)
  drawHorizontalCableFlow(args, rightInner, rightOuter, cableY, thickness, mode, true, thickness)
end

local function drawReactorRightCableFluxAt(args, x, y, w, h, data)
  local mode = resolveAnimationMode(data)
  if mode == "offline" then
    return
  end

  local cableY = y + math.floor(h * 0.516)
  local thickness = math.max(2, math.floor(h * 0.018))
  local startX = x + math.floor(w * 0.748)
  local endX = x + math.floor(w * 0.915)

  drawHorizontalCableFlow(args, startX, endX, cableY, thickness, mode, false, thickness)
end

local function drawReactorBottomGasFluxAt(args, x, y, w, h, data)
  if not data or not data.formed then
    return
  end

  local topY = y + math.floor(h * 0.815)
  local bottomY = y + math.floor(h * 0.955)
  local thickness = math.max(2, math.floor(w * 0.010))

  local channels = {
    { ratio = 0.334, color = 0xFF4DE06D, glow = 0x224DE06D, speed = 6, count = 2, enabled = data.readers and data.readers.deuterium and data.readers.deuterium.ok },
    { ratio = 0.455, color = 0xFFFFCC55, glow = 0x22FFCC55, speed = 5, count = 2, enabled = (tonumber(data.dtPct) or 0) > 0 },
    { ratio = 0.562, color = 0xFF5BE8FF, glow = 0x225BE8FF, speed = 7, count = 2, enabled = data.readers and data.readers.tritium and data.readers.tritium.ok },
  }

  for _, channel in ipairs(channels) do
    if channel.enabled then
      local cx = x + math.floor(w * channel.ratio)
      drawVerticalCableFlow(args, cx, topY, bottomY, thickness, channel.color, channel.glow, channel.speed, true, channel.count)
    end
  end
end

function M.drawImageStack(args)
  local slotX = args.slotX
  local slotY = args.slotY
  local slotW = args.slotW
  local slotH = args.slotH
  local data = args.data
  local forcedLayout = args.forcedLayout
  local control = args.control
  local ui = args.ui
  local C = args.colors
  local gpu = args.gpu
  local chooseStackLayout = args.chooseStackLayout
  local drawTextCenter = args.drawTextCenter
  local textPixelHeight = args.textPixelHeight

  local configuredModuleCount = math.max(1, tonumber(control.laserModuleCount) or 1)
  local layout = forcedLayout or chooseStackLayout(slotW, slotH, configuredModuleCount)

  gpu.filledRectangle(slotX, slotY, slotW, slotH, C.white)

  if not layout or not layout.reactor then
    local ty = slotY + math.max(0, math.floor((slotH - textPixelHeight(1)) / 2))
    drawTextCenter(slotX, ty, slotW, "assets missing", C.muted, 1)
    return
  end

  local reactorVariant = layout.reactor
  local moduleVariant = layout.module
  local configuredCount = layout.configuredModuleCount or configuredModuleCount
  local drawnModuleCount = layout.drawnModuleCount
  if drawnModuleCount == nil then
    drawnModuleCount = layout.moduleCount or configuredCount
    if ui.micro and configuredCount > 6 then
      drawnModuleCount = math.min(drawnModuleCount, 6)
    end
  end

  local moduleGap = layout.moduleGap or math.max(1, math.floor(ui.smallPad * 0.45))
  local gap = ui.smallPad
  local modulesBlockH = 0

  if moduleVariant and drawnModuleCount > 0 then
    modulesBlockH = (moduleVariant.height * drawnModuleCount) + (moduleGap * math.max(0, drawnModuleCount - 1))
  end

  local totalH = reactorVariant.height + ((moduleVariant and drawnModuleCount > 0) and (gap + modulesBlockH) or 0)
  local startY = slotY + math.floor((slotH - totalH) / 2)

  if moduleVariant and drawnModuleCount > 0 then
    for i = 1, drawnModuleCount do
      local moduleX = slotX + math.floor((slotW - moduleVariant.width) / 2)
      local moduleY = startY + ((i - 1) * (moduleVariant.height + moduleGap))
      drawImageSafe(gpu, moduleVariant.image, moduleX, moduleY)
      drawModuleCableFluxAt(args, moduleX, moduleY, moduleVariant.width, moduleVariant.height, data)
    end
    startY = startY + modulesBlockH + gap
  else
    local moduleTextY = startY + math.max(0, math.floor((ui.smallPad + textPixelHeight(1)) / 2))
    drawTextCenter(slotX, moduleTextY, slotW, "LASER x" .. tostring(configuredCount), C.muted, 1)
    startY = startY + ui.smallPad + textPixelHeight(1) + ui.smallPad
  end

  local reactorX = slotX + math.floor((slotW - reactorVariant.width) / 2)
  drawImageSafe(gpu, reactorVariant.image, reactorX, startY)
  drawReactorCoreAnimationAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawReactorRightCableFluxAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawReactorBottomGasFluxAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)

  if configuredCount > drawnModuleCount then
    local badgeW = math.max(26, math.floor(slotW * 0.28))
    local badgeH = 12
    local badgeX = slotX + slotW - badgeW - 2
    local badgeY = slotY + 2

    gpu.filledRectangle(badgeX, badgeY, badgeW, badgeH, C.panel)
    gpu.rectangle(badgeX, badgeY, badgeW, badgeH, C.border)
    drawTextCenter(badgeX, badgeY + 2, badgeW, "x" .. tostring(configuredCount), C.yellow, 1)
  end
end

return M
