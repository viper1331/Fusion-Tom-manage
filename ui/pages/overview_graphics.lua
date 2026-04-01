local M = {}

local ElectricFlowAnimation = assert(dofile("ui/animations/electric_flow.lua"))
local ReactorCoreAnimation = assert(dofile("ui/animations/reactor_core.lua"))
local GpuSafe = assert(dofile("ui/helpers/gpu_safe.lua"))
local renderLogKeys = {}
local STACK_CALIBRATION = {
  large = {
    moduleGapMul = 0.46,
    reactorGapMul = 2.28,
    stackOffsetY = 4,
    moduleOffsetX = 0,
    reactorOffsetX = 0,
    topPad = 6,
    bottomPad = 4,
    sidePad = 2,
    maxWFill = 0.92,
    maxHFill = 0.88,
  },
  compact = {
    moduleGapMul = 0.42,
    reactorGapMul = 2.00,
    stackOffsetY = 3,
    moduleOffsetX = 0,
    reactorOffsetX = 0,
    topPad = 5,
    bottomPad = 3,
    sidePad = 2,
    maxWFill = 0.90,
    maxHFill = 0.86,
  },
  micro = {
    moduleGapMul = 0.38,
    reactorGapMul = 1.70,
    stackOffsetY = 2,
    moduleOffsetX = 0,
    reactorOffsetX = 0,
    topPad = 4,
    bottomPad = 2,
    sidePad = 1,
    maxWFill = 0.88,
    maxHFill = 0.84,
  },
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
  local topPad = math.max(0, math.floor(profile.topPad or 0))
  local bottomPad = math.max(0, math.floor(profile.bottomPad or 0))
  local sidePad = math.max(0, math.floor(profile.sidePad or 0))
  local maxWFill = tonumber(profile.maxWFill) or 1
  local maxHFill = tonumber(profile.maxHFill) or 1

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
    topPad = topPad,
    bottomPad = bottomPad,
    sidePad = sidePad,
    maxWFill = maxWFill,
    maxHFill = maxHFill,
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
local DEGREE_SYMBOL = "\194\176"
local function formatMkValue(value)
  local n = tonumber(value)
  if not n then
    return "n/a"
  end
  return string.format("%.1f", n)
end

local function formatTemperatureLabel(profile, kind, mkValue)
  local valueText = formatMkValue(mkValue)
  local casePrefix = "T" .. DEGREE_SYMBOL .. " CASE "
  local corePrefix = "T" .. DEGREE_SYMBOL .. " CORE "

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
      return profile.mode == "large" and (casePrefix .. "n/a") or "CASE n/a"
    end
    return profile.mode == "large" and (corePrefix .. "n/a") or "CORE n/a"
  end

  if kind == "case" then
    return casePrefix .. valueText .. " MK"
  end
  return corePrefix .. valueText .. " MK"
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
  return name .. " " .. stateText
end

local function safeTextWidth(gpu, text, size)
  local ok, value = pcall(gpu.getTextLength, text, size, 0)
  if ok and type(value) == "number" and value > 0 then
    return math.floor(value)
  end
  return math.max(1, (#text) * (6 * math.max(1, size)))
end

local function fitTextToWidth(gpu, text, size, maxWidth)
  local raw = tostring(text or "")
  if raw == "" then
    return ""
  end

  if maxWidth <= 0 then
    return ""
  end

  if safeTextWidth(gpu, raw, size) <= maxWidth then
    return raw
  end

  local suffix = "..."
  local suffixW = safeTextWidth(gpu, suffix, size)
  if suffixW >= maxWidth then
    return ""
  end

  local trimmed = raw
  while #trimmed > 0 do
    trimmed = string.sub(trimmed, 1, #trimmed - 1)
    local candidate = trimmed .. suffix
    if safeTextWidth(gpu, candidate, size) <= maxWidth then
      return candidate
    end
  end

  return ""
end

local function drawCalloutLabel(args, spec)
  local gpu = args and args.gpu
  if not gpu then
    return
  end

  local rawText = tostring(spec.text or "")
  if rawText == "" then
    return
  end

  local size = math.max(1, math.floor(spec.size or 1))
  local viewportMinX = spec.slotX + 1
  local viewportMinY = spec.slotY + 1
  local viewportMaxX = spec.slotX + spec.slotW - 2
  local viewportMaxY = spec.slotY + spec.slotH - 2
  if viewportMaxX <= viewportMinX or viewportMaxY <= viewportMinY then
    return
  end

  local textH = math.max(1, spec.textPixelHeight and spec.textPixelHeight(size) or (8 * size))
  local annotationName = tostring(spec.name or "annotation")

  local anchorX = clampValue(math.floor(spec.anchorX), viewportMinX, viewportMaxX)
  local anchorY = clampValue(math.floor(spec.anchorY), viewportMinY, viewportMaxY)
  local elbowX = clampValue(math.floor(spec.elbowX), viewportMinX, viewportMaxX)
  local elbowY = clampValue(math.floor(spec.elbowY), viewportMinY, viewportMaxY)
  local side = spec.side == "left" and "left" or "right"
  local textGap = math.max(2, math.floor(spec.textGap or 3))
  local minHorizontal = math.max(5, math.floor(spec.minHorizontal or 8))
  local requestedEndLen = math.max(minHorizontal, math.floor(math.abs(spec.endLen or 20)))
  local requestedTextY = elbowY + (spec.textDy or 0)
  local textY = clampValue(math.floor(requestedTextY), viewportMinY, viewportMaxY - textH + 1)

  local function computeAvailableWidth(candidateSide)
    if candidateSide == "right" then
      return viewportMaxX - (elbowX + minHorizontal + textGap) + 1
    end
    return (elbowX - minHorizontal - textGap) - viewportMinX + 1
  end

  local function placementForSide(candidateSide)
    local availableWidth = computeAvailableWidth(candidateSide)
    if availableWidth < 4 then
      return nil
    end

    local fittedText = fitTextToWidth(gpu, rawText, size, availableWidth)
    if fittedText == "" then
      return nil
    end

    local fittedTextWidth = safeTextWidth(gpu, fittedText, size)
    local textX
    local endX
    local requestedTextX

    if candidateSide == "right" then
      local minTextX = elbowX + minHorizontal + textGap
      local maxTextX = viewportMaxX - fittedTextWidth + 1
      if maxTextX < minTextX then
        return nil
      end
      requestedTextX = elbowX + requestedEndLen + textGap
      textX = clampValue(requestedTextX, minTextX, maxTextX)
      endX = textX - textGap
    else
      local minTextX = viewportMinX
      local maxTextX = math.min(viewportMaxX - fittedTextWidth + 1, elbowX - minHorizontal - textGap - fittedTextWidth + 1)
      if maxTextX < minTextX then
        return nil
      end
      requestedTextX = elbowX - requestedEndLen - textGap - fittedTextWidth + 1
      textX = clampValue(requestedTextX, minTextX, maxTextX)
      endX = textX + fittedTextWidth + textGap - 1
    end

    endX = clampValue(endX, viewportMinX, viewportMaxX)
    return {
      side = candidateSide,
      text = fittedText,
      textW = fittedTextWidth,
      textX = textX,
      endX = endX,
      requestedTextX = requestedTextX,
      availableWidth = availableWidth,
    }
  end

  local placement = placementForSide(side)
  if not placement then
    local alternate = side == "right" and "left" or "right"
    placement = placementForSide(alternate)
    if placement then
      appendRuntimeLogOnce(
        args,
        "annotation_side_flip_" .. annotationName,
        annotationName .. "|" .. tostring(alternate) .. "|" .. tostring(viewportMinX) .. "|" .. tostring(viewportMaxX),
        "overview annotation side fallback: name=" .. annotationName .. " side=" .. side .. "->" .. alternate
      )
    end
  end

  if not placement then
    local bestSide = side
    local rightWidth = computeAvailableWidth("right")
    local leftWidth = computeAvailableWidth("left")
    if leftWidth > rightWidth then
      bestSide = "left"
    end

    local bestWidth = math.max(1, math.max(rightWidth, leftWidth))
    local emergencyText = fitTextToWidth(gpu, rawText, size, bestWidth)
    if emergencyText == "" then
      emergencyText = "."
    end
    local emergencyW = safeTextWidth(gpu, emergencyText, size)
    local emergencyX = clampValue(elbowX + textGap + 1, viewportMinX, viewportMaxX - emergencyW + 1)
    if bestSide == "left" then
      emergencyX = clampValue(elbowX - textGap - emergencyW - 1, viewportMinX, viewportMaxX - emergencyW + 1)
    end
    local emergencyEndX = bestSide == "right"
      and clampValue(emergencyX - textGap, viewportMinX, viewportMaxX)
      or clampValue(emergencyX + emergencyW + textGap - 1, viewportMinX, viewportMaxX)

    placement = {
      side = bestSide,
      text = emergencyText,
      textW = emergencyW,
      textX = emergencyX,
      endX = emergencyEndX,
      requestedTextX = emergencyX,
      availableWidth = bestWidth,
    }

    appendRuntimeLogOnce(
      args,
      "annotation_emergency_" .. annotationName,
      annotationName .. "|" .. tostring(bestSide) .. "|" .. tostring(bestWidth),
      "overview annotation emergency placement: name=" .. annotationName .. " side=" .. bestSide
    )
  end

  if placement.text ~= rawText then
    local trimKey = annotationName .. "|" .. placement.side .. "|" .. placement.text
    appendRuntimeLogOnce(
      args,
      "annotation_trim_" .. annotationName,
      trimKey,
      "overview annotation text trimmed: name=" .. annotationName
        .. " side=" .. placement.side
        .. " text=\"" .. placement.text .. "\""
    )
  end

  if placement.textX ~= placement.requestedTextX or textY ~= requestedTextY then
    local clampKey = table.concat({
      annotationName,
      tostring(placement.requestedTextX),
      tostring(requestedTextY),
      tostring(placement.textX),
      tostring(textY),
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
        .. " requested=" .. tostring(placement.requestedTextX) .. "," .. tostring(requestedTextY)
        .. " final=" .. tostring(placement.textX) .. "," .. tostring(textY)
        .. " viewport=" .. tostring(spec.slotX) .. "," .. tostring(spec.slotY)
        .. ":" .. tostring(spec.slotW) .. "x" .. tostring(spec.slotH)
    )
  end

  local endY = clampValue(elbowY, viewportMinY, viewportMaxY)

  local lineColor = spec.lineColor
  local lineThickness = math.max(1, math.floor(spec.lineThickness or 1))
  drawLineSafe(args, anchorX, anchorY, elbowX, elbowY, lineColor, lineThickness)
  drawLineSafe(args, elbowX, elbowY, placement.endX, endY, lineColor, lineThickness)

  local cap = math.max(1, math.floor(spec.capSize or 2))
  drawLineSafe(args, placement.endX, endY - cap, placement.endX, endY + cap, lineColor, 1)
  local anchorDot = math.max(1, math.floor(spec.anchorSize or (lineThickness + 1)))
  local anchorHalf = math.floor(anchorDot / 2)
  GpuSafe.filledRect(args, anchorX - anchorHalf, anchorY - anchorHalf, anchorDot, anchorDot, lineColor)

  if spec.textShadowColor then
    GpuSafe.drawText(args, placement.textX + 1, textY + 1, placement.text, spec.textShadowColor, nil, size, 0, {
      clipX = spec.slotX + 1,
      clipY = spec.slotY + 1,
      clipW = spec.slotW - 2,
      clipH = spec.slotH - 2,
    })
  end

  GpuSafe.drawText(args, placement.textX, textY, placement.text, spec.textColor, nil, size, 0, {
    clipX = spec.slotX + 1,
    clipY = spec.slotY + 1,
    clipW = spec.slotW - 2,
    clipH = spec.slotH - 2,
  })
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
      textGap = 2,
      capSize = 1,
      minHorizontal = 4,
      anchorSize = 2,
      textShadowColor = 0x88000000,
      case = {
        anchorRatioX = 0.77,
        anchorRatioY = 0.34,
        side = "right",
        elbowDx = 6,
        elbowDy = -5,
        endLen = 10,
        textDy = -5,
      },
      core = {
        anchorRatioX = 0.51,
        anchorRatioY = 0.53,
        side = "right",
        elbowDx = 6,
        elbowDy = 6,
        endLen = 10,
        textDy = -1,
      },
      ports = {
        anchorRatioY = 0.92,
        side = { "left", "right", "right" },
        elbowDx = { -4, 0, 4 },
        elbowDy = { 5, 6, 5 },
        endLen = { 8, 7, 8 },
        textDy = { 1, 1, 1 },
      },
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
      textGap = 3,
      capSize = 2,
      minHorizontal = 6,
      anchorSize = 2,
      textShadowColor = 0x88000000,
      case = {
        anchorRatioX = 0.77,
        anchorRatioY = 0.34,
        side = "right",
        elbowDx = 10,
        elbowDy = -9,
        endLen = 16,
        textDy = -7,
      },
      core = {
        anchorRatioX = 0.51,
        anchorRatioY = 0.53,
        side = "right",
        elbowDx = 10,
        elbowDy = 10,
        endLen = 18,
        textDy = 0,
      },
      ports = {
        anchorRatioY = 0.92,
        side = { "left", "right", "right" },
        elbowDx = { -8, 0, 8 },
        elbowDy = { 9, 10, 9 },
        endLen = { 14, 10, 14 },
        textDy = { 2, 2, 2 },
      },
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
    lineThickness = 1,
    textGap = 3,
    capSize = 2,
    minHorizontal = 8,
    anchorSize = 2,
    textShadowColor = 0x88000000,
    case = {
      anchorRatioX = 0.77,
      anchorRatioY = 0.34,
      side = "right",
      elbowDx = 16,
      elbowDy = -13,
      endLen = 24,
      textDy = -8,
    },
    core = {
      anchorRatioX = 0.51,
      anchorRatioY = 0.53,
      side = "right",
      elbowDx = 14,
      elbowDy = 15,
      endLen = 26,
      textDy = 1,
    },
    ports = {
      anchorRatioY = 0.92,
      side = { "left", "right", "right" },
      elbowDx = { -12, 0, 12 },
      elbowDy = { 12, 14, 12 },
      endLen = { 22, 14, 22 },
      textDy = { 3, 3, 3 },
    },
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
  local _ = drawTextCenter
  local profile = resolveAnnotationProfile(ui, slotW, slotH)
  if not profile.enabled then
    return
  end

  local tempColor = 0xFFE54E60
  local caseLabelText = formatTemperatureLabel(profile, "case", data and data.caseMK)
  local coreLabelText = formatTemperatureLabel(profile, "core", data and data.plasmaMK)

  local caseAnchorX = reactorX + math.floor(reactorW * profile.case.anchorRatioX)
  local caseAnchorY = reactorY + math.floor(reactorH * profile.case.anchorRatioY)
  local caseElbowX = clampValue(caseAnchorX + profile.case.elbowDx, slotX + 1, slotX + slotW - 2)
  local caseElbowY = clampValue(caseAnchorY + profile.case.elbowDy, slotY + 1, slotY + slotH - 2)

  drawCalloutLabel(args, {
    name = "CASE",
    text = caseLabelText,
    size = 1,
    slotX = slotX,
    slotY = slotY,
    slotW = slotW,
    slotH = slotH,
    side = profile.case.side,
    anchorX = caseAnchorX,
    anchorY = caseAnchorY,
    elbowX = caseElbowX,
    elbowY = caseElbowY,
    endLen = profile.case.endLen,
    textDy = profile.case.textDy,
    lineColor = tempColor,
    lineThickness = profile.lineThickness,
    textColor = tempColor,
    textShadowColor = profile.textShadowColor,
    textGap = profile.textGap,
    capSize = profile.capSize,
    minHorizontal = profile.minHorizontal,
    anchorSize = profile.anchorSize,
    textPixelHeight = textPixelHeight,
  })

  local coreAnchorX = reactorX + math.floor(reactorW * profile.core.anchorRatioX)
  local coreAnchorY = reactorY + math.floor(reactorH * profile.core.anchorRatioY)
  local coreElbowX = clampValue(coreAnchorX + profile.core.elbowDx, slotX + 1, slotX + slotW - 2)
  local coreElbowY = clampValue(coreAnchorY + profile.core.elbowDy, slotY + 1, slotY + slotH - 2)

  drawCalloutLabel(args, {
    name = "CORE",
    text = coreLabelText,
    size = 1,
    slotX = slotX,
    slotY = slotY,
    slotW = slotW,
    slotH = slotH,
    side = profile.core.side,
    anchorX = coreAnchorX,
    anchorY = coreAnchorY,
    elbowX = coreElbowX,
    elbowY = coreElbowY,
    endLen = profile.core.endLen,
    textDy = profile.core.textDy,
    lineColor = tempColor,
    lineThickness = profile.lineThickness,
    textColor = tempColor,
    textShadowColor = profile.textShadowColor,
    textGap = profile.textGap,
    capSize = profile.capSize,
    minHorizontal = profile.minHorizontal,
    anchorSize = profile.anchorSize,
    textPixelHeight = textPixelHeight,
  })

  local portProfile = profile.ports
  local portTelemetrySummary = {}
  for idx, channel in ipairs(PORT_CHANNELS) do
    local portAnchorX = reactorX + math.floor(reactorW * channel.ratio)
    local portAnchorY = reactorY + math.floor(reactorH * portProfile.anchorRatioY)
    local portElbowX = clampValue(portAnchorX + (portProfile.elbowDx[idx] or 0), slotX + 1, slotX + slotW - 2)
    local portElbowY = clampValue(portAnchorY + (portProfile.elbowDy[idx] or 0), slotY + 1, slotY + slotH - 2)
    local isOpen, source = resolvePortOpenState(data, channel.key)
    local labelText = formatPortStatus(profile, channel.key, isOpen)
    local side = portProfile.side[idx] or "right"

    drawCalloutLabel(args, {
      name = "FLOW_" .. string.upper(channel.key),
      text = labelText,
      size = 1,
      slotX = slotX,
      slotY = slotY,
      slotW = slotW,
      slotH = slotH,
      side = side,
      anchorX = portAnchorX,
      anchorY = portAnchorY,
      elbowX = portElbowX,
      elbowY = portElbowY,
      endLen = portProfile.endLen[idx] or 16,
      textDy = portProfile.textDy[idx] or 0,
      lineColor = channel.color,
      lineThickness = profile.lineThickness,
      textColor = channel.color,
      textShadowColor = profile.textShadowColor,
      textGap = profile.textGap,
      capSize = profile.capSize,
      minHorizontal = profile.minHorizontal,
      anchorSize = profile.anchorSize,
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
  local topPad = math.max(0, layout.topPad or stackCalibration.topPad or 0)
  local bottomPad = math.max(0, layout.bottomPad or stackCalibration.bottomPad or 0)
  local sidePad = math.max(0, layout.sidePad or stackCalibration.sidePad or 0)
  local viewX = slotX + sidePad
  local viewY = slotY + topPad
  local viewW = math.max(1, slotW - sidePad * 2)
  local viewH = math.max(1, slotH - topPad - bottomPad)
  if viewW < 1 or viewH < 1 then
    viewX = slotX
    viewY = slotY
    viewW = slotW
    viewH = slotH
    topPad = 0
    bottomPad = 0
    sidePad = 0
  end
  local modulesBlockH = 0

  if moduleVariant and drawnModuleCount > 0 then
    modulesBlockH = (moduleVariant.height * drawnModuleCount) + (moduleGap * math.max(0, drawnModuleCount - 1))
  end

  local totalH = reactorVariant.height + ((moduleVariant and drawnModuleCount > 0) and (reactorGap + modulesBlockH) or 0)
  local totalW = reactorVariant.width
  if moduleVariant and drawnModuleCount > 0 then
    totalW = math.max(totalW, moduleVariant.width)
  end
  local startY = viewY + math.floor((viewH - totalH) / 2) + stackOffsetY
  local minStartY = viewY
  local maxStartY = viewY + math.max(0, viewH - totalH)
  if startY < minStartY then
    startY = minStartY
  elseif startY > maxStartY then
    startY = maxStartY
  end

  local reactorX = viewX + math.floor((viewW - reactorVariant.width) / 2) + reactorOffsetX
  reactorX = clampValue(reactorX, viewX, viewX + math.max(0, viewW - reactorVariant.width))

  if moduleVariant and drawnModuleCount > 0 then
    local moduleBaseX = reactorX + math.floor((reactorVariant.width - moduleVariant.width) / 2) + moduleOffsetX
    local moduleMinX = viewX
    local moduleMaxX = viewX + math.max(0, viewW - moduleVariant.width)
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
  local fillW = totalW / math.max(1, viewW)
  local fillH = totalH / math.max(1, viewH)
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
    tostring(viewW),
    tostring(viewH),
    tostring(topPad),
    tostring(bottomPad),
    tostring(sidePad),
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
      .. " required=" .. tostring(totalW) .. "x" .. tostring(totalH)
      .. " availableViewport=" .. tostring(viewW) .. "x" .. tostring(viewH)
      .. " fillW=" .. string.format("%.2f", fillW)
      .. " fillH=" .. string.format("%.2f", fillH)
      .. " scenePadding=" .. tostring(topPad) .. "," .. tostring(bottomPad) .. "," .. tostring(sidePad)
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
