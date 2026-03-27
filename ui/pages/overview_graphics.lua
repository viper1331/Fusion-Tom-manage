local M = {}

local ElectricFlowAnimation = assert(dofile("ui/animations/electric_flow.lua"))
local ReactorCoreAnimation = assert(dofile("ui/animations/reactor_core.lua"))
local GpuSafe = assert(dofile("ui/helpers/gpu_safe.lua"))
local renderLogKeys = {}

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
      moduleGap = math.max(1, math.floor(ui.smallPad * 0.45)),
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
      drawImageSafe(args, moduleVariant.image, moduleX, moduleY)
      drawModuleCableFluxAt(args, moduleX, moduleY, moduleVariant.width, moduleVariant.height, data)
    end
    startY = startY + modulesBlockH + gap
  else
    local moduleTextY = startY + math.max(0, math.floor((ui.smallPad + textPixelHeight(1)) / 2))
    drawTextCenter(slotX, moduleTextY, slotW, "LASER x" .. tostring(configuredCount), C.muted, 1)
    startY = startY + ui.smallPad + textPixelHeight(1) + ui.smallPad
  end

  local reactorX = slotX + math.floor((slotW - reactorVariant.width) / 2)
  drawImageSafe(args, reactorVariant.image, reactorX, startY)
  drawReactorCoreAnimationAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawReactorRightCableFluxAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawReactorBottomGasFluxAt(args, reactorX, startY, reactorVariant.width, reactorVariant.height, data)

  local renderedMode = moduleVariant and drawnModuleCount > 0 and "pair" or "reactor-only"
  local renderedKey = table.concat({
    tostring(renderedMode),
    tostring(reactorVariant and reactorVariant.name or "none"),
    tostring(moduleVariant and moduleVariant.name or "none"),
    tostring(reactorVariant and reactorVariant.width or "n/a"),
    tostring(reactorVariant and reactorVariant.height or "n/a"),
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
