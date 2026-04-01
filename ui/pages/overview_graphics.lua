local M = {}

local ElectricFlowAnimation = assert(dofile("ui/animations/electric_flow.lua"))
local ReactorCoreAnimation = assert(dofile("ui/animations/reactor_core.lua"))
local GpuSafe = assert(dofile("ui/helpers/gpu_safe.lua"))
local renderLogKeys = {}
local STACK_CALIBRATION = {
  large = { moduleGapMul = 0.46, reactorGapMul = 1.92, stackOffsetY = 2, moduleOffsetX = -1, reactorOffsetX = 0 },
  compact = { moduleGapMul = 0.42, reactorGapMul = 1.70, stackOffsetY = 1, moduleOffsetX = -1, reactorOffsetX = 0 },
  micro = { moduleGapMul = 0.38, reactorGapMul = 1.40, stackOffsetY = 0, moduleOffsetX = 0, reactorOffsetX = 0 },
}

local function resolveStackCalibration(ui, state)
  local profile = STACK_CALIBRATION.large
  if ui and ui.micro then
    profile = STACK_CALIBRATION.micro
  elseif ui and ui.compact then
    profile = STACK_CALIBRATION.compact
  end

  local smallPad = ui and ui.smallPad or 0
  local moduleGap = math.max(1, math.floor(smallPad * profile.moduleGapMul))
  local reactorGap = math.max(2, math.floor(smallPad * profile.reactorGapMul))
  local stackOffsetY = profile.stackOffsetY or 0
  local moduleOffsetX = profile.moduleOffsetX or 0
  local reactorOffsetX = profile.reactorOffsetX or 0

  local visual = state and state.visual
  if visual and visual.effectLevel == "minimal" then
    moduleGap = math.max(1, moduleGap - 1)
  end

  return {
    moduleGap = moduleGap,
    reactorGap = reactorGap,
    stackOffsetY = stackOffsetY,
    moduleOffsetX = moduleOffsetX,
    reactorOffsetX = reactorOffsetX,
  }
end

local function appendRuntimeLog(args, message)
  local logger = args and args.appendUiRuntimeLog
  if type(logger) == "function" then
    logger(message)
  end
end

local function appendRuntimeLogOnce(args, stage, key, message)
  if renderLogKeys[stage] ~= key then
    appendRuntimeLog(args, message)
    renderLogKeys[stage] = key
  end
end

local function drawImageSafe(args, img, x, y)
  if not img then
    return
  end

  GpuSafe.drawImage(args, img, x, y)
end

local function drawModuleCableFluxAt(args, x, y, w, h, data)
  ElectricFlowAnimation.drawModuleFlux(args, x, y, w, h, data)
end

local function drawReactorRightCableFluxAt(args, x, y, w, h, data)
  ElectricFlowAnimation.drawReactorRightFlux(args, x, y, w, h, data)
end

local function drawReactorBottomGasFluxAt(args, x, y, w, h, data)
  ElectricFlowAnimation.drawReactorBottomFlux(args, x, y, w, h, data)
end

local function drawReactorCoreAnimationAt(args, x, y, w, h, data)
  ReactorCoreAnimation.draw(args, x, y, w, h, data)
end

local function clampValue(value, minValue, maxValue)
  if value < minValue then
    return minValue
  end
  if value > maxValue then
    return maxValue
  end
  return value
end

local function drawLineSafe(args, x1, y1, x2, y2, color, thickness)
  local t = math.max(1, math.floor(tonumber(thickness) or 1))
  local half = math.floor(t / 2)
  local ix1 = math.floor(tonumber(x1) or 0)
  local iy1 = math.floor(tonumber(y1) or 0)
  local ix2 = math.floor(tonumber(x2) or 0)
  local iy2 = math.floor(tonumber(y2) or 0)

  local dx = math.abs(ix2 - ix1)
  local sx = ix1 < ix2 and 1 or -1
  local dy = -math.abs(iy2 - iy1)
  local sy = iy1 < iy2 and 1 or -1
  local err = dx + dy

  while true do
    GpuSafe.filledRect(args, ix1 - half, iy1 - half, t, t, color)
    if ix1 == ix2 and iy1 == iy2 then
      break
    end
    local e2 = err * 2
    if e2 >= dy then
      err = err + dy
      ix1 = ix1 + sx
    end
    if e2 <= dx then
      err = err + dx
      iy1 = iy1 + sy
    end
  end
end

local PORT_CHANNELS = {
  -- Strict left -> right order requested from field calibration.
  { key = "tritium", ratio = 0.334, color = 0xFF4DE06D },
  { key = "dtFuel", ratio = 0.452, color = 0xFFB26BFF },
  { key = "deuterium", ratio = 0.567, color = 0xFFFF5A5A },
}

local function formatMkValue(value)
  local n = tonumber(value)
  if not n then
    return "n/a"
  end
  return string.format("%.1f", n)
end

local function formatTemperatureLabel(profile, kind, mkValue)
  local valueText = formatMkValue(mkValue)
  if profile.mode == "micro" then
    if kind == "case" then
      return "C " .. valueText
    end
    return "P " .. valueText
  end

  if profile.mode == "compact" then
    if kind == "case" then
      return "CASE " .. valueText
    end
    return "CORE " .. valueText
  end

  if valueText == "n/a" then
    if kind == "case" then
      return "T CASE n/a"
    end
    return "T CORE n/a"
  end

  if kind == "case" then
    return "T CASE " .. valueText .. " MK"
  end
  return "T CORE " .. valueText .. " MK"
end

local function resolveReaderOpenState(reader, sourcePrefix)
  if type(reader) ~= "table" or reader.ok ~= true then
    return nil, nil
  end

  if type(reader.active) == "boolean" then
    return reader.active, sourcePrefix .. ".active"
  end

  if type(reader.currentRedstone) == "number" then
    return reader.currentRedstone > 0, sourcePrefix .. ".currentRedstone"
  end

  if type(reader.redstone) == "number" then
    return reader.redstone > 0, sourcePrefix .. ".redstone"
  end

  if type(reader.amount) == "number" then
    return reader.amount > 0, sourcePrefix .. ".amount"
  end

  return nil, nil
end

local function resolvePortOpenState(data, key)
  local readers = type(data) == "table" and data.readers or nil
  local relayStates = type(data) == "table" and data.relayStates or nil

  if key == "tritium" then
    local open, source = resolveReaderOpenState(readers and readers.tritium, "reader.tritium")
    if open ~= nil then
      return open, source
    end
    if relayStates and relayStates.tritiumTank ~= nil then
      return relayStates.tritiumTank == true, "relay.tritiumTank"
    end
    return (tonumber(data and data.tPct) or 0) > 0.1, "inference.tPct"
  end

  if key == "deuterium" then
    local open, source = resolveReaderOpenState(readers and readers.deuterium, "reader.deuterium")
    if open ~= nil then
      return open, source
    end
    if relayStates and relayStates.deuteriumTank ~= nil then
      return relayStates.deuteriumTank == true, "relay.deuteriumTank"
    end
    return (tonumber(data and data.dPct) or 0) > 0.1, "inference.dPct"
  end

  local open, source = resolveReaderOpenState(readers and readers.dtFuel, "reader.dtFuel")
  if open ~= nil then
    return open, source
  end

  local triRelay = relayStates and relayStates.tritiumTank == true
  local deuRelay = relayStates and relayStates.deuteriumTank == true
  if relayStates and (relayStates.tritiumTank ~= nil or relayStates.deuteriumTank ~= nil) then
    return triRelay and deuRelay, "inference.relayPair"
  end

  local injection = tonumber(data and data.injectionRateValue) or 0
  local dtPct = tonumber(data and data.dtPct) or 0
  local ignited = data and data.ignited == true
  return ((ignited and dtPct > 0.1) or injection > 0), "inference.dtPct|injection"
end

local function formatPortStatus(profile, channelKey, isOpen)
  local stateText = isOpen and profile.portStateOpen or profile.portStateClosed
  local name = profile.portNames[channelKey] or string.upper(channelKey)
  if profile.mode == "micro" then
    return name .. " " .. stateText
  end
  return name .. " " .. stateText
end

local function drawLeaderLabel(args, spec)
  local gpu = args and args.gpu
  if not gpu then
    return
  end

  local text = tostring(spec.text or "")
  if text == "" then
    return
  end

  local size = math.max(1, math.floor(spec.size or 1))
  local padX = math.max(1, math.floor(spec.padX or 2))
  local padY = math.max(0, math.floor(spec.padY or 1))
  local textW = math.max(1, gpu.getTextLength(text, size, 0))
  local textH = math.max(1, spec.textPixelHeight and spec.textPixelHeight(size) or (8 * size))
  local boxW = textW + (padX * 2)
  local boxH = textH + (padY * 2)

  local minX = spec.slotX + 1
  local minY = spec.slotY + 1
  local maxX = spec.slotX + spec.slotW - boxW - 1
  local maxY = spec.slotY + spec.slotH - boxH - 1
  if maxX < minX or maxY < minY then
    return
  end

  local requestedX = math.floor(spec.labelX)
  local requestedY = math.floor(spec.labelY)
  local labelX = clampValue(requestedX, minX, maxX)
  local labelY = clampValue(requestedY, minY, maxY)
  local labelTargetX = (spec.side == "left") and (labelX + boxW - 1) or labelX
  local labelTargetY = labelY + math.floor(boxH / 2)
  local annotationName = tostring(spec.name or "annotation")

  if labelX ~= requestedX or labelY ~= requestedY then
    local clampKey = table.concat({
      annotationName,
      tostring(requestedX),
      tostring(requestedY),
      tostring(labelX),
      tostring(labelY),
      tostring(spec.slotX),
      tostring(spec.slotY),
      tostring(spec.slotW),
      tostring(spec.slotH),
    }, "|")

    appendRuntimeLogOnce(
      args,
      "annotation_clamp_" .. annotationName,
      clampKey,
      "overview annotation clamped:"
        .. " name=" .. annotationName
        .. " requested=" .. tostring(requestedX) .. "," .. tostring(requestedY)
        .. " final=" .. tostring(labelX) .. "," .. tostring(labelY)
        .. " viewport=" .. tostring(spec.slotX) .. "," .. tostring(spec.slotY)
        .. ":" .. tostring(spec.slotW) .. "x" .. tostring(spec.slotH)
    )
  end

  local lineColor = spec.lineColor
  local lineThickness = math.max(1, math.floor(spec.lineThickness or 1))
  drawLineSafe(args, spec.anchorX, spec.anchorY, spec.kneeX, spec.kneeY, lineColor, lineThickness)
  drawLineSafe(args, spec.kneeX, spec.kneeY, labelTargetX, labelTargetY, lineColor, lineThickness)

  GpuSafe.filledRect(args, labelX, labelY, boxW, boxH, spec.bgColor)
  GpuSafe.rectangle(args, labelX, labelY, boxW, boxH, spec.borderColor)

  if type(spec.drawTextCenter) == "function" then
    spec.drawTextCenter(
      labelX,
      labelY + math.max(0, math.floor((boxH - textH) / 2)),
      boxW,
      text,
      spec.textColor,
      size
    )
  end
end

local function resolveAnnotationProfile(ui, slotW, slotH)
  if slotW < 86 or slotH < 86 then
    return { enabled = false }
  end

  if ui and ui.micro then
    return {
      enabled = true,
      mode = "micro",
      lineThickness = 1,
      rightOffset = 3,
      diagStep = 5,
      labelPadX = 1,
      caseDiagY = -4,
      caseLabelDy = -3,
      coreDiagY = 5,
      coreLabelDy = -3,
      portKneeY = 4,
      portKneeX = { -3, 0, 3 },
      portLabelDx = { -13, -8, -2 },
      portLabelDy = { 4, 5, 6 },
      portNames = {
        tritium = "T",
        dtFuel = "DT",
        deuterium = "D",
      },
      portStateOpen = "O",
      portStateClosed = "F",
    }
  end

  if ui and ui.compact then
    return {
      enabled = true,
      mode = "compact",
      lineThickness = 1,
      rightOffset = 5,
      diagStep = 7,
      labelPadX = 2,
      caseDiagY = -6,
      caseLabelDy = -5,
      coreDiagY = 8,
      coreLabelDy = -5,
      portKneeY = 7,
      portKneeX = { -7, 0, 7 },
      portLabelDx = { -40, -24, -8 },
      portLabelDy = { 6, 8, 10 },
      portNames = {
        tritium = "TRI",
        dtFuel = "DT",
        deuterium = "DEU",
      },
      portStateOpen = "OUVERT",
      portStateClosed = "FERME",
    }
  end

  return {
    enabled = true,
    mode = "large",
    lineThickness = 2,
    rightOffset = 7,
    diagStep = 9,
    labelPadX = 2,
    caseDiagY = -8,
    caseLabelDy = -6,
    coreDiagY = 9,
    coreLabelDy = -6,
    portKneeY = 9,
    portKneeX = { -9, 0, 9 },
    portLabelDx = { -52, -30, -9 },
    portLabelDy = { 8, 11, 14 },
    portNames = {
      tritium = "TRITIUM",
      dtFuel = "DT-FUEL",
      deuterium = "DEUTERIUM",
    },
    portStateOpen = "OUVERT",
    portStateClosed = "FERME",
  }
end

local function drawSceneAnnotations(args, drawTextCenter, textPixelHeight, slotX, slotY, slotW, slotH, reactorX, reactorY, reactorW, reactorH, data)
  local ui = args.ui
  local profile = resolveAnnotationProfile(ui, slotW, slotH)
  if not profile.enabled then
    return
  end

  local smallPad = ui and ui.smallPad or 1
  local tempColor = 0xFFE54E60
  local bgColor = 0xC0151B24
  local borderColor = 0xCC2B3646
  local caseLabelText = formatTemperatureLabel(profile, "case", data and data.caseMK)
  local coreLabelText = formatTemperatureLabel(profile, "core", data and data.plasmaMK)

  local caseAnchorX = reactorX + math.floor(reactorW * 0.78)
  local caseAnchorY = reactorY + math.floor(reactorH * 0.34)
  local caseKneeX = clampValue(caseAnchorX + profile.diagStep, slotX + 1, slotX + slotW - 2)
  local caseKneeY = clampValue(caseAnchorY + profile.caseDiagY, slotY + 1, slotY + slotH - 2)
  local caseLabelX = caseKneeX + profile.rightOffset + smallPad
  local caseLabelY = caseKneeY + profile.caseLabelDy

  drawLeaderLabel(args, {
    name = "CASE",
    text = caseLabelText,
    size = 1,
    padX = profile.labelPadX,
    padY = 0,
    slotX = slotX,
    slotY = slotY,
    slotW = slotW,
    slotH = slotH,
    labelX = caseLabelX,
    labelY = caseLabelY,
    side = "right",
    anchorX = caseAnchorX,
    anchorY = caseAnchorY,
    kneeX = caseKneeX,
    kneeY = caseKneeY,
    lineColor = tempColor,
    lineThickness = profile.lineThickness,
    textColor = tempColor,
    bgColor = bgColor,
    borderColor = borderColor,
    drawTextCenter = drawTextCenter,
    textPixelHeight = textPixelHeight,
  })

  local coreAnchorX = reactorX + math.floor(reactorW * 0.52)
  local coreAnchorY = reactorY + math.floor(reactorH * 0.52)
  local coreKneeX = clampValue(coreAnchorX + profile.diagStep, slotX + 1, slotX + slotW - 2)
  local coreKneeY = clampValue(coreAnchorY + profile.coreDiagY, slotY + 1, slotY + slotH - 2)
  local coreLabelX = coreKneeX + profile.rightOffset + smallPad
  local coreLabelY = coreKneeY + profile.coreLabelDy

  drawLeaderLabel(args, {
    name = "CORE",
    text = coreLabelText,
    size = 1,
    padX = profile.labelPadX,
    padY = 0,
    slotX = slotX,
    slotY = slotY,
    slotW = slotW,
    slotH = slotH,
    labelX = coreLabelX,
    labelY = coreLabelY,
    side = "right",
    anchorX = coreAnchorX,
    anchorY = coreAnchorY,
    kneeX = coreKneeX,
    kneeY = coreKneeY,
    lineColor = tempColor,
    lineThickness = profile.lineThickness,
    textColor = tempColor,
    bgColor = bgColor,
    borderColor = borderColor,
    drawTextCenter = drawTextCenter,
    textPixelHeight = textPixelHeight,
  })

  local portTelemetrySummary = {}
  for idx, channel in ipairs(PORT_CHANNELS) do
    local portAnchorX = reactorX + math.floor(reactorW * channel.ratio)
    local portAnchorY = reactorY + math.floor(reactorH * 0.91)
    local portKneeX = clampValue(portAnchorX + (profile.portKneeX[idx] or 0), slotX + 1, slotX + slotW - 2)
    local portKneeY = clampValue(portAnchorY + profile.portKneeY, slotY + 1, slotY + slotH - 2)
    local portLabelX = portKneeX + (profile.portLabelDx[idx] or 0)
    local portLabelY = portKneeY + (profile.portLabelDy[idx] or 0)
    local isOpen, source = resolvePortOpenState(data, channel.key)
    local labelText = formatPortStatus(profile, channel.key, isOpen)
    local side = (portLabelX < portAnchorX) and "left" or "right"

    drawLeaderLabel(args, {
      name = "FLOW_" .. string.upper(channel.key),
      text = labelText,
      size = 1,
      padX = profile.labelPadX,
      padY = 0,
      slotX = slotX,
      slotY = slotY,
      slotW = slotW,
      slotH = slotH,
      labelX = portLabelX,
      labelY = portLabelY,
      side = side,
      anchorX = portAnchorX,
      anchorY = portAnchorY,
      kneeX = portKneeX,
      kneeY = portKneeY,
      lineColor = channel.color,
      lineThickness = profile.lineThickness,
      textColor = channel.color,
      bgColor = bgColor,
      borderColor = borderColor,
      drawTextCenter = drawTextCenter,
      textPixelHeight = textPixelHeight,
    })

    portTelemetrySummary[#portTelemetrySummary + 1] =
      channel.key .. "=" .. (isOpen and "open" or "closed") .. "@" .. tostring(source or "n/a")
  end

  local annotationStateKey = table.concat({
    tostring(caseLabelText),
    tostring(coreLabelText),
    table.concat(portTelemetrySummary, ","),
  }, "|")
  appendRuntimeLogOnce(
    args,
    "overview_annotation_state",
    annotationStateKey,
    "overview annotations: "
      .. "case=\"" .. tostring(caseLabelText) .. "\" "
      .. "core=\"" .. tostring(coreLabelText) .. "\" "
      .. "flows=" .. table.concat(portTelemetrySummary, ",")
  )
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
  local sceneMode = tostring(args.sceneMode or "none")
  local reactorPresent = args.reactorPresent == true
  local laserPresent = args.laserPresent == true
  local reactorAssetName = tostring(args.reactorAssetName or "none")
  local laserAssetName = tostring(args.laserAssetName or "none")
  local fallbackReactorVariant = args.fallbackReactorVariant
  local fallbackLaserVariant = args.fallbackLaserVariant
  local stackCalibration = resolveStackCalibration(ui, args.state)
  if (not reactorPresent) and fallbackReactorVariant then
    reactorPresent = true
  end
  if (not laserPresent) and fallbackLaserVariant then
    laserPresent = true
  end
  local safeRect = function(x, y, w, h, color)
    GpuSafe.filledRect(args, x, y, w, h, color)
  end

  if slotW <= 0 or slotH <= 0 then
    return
  end

  local configuredModuleCount = math.max(1, tonumber(control.laserModuleCount) or 1)
  local layout = forcedLayout
  if not layout or not layout.reactor then
    layout = chooseStackLayout(slotW, slotH, configuredModuleCount)
  end

  if (not layout or not layout.reactor)
    and fallbackReactorVariant
    and fallbackReactorVariant.width <= slotW
    and fallbackReactorVariant.height <= slotH then
    layout = {
      reactor = fallbackReactorVariant,
      module = nil,
      moduleCount = 0,
      configuredModuleCount = configuredModuleCount,
      drawnModuleCount = 0,
      moduleGap = stackCalibration.moduleGap,
      reactorGap = stackCalibration.reactorGap,
      stackOffsetY = stackCalibration.stackOffsetY,
      moduleOffsetX = stackCalibration.moduleOffsetX,
      reactorOffsetX = stackCalibration.reactorOffsetX,
    }
    local fallbackLayoutKey = table.concat({
      tostring(slotW),
      tostring(slotH),
      tostring(fallbackReactorVariant.name or "runtime"),
    }, "|")
    appendRuntimeLogOnce(
      args,
      "overview_scene_fallback_layout",
      fallbackLayoutKey,
      "overview renderer fallback: promoting reactor-only layout from active reactor asset"
        .. " reactorVariant=" .. tostring(fallbackReactorVariant.name or "runtime")
    )
  elseif (not layout or not layout.reactor) and fallbackReactorVariant then
    local fallbackRejectKey = table.concat({
      tostring(slotW),
      tostring(slotH),
      tostring(fallbackReactorVariant.width),
      tostring(fallbackReactorVariant.height),
    }, "|")
    appendRuntimeLogOnce(
      args,
      "overview_scene_fallback_reject",
      fallbackRejectKey,
      "overview renderer fallback rejected: class=viewport_overflow"
        .. " viewport=" .. tostring(slotW) .. "x" .. tostring(slotH)
        .. " reactorSize=" .. tostring(fallbackReactorVariant.width) .. "x" .. tostring(fallbackReactorVariant.height)
    )
  end

  safeRect(slotX, slotY, slotW, slotH, C.white)

  local incomingKey = table.concat({
    tostring(sceneMode),
    tostring(reactorPresent),
    tostring(laserPresent),
    tostring(reactorAssetName),
    tostring(laserAssetName),
    tostring(layout and layout.reactor ~= nil),
    tostring(layout and layout.module ~= nil),
    tostring(slotW),
    tostring(slotH),
  }, "|")
  appendRuntimeLogOnce(
    args,
    "overview_scene_incoming",
    incomingKey,
    "overview renderer incoming:"
      .. " sceneMode=" .. tostring(sceneMode)
      .. " reactorPresent=" .. tostring(reactorPresent and "yes" or "no")
      .. " laserPresent=" .. tostring(laserPresent and "yes" or "no")
      .. " reactorAsset=" .. tostring(reactorAssetName)
      .. " laserAsset=" .. tostring(laserAssetName)
      .. " layoutReactor=" .. tostring(layout and layout.reactor and "yes" or "no")
      .. " layoutLaser=" .. tostring(layout and layout.module and "yes" or "no")
  )

  if not layout or not layout.reactor then
    local missingKey = table.concat({
      tostring(sceneMode),
      tostring(reactorPresent),
      tostring(laserPresent),
      tostring(slotW),
      tostring(slotH),
    }, "|")
    appendRuntimeLogOnce(
      args,
      "overview_scene_missing",
      missingKey,
      "overview renderer final: sceneMode=none rendered=assets_missing"
        .. " reactorPresent=" .. tostring(reactorPresent and "yes" or "no")
        .. " laserPresent=" .. tostring(laserPresent and "yes" or "no")
        .. " reason=no_reactor_layout"
    )
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

  local moduleGap = layout.moduleGap or stackCalibration.moduleGap
  local reactorGap = layout.reactorGap or stackCalibration.reactorGap
  local stackOffsetY = layout.stackOffsetY or stackCalibration.stackOffsetY
  local moduleOffsetX = layout.moduleOffsetX or stackCalibration.moduleOffsetX or 0
  local reactorOffsetX = layout.reactorOffsetX or stackCalibration.reactorOffsetX or 0
  local modulesBlockH = 0

  if moduleVariant and drawnModuleCount > 0 then
    modulesBlockH = (moduleVariant.height * drawnModuleCount) + (moduleGap * math.max(0, drawnModuleCount - 1))
  end

  local totalH = reactorVariant.height + ((moduleVariant and drawnModuleCount > 0) and (reactorGap + modulesBlockH) or 0)
  local startY = slotY + math.floor((slotH - totalH) / 2) + stackOffsetY
  local minStartY = slotY
  local maxStartY = slotY + math.max(0, slotH - totalH)
  if startY < minStartY then
    startY = minStartY
  elseif startY > maxStartY then
    startY = maxStartY
  end

  local reactorX = slotX + math.floor((slotW - reactorVariant.width) / 2) + reactorOffsetX
  reactorX = clampValue(reactorX, slotX, slotX + math.max(0, slotW - reactorVariant.width))

  if moduleVariant and drawnModuleCount > 0 then
    local moduleBaseX = reactorX + math.floor((reactorVariant.width - moduleVariant.width) / 2) + moduleOffsetX
    local moduleMinX = slotX
    local moduleMaxX = slotX + math.max(0, slotW - moduleVariant.width)
    for i = 1, drawnModuleCount do
      local moduleX = clampValue(moduleBaseX, moduleMinX, moduleMaxX)
      local moduleY = startY + ((i - 1) * (moduleVariant.height + moduleGap))
      drawImageSafe(args, moduleVariant.image, moduleX, moduleY)
      drawModuleCableFluxAt(args, moduleX, moduleY, moduleVariant.width, moduleVariant.height, data)
    end
    startY = startY + modulesBlockH + reactorGap
  else
    local moduleTextY = startY + math.max(0, math.floor((ui.smallPad + textPixelHeight(1)) / 2))
    drawTextCenter(slotX, moduleTextY, slotW, "LASER x" .. tostring(configuredCount), C.muted, 1)
    startY = startY + math.max(ui.smallPad, reactorGap - 1) + textPixelHeight(1) + ui.smallPad
  end

  drawImageSafe(args, reactorVariant.image, reactorX, startY)
  drawReactorCoreAnimationAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawReactorRightCableFluxAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawReactorBottomGasFluxAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawSceneAnnotations(args, drawTextCenter, textPixelHeight, slotX, slotY, slotW, slotH, reactorX, startY, reactorVariant.width, reactorVariant.height, data)

  local renderedMode = moduleVariant and drawnModuleCount > 0 and "pair" or "reactor-only"
  local renderedKey = table.concat({
    tostring(renderedMode),
    tostring(reactorVariant and reactorVariant.name or "none"),
    tostring(moduleVariant and moduleVariant.name or "none"),
    tostring(reactorVariant and reactorVariant.width or "n/a"),
    tostring(reactorVariant and reactorVariant.height or "n/a"),
    tostring(moduleGap),
    tostring(reactorGap),
    tostring(stackOffsetY),
    tostring(moduleOffsetX),
    tostring(reactorOffsetX),
    tostring(slotW),
    tostring(slotH),
  }, "|")
  appendRuntimeLogOnce(
    args,
    "overview_scene_rendered",
    renderedKey,
    "overview renderer final:"
      .. " sceneMode=" .. tostring(renderedMode)
      .. " reactorPresent=yes"
      .. " laserPresent=" .. tostring(moduleVariant and drawnModuleCount > 0 and "yes" or "no")
      .. " reactorVariant=" .. tostring(reactorVariant and reactorVariant.name or "none")
      .. " reactorSize=" .. tostring(reactorVariant and reactorVariant.width or "n/a") .. "x" .. tostring(reactorVariant and reactorVariant.height or "n/a")
      .. " laserVariant=" .. tostring(moduleVariant and moduleVariant.name or "none")
      .. " laserSize=" .. tostring(moduleVariant and moduleVariant.width or "n/a") .. "x" .. tostring(moduleVariant and moduleVariant.height or "n/a")
      .. " moduleGap=" .. tostring(moduleGap)
      .. " reactorGap=" .. tostring(reactorGap)
      .. " stackOffsetY=" .. tostring(stackOffsetY)
      .. " moduleOffsetX=" .. tostring(moduleOffsetX)
      .. " reactorOffsetX=" .. tostring(reactorOffsetX)
      .. " viewport=" .. tostring(slotW) .. "x" .. tostring(slotH)
  )

  if configuredCount > drawnModuleCount then
    local badgeW = math.max(18, math.floor(slotW * 0.16))
    local badgeH = ui.micro and 9 or 10
    local badgeX = slotX + slotW - badgeW - 1
    local badgeY = slotY + 1

    safeRect(badgeX, badgeY, badgeW, badgeH, C.panel2 or C.panel)
    GpuSafe.rectangle(args, badgeX, badgeY, badgeW, badgeH, C.border)
    drawTextCenter(badgeX, badgeY + math.max(0, math.floor((badgeH - textPixelHeight(1)) / 2)), badgeW, "x" .. tostring(configuredCount), C.muted, 1)
  end
end

return M
