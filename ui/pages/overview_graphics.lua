local M = {}

local ElectricFlowAnimation = assert(dofile("ui/animations/electric_flow.lua"))
local ReactorCoreAnimation = assert(dofile("ui/animations/reactor_core.lua"))
local GpuSafe = assert(dofile("ui/helpers/gpu_safe.lua"))
local CalloutRenderer = assert(dofile("ui/helpers/callout_renderer.lua"))
local OverviewCalibration = assert(dofile("ui/pages/overview_calibration.lua"))
local OverviewAnimationState = assert(dofile("core/runtime/overview_animation_state.lua"))
local renderLogKeys = {}
local lastViewportKey = nil

local function resolveStackCalibration(ui, state)
  local profile = OverviewCalibration.resolveStackProfile(ui)

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

local function resolveResponsiveMode(ui, responsiveOptions)
  local mode = responsiveOptions and responsiveOptions.responsiveMode
  if mode == "large"
    or mode == "compact"
    or mode == "micro"
    or mode == "ultra_compact_5x4_ou_6x4"
    or mode == "ultra_compact_4x4" then
    return mode
  end
  if ui and (ui.overviewResponsiveMode == "ultra_compact_5x4_ou_6x4" or ui.overviewResponsiveMode == "ultra_compact_4x4") then
    return ui.overviewResponsiveMode
  end
  if ui and (ui.overviewScreenClass == "ultra_compact_5x4_ou_6x4" or ui.overviewScreenClass == "ultra_compact_4x4") then
    return ui.overviewScreenClass
  end
  if ui and ui.micro then
    return "micro"
  end
  if ui and ui.compact then
    return "compact"
  end
  return "large"
end

local function resolveResponsiveFactor(mode)
  if mode == "ultra_compact_4x4" then
    return 0.34, "survival"
  end
  if mode == "ultra_compact_5x4_ou_6x4" then
    return 0.48, "ultra"
  end
  if mode == "micro" then
    return 0.62, "minimal"
  end
  if mode == "compact" then
    return 0.82, "lite"
  end
  return 1.00, "normal"
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

local function drawModuleCableFluxAt(args, x, y, w, h, data, animationContext)
  ElectricFlowAnimation.drawModuleFlux(args, x, y, w, h, data, animationContext)
end

local function drawReactorRightCableFluxAt(args, x, y, w, h, data, animationContext)
  ElectricFlowAnimation.drawReactorRightFlux(args, x, y, w, h, data, animationContext)
end

local function drawReactorBottomGasFluxAt(args, x, y, w, h, data, animationContext)
  ElectricFlowAnimation.drawReactorBottomFlux(args, x, y, w, h, data, animationContext)
end

local function drawReactorCoreAnimationAt(args, x, y, w, h, data, animationContext)
  ReactorCoreAnimation.draw(args, x, y, w, h, data, animationContext)
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

local DEGREE_SYMBOL = "\194\176"
local function formatMkValue(value)
  local n = tonumber(value)
  if not n then
    return "n/a"
  end
  return string.format("%.1f", n)
end

local function formatTemperatureLabel(_profile, kind, mkValue)
  local valueText = formatMkValue(mkValue)
  local casePrefix = "T" .. DEGREE_SYMBOL .. " CASE "
  local corePrefix = "T" .. DEGREE_SYMBOL .. " CORE "

  if valueText == "n/a" then
    if kind == "case" then
      return casePrefix .. "n/a"
    end
    return corePrefix .. "n/a"
  end

  if kind == "case" then
    return casePrefix .. valueText .. " MK"
  end
  return corePrefix .. valueText .. " MK"
end
local function formatPortStatus(profile, channelKey, isOpen)
  local stateText = isOpen and profile.portStateOpen or profile.portStateClosed
  local name = profile.portNames[channelKey] or string.upper(channelKey)
  return name .. " " .. stateText
end

local function normalizeReservedRects(reservedRects)
  return CalloutRenderer.normalizeReservedRects(reservedRects)
end

local function drawCalloutLabel(args, spec)
  return CalloutRenderer.drawCalloutLabel(args, spec)
end

local function logAnimationContext(args, animationContext)
  if type(animationContext) ~= "table" then
    return
  end

  local core = animationContext.core or {}
  local coreKey = table.concat({
    tostring(core.state or "n/a"),
    tostring(core.reason or "n/a"),
    tostring(core.formed and "1" or "0"),
    tostring(core.ignited and "1" or "0"),
    tostring(math.floor((tonumber(core.plasmaMK) or 0) * 10 + 0.5) / 10),
    tostring(core.status or "n/a"),
    tostring(core.alerts or "n/a"),
  }, "|")
  appendRuntimeLogOnce(
    args,
    "overview_animation_core_state",
    coreKey,
    "animation core:"
      .. " state=" .. tostring(core.state or "n/a")
      .. " reason=" .. tostring(core.reason or "n/a")
      .. " formed=" .. tostring(core.formed == true)
      .. " ignited=" .. tostring(core.ignited == true)
      .. " plasmaMK=" .. string.format("%.1f", tonumber(core.plasmaMK) or 0)
      .. " status=" .. tostring(core.status or "n/a")
      .. " alerts=" .. tostring(core.alerts or "n/a")
  )

  local gas = animationContext.gas or {}
  local tri = gas.tritium or {}
  local dt = gas.dtFuel or {}
  local deu = gas.deuterium or {}
  local gasKey = table.concat({
    tostring(tri.open and "1" or "0"),
    tostring(tri.source or "n/a"),
    tostring(dt.open and "1" or "0"),
    tostring(dt.source or "n/a"),
    tostring(deu.open and "1" or "0"),
    tostring(deu.source or "n/a"),
  }, "|")
  appendRuntimeLogOnce(
    args,
    "overview_animation_gas_state",
    gasKey,
    "animation gas:"
      .. " tritium=" .. tostring(tri.open and "open" or "closed")
      .. " source=" .. tostring(tri.source or "n/a")
      .. " dtFuel=" .. tostring(dt.open and "open" or "closed")
      .. " source=" .. tostring(dt.source or "n/a")
      .. " deuterium=" .. tostring(deu.open and "open" or "closed")
      .. " source=" .. tostring(deu.source or "n/a")
  )

  local electric = animationContext.electric or {}
  local electricKey = table.concat({
    tostring(electric.state or "n/a"),
    tostring(electric.reason or "n/a"),
    tostring(math.floor((tonumber(electric.energyPct) or 0) + 0.5)),
    tostring(math.floor((tonumber(electric.amplifierPct) or 0) * 100 + 0.5)),
    tostring(electric.laserReady and "1" or "0"),
  }, "|")
  appendRuntimeLogOnce(
    args,
    "overview_animation_electric_state",
    electricKey,
    "animation electric:"
      .. " state=" .. tostring(electric.state or "n/a")
      .. " reason=" .. tostring(electric.reason or "n/a")
      .. " energyPct=" .. string.format("%.1f", tonumber(electric.energyPct) or 0)
      .. " amplifierPct=" .. string.format("%.2f", tonumber(electric.amplifierPct) or 0)
      .. " laserReady=" .. tostring(electric.laserReady == true)
  )
end

local function resolveAnnotationProfile(ui, slotW, slotH)
  return OverviewCalibration.resolveAnnotationProfile(ui, slotW, slotH)
end

local function drawSceneAnnotations(args, drawTextCenter, textPixelHeight, slotX, slotY, slotW, slotH, reactorX, reactorY, reactorW, reactorH, data, animationContext, responsiveOptions)
  local ui = args.ui
  local _ = drawTextCenter
  local profile = resolveAnnotationProfile(ui, slotW, slotH)
  if not profile.enabled then
    if profile.reason == "ultra_compact_callouts_disabled" then
      appendRuntimeLogOnce(
        args,
        "overview_callouts_ultra_disabled",
        tostring(profile.mode or "unknown"),
        "callouts disabled for ultra compact"
          .. " mode=" .. tostring(profile.mode or "unknown")
      )
    end
    return
  end

  local reservedRects = responsiveOptions and responsiveOptions.reservedRects or nil
  local sceneViewport = responsiveOptions and responsiveOptions.sceneViewport or nil
  local sceneViewportW = sceneViewport and tonumber(sceneViewport.w) or slotW
  local responsiveFactor = 1.00
  if profile.mode == "compact" and sceneViewportW < 170 then
    responsiveFactor = 0.90
  elseif profile.mode == "micro" and sceneViewportW < 130 then
    responsiveFactor = 0.78
  end

  local function scaleSigned(value, minAbs)
    local raw = tonumber(value) or 0
    local sign = raw < 0 and -1 or 1
    local scaled = math.floor(math.abs(raw) * responsiveFactor + 0.5)
    if math.abs(raw) > 0 then
      scaled = math.max(minAbs or 1, scaled)
    end
    return sign * scaled
  end

  local function scaleLength(value, minAbs)
    local raw = math.abs(tonumber(value) or 0)
    local scaled = math.floor(raw * responsiveFactor + 0.5)
    return math.max(minAbs or 4, scaled)
  end

  local tempColor = 0xFFE54E60
  local caseLabelText = formatTemperatureLabel(profile, "case", data and data.caseMK)
  local coreLabelText = formatTemperatureLabel(profile, "core", data and data.plasmaMK)

  local caseAnchorX = reactorX + math.floor(reactorW * profile.case.anchorRatioX)
  local caseAnchorY = reactorY + math.floor(reactorH * profile.case.anchorRatioY)
  local caseElbowX = clampValue(caseAnchorX + scaleSigned(profile.case.elbowDx, 2), slotX + 1, slotX + slotW - 2)
  local caseElbowY = clampValue(caseAnchorY + scaleSigned(profile.case.elbowDy, 2), slotY + 1, slotY + slotH - 2)

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
    endLen = scaleLength(profile.case.endLen, profile.minHorizontal),
    textDy = scaleSigned(profile.case.textDy, 1),
    lineColor = tempColor,
    lineThickness = profile.lineThickness,
    textColor = tempColor,
    textShadowColor = profile.textShadowColor,
    textGap = profile.textGap,
    capSize = profile.capSize,
    minHorizontal = profile.minHorizontal,
    anchorSize = profile.anchorSize,
    textPixelHeight = textPixelHeight,
    reservedRects = reservedRects,
  })

  local coreAnchorX = reactorX + math.floor(reactorW * profile.core.anchorRatioX)
  local coreAnchorY = reactorY + math.floor(reactorH * profile.core.anchorRatioY)
  local coreElbowX = clampValue(coreAnchorX + scaleSigned(profile.core.elbowDx, 2), slotX + 1, slotX + slotW - 2)
  local coreElbowY = clampValue(coreAnchorY + scaleSigned(profile.core.elbowDy, 2), slotY + 1, slotY + slotH - 2)

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
    endLen = scaleLength(profile.core.endLen, profile.minHorizontal),
    textDy = scaleSigned(profile.core.textDy, 1),
    lineColor = tempColor,
    lineThickness = profile.lineThickness,
    textColor = tempColor,
    textShadowColor = profile.textShadowColor,
    textGap = profile.textGap,
    capSize = profile.capSize,
    minHorizontal = profile.minHorizontal,
    anchorSize = profile.anchorSize,
    textPixelHeight = textPixelHeight,
    reservedRects = reservedRects,
  })

  local portProfile = profile.ports
  local portChannels = OverviewCalibration.getPortChannels()
  local portTelemetrySummary = {}
  for idx, channel in ipairs(portChannels) do
    local portAnchorX = reactorX + math.floor(reactorW * channel.ratio)
    local portAnchorY = reactorY + math.floor(reactorH * portProfile.anchorRatioY)
    local portElbowX = clampValue(portAnchorX + scaleSigned(portProfile.elbowDx[idx] or 0, 1), slotX + 1, slotX + slotW - 2)
    local portElbowY = clampValue(portAnchorY + scaleSigned(portProfile.elbowDy[idx] or 0, 1), slotY + 1, slotY + slotH - 2)
    local gasState = animationContext and animationContext.gas and animationContext.gas[channel.key] or {}
    local isOpen = gasState.open == true
    local source = gasState.source or "n/a"
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
      endLen = scaleLength(portProfile.endLen[idx] or 16, profile.minHorizontal),
      textDy = scaleSigned(portProfile.textDy[idx] or 0, 1),
      lineColor = channel.color,
      lineThickness = profile.lineThickness,
      textColor = channel.color,
      textShadowColor = profile.textShadowColor,
      textGap = profile.textGap,
      capSize = profile.capSize,
      minHorizontal = profile.minHorizontal,
      anchorSize = profile.anchorSize,
      textPixelHeight = textPixelHeight,
      reservedRects = reservedRects,
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
  local responsiveOptions = type(args.responsiveOptions) == "table" and args.responsiveOptions or nil
  local responsiveMode = resolveResponsiveMode(ui, responsiveOptions)
  local responsiveFactor, responsiveEffectLevel = resolveResponsiveFactor(responsiveMode)
  local reservedRects = normalizeReservedRects(responsiveOptions and responsiveOptions.reservedRects or nil)
  local sceneViewport = responsiveOptions and responsiveOptions.sceneViewport or nil
  local stackCalibration = resolveStackCalibration(ui, args.state)
  args.responsiveMode = responsiveMode
  args.responsiveFactor = responsiveFactor
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

  local viewportKey = table.concat({
    tostring(slotX),
    tostring(slotY),
    tostring(slotW),
    tostring(slotH),
    tostring(responsiveMode),
  }, "|")
  if viewportKey ~= lastViewportKey then
    appendRuntimeLog(
      args,
      "overview resize recompute: viewportKey changed"
        .. " old=" .. tostring(lastViewportKey or "none")
        .. " new=" .. viewportKey
    )
    CalloutRenderer.resetPlacementCache()
    lastViewportKey = viewportKey
  end

  local viewportLogRect = sceneViewport or { x = slotX, y = slotY, w = slotW, h = slotH }
  local responsiveContextKey = table.concat({
    tostring(responsiveMode),
    tostring(viewportLogRect.x),
    tostring(viewportLogRect.y),
    tostring(viewportLogRect.w),
    tostring(viewportLogRect.h),
    tostring(#reservedRects),
  }, "|")
  appendRuntimeLogOnce(
    args,
    "overview_responsive_context",
    responsiveContextKey,
    "overview responsive: mode=" .. tostring(responsiveMode)
      .. " viewport=" .. tostring(viewportLogRect.x) .. "," .. tostring(viewportLogRect.y)
      .. ":" .. tostring(viewportLogRect.w) .. "x" .. tostring(viewportLogRect.h)
      .. " reserved=" .. tostring(#reservedRects)
  )
  appendRuntimeLogOnce(
    args,
    "overview_degradation_profile",
    tostring(responsiveMode) .. "|" .. string.format("%.2f", responsiveFactor),
    "overview degradation: effects=" .. tostring(responsiveEffectLevel)
      .. " responsiveFactor=" .. string.format("%.2f", responsiveFactor)
  )
  if responsiveMode == "ultra_compact_5x4_ou_6x4" or responsiveMode == "ultra_compact_4x4" then
    appendRuntimeLogOnce(
      args,
      "overview_layout_degradation_ultra",
      tostring(responsiveMode),
      "layout degradation level=ultra"
        .. " class=" .. tostring(responsiveMode)
    )
  end

  local configuredModuleCount = math.max(1, tonumber(control.laserModuleCount) or 1)
  local layout = forcedLayout
  if not layout or not layout.reactor then
    -- Pair scene remains preferred. chooseStackLayout already ranks pair over reactor-only.
    layout = chooseStackLayout(slotW, slotH, configuredModuleCount, {
      preferPair = sceneMode == "pair",
      responsiveMode = responsiveMode,
    })
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
      fallbackReason = "renderer_fallback_reactor_only",
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
    if sceneMode == "pair" then
      appendRuntimeLogOnce(
        args,
        "overview_pair_layout_missing",
        table.concat({
          tostring(slotW),
          tostring(slotH),
          tostring(reactorPresent),
          tostring(laserPresent),
        }, "|"),
        "overview layout fallback: requestedSceneMode=pair renderedSceneMode=none reason=no_reactor_layout"
      )
    end
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
  local animationContext = OverviewAnimationState.resolveContext(data)
  logAnimationContext(args, animationContext)
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
      drawModuleCableFluxAt(args, moduleX, moduleY, moduleVariant.width, moduleVariant.height, data, animationContext)
    end
    startY = startY + modulesBlockH + reactorGap
  else
    local moduleTextY = startY + math.max(0, math.floor((ui.smallPad + textPixelHeight(1)) / 2))
    drawTextCenter(slotX, moduleTextY, slotW, "LASER x" .. tostring(configuredCount), C.muted, 1)
    startY = startY + math.max(ui.smallPad, reactorGap - 1) + textPixelHeight(1) + ui.smallPad
  end

  drawImageSafe(args, reactorVariant.image, reactorX, startY)
  drawReactorCoreAnimationAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data, animationContext)
  drawReactorRightCableFluxAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data, animationContext)
  drawReactorBottomGasFluxAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data, animationContext)
  drawSceneAnnotations(
    args,
    drawTextCenter,
    textPixelHeight,
    slotX,
    slotY,
    slotW,
    slotH,
    reactorX,
    startY,
    reactorVariant.width,
    reactorVariant.height,
    data,
    animationContext,
    {
      reservedRects = reservedRects,
      responsiveMode = responsiveMode,
      sceneViewport = { x = viewX, y = viewY, w = viewW, h = viewH },
    }
  )

  local renderedMode = moduleVariant and drawnModuleCount > 0 and "pair" or "reactor-only"
  if sceneMode == "pair" and renderedMode ~= "pair" then
    local fallbackReason = tostring(layout and (layout.fallbackReason or layout.selectionReason or layout.selectionClass) or "layout_without_pair")
    local fallbackKey = table.concat({
      tostring(sceneMode),
      tostring(renderedMode),
      tostring(slotW),
      tostring(slotH),
      tostring(configuredCount),
      tostring(drawnModuleCount),
      fallbackReason,
      tostring(responsiveMode),
    }, "|")
    appendRuntimeLogOnce(
      args,
      "overview_pair_to_reactor_fallback",
      fallbackKey,
      "overview layout fallback:"
        .. " requestedSceneMode=pair"
        .. " renderedSceneMode=" .. tostring(renderedMode)
        .. " reason=" .. fallbackReason
        .. " responsiveMode=" .. tostring(responsiveMode)
        .. " configuredModules=" .. tostring(configuredCount)
        .. " drawnModules=" .. tostring(drawnModuleCount)
        .. " viewport=" .. tostring(viewW) .. "x" .. tostring(viewH)
    )
  end
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
      .. " responsiveMode=" .. tostring(responsiveMode)
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
