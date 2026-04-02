local M = {}

function M.create(args)
  local fs = args.fs
  local gpu = args.gpu
  local C = args.colors
  local state = args.state
  local images = args.images
  local CONTROL = args.control
  local OverviewCalibration = args.overviewCalibration
  local appendUiRuntimeLog = args.appendUiRuntimeLog
  local ASSET_REACTOR_VARIANTS = args.assetReactorVariants or {}
  local ASSET_LASER_MODULE_VARIANTS = args.assetLaserModuleVariants or {}
  local displayState = args.displayState or {}
  local MIN_VALID_SCREEN_W = tonumber(args.minValidScreenW) or 96
  local MIN_VALID_SCREEN_H = tonumber(args.minValidScreenH) or 180
  local MIN_VALID_VIEWPORT_W = tonumber(args.minValidViewportW) or 48
  local MIN_VALID_VIEWPORT_H = tonumber(args.minValidViewportH) or 72
  local sv = args.sv

  local ui = nil
  local function syncUi()
    ui = args.getUi and args.getUi() or args.ui
    return ui
  end

  syncUi()
local function isVramError(err)
  local low = string.lower(tostring(err or ""))
  return string.find(low, "vram", 1, true) ~= nil
    or string.find(low, "alloc failed", 1, true) ~= nil
    or string.find(low, "out of memory", 1, true) ~= nil
end

local function readAllBytes(path)
  if type(path) ~= "string" or path == "" then
    return nil, "chemin asset invalide: " .. tostring(path)
  end

  if not fs.exists(path) then
    return nil, "fichier absent: " .. tostring(path)
  end

  local f = fs.open(path, "rb")
  if not f then
    return nil, "impossible d'ouvrir: " .. tostring(path)
  end

  local data = f.readAll()
  f.close()

  if not data or #data == 0 then
    return nil, "fichier vide: " .. tostring(path)
  end

  return { string.byte(data, 1, #data) }
end

local function loadPng(path)
  local bytes, err = readAllBytes(path)
  if not bytes then
    return nil, err
  end

  local ok, img, decodeErr = pcall(function()
    return gpu.decodeImage(table.unpack(bytes))
  end)

  if not ok then
    return nil, img
  end

  if not img then
    return nil, decodeErr or ("decode failed (nil image): " .. tostring(path))
  end

  return img
end

local function sortVariantList(list)
  table.sort(list, function(a, b)
    local areaA = a.width * a.height
    local areaB = b.width * b.height
    if areaA == areaB then
      return a.width < b.width
    end
    return areaA < areaB
  end)
end

local function sortReactorVariants()
  sortVariantList(images.reactorVariants)
end

local function sortLaserModuleVariants()
  sortVariantList(images.laserModuleVariants)
end

local ASSET_TIER_ORDER = { "micro", "tiny", "xsmall", "small2", "small", "medium", "large" }
local ASSET_TIER_INDEX = {}
for index, tier in ipairs(ASSET_TIER_ORDER) do
  ASSET_TIER_INDEX[tier] = index
end

local function compactError(err)
  local msg = tostring(err or "unknown")
  local idx = string.find(msg, "\n", 1, true)
  if idx then
    return string.sub(msg, 1, idx - 1)
  end
  return msg
end

local function normalizeTierName(name)
  local low = string.lower(tostring(name or ""))
  if ASSET_TIER_INDEX[low] then
    return low
  end
  return nil
end

local function resolveReactorTier(name)
  local low = string.lower(tostring(name or ""))
  if string.sub(low, 1, 5) == "trim_" then
    local trimmed = string.sub(low, 6)
    local tier = normalizeTierName(trimmed)
    if tier then
      return tier
    end
  end

  local direct = normalizeTierName(low)
  if direct then
    return direct
  end

  if low == "base" then
    return "large"
  end
  return nil
end

local function resolveModuleTier(name)
  local low = string.lower(tostring(name or ""))
  return normalizeTierName(low)
end

local function normalizeAssetVariants(rawVariants, kindLabel)
  local out = {}
  for index, variant in ipairs(rawVariants or {}) do
    local name = nil
    local path = nil
    if type(variant) == "table" then
      name = variant.name
      path = variant.path
    elseif type(variant) == "string" then
      name = (kindLabel or "variant") .. "_" .. tostring(index)
      path = variant
    end

    if type(path) == "string" and path ~= "" then
      local variantName = name or ((kindLabel or "variant") .. "_" .. tostring(index))
      local tier = kindLabel == "reactor" and resolveReactorTier(variantName) or resolveModuleTier(variantName)
      if not tier then
        appendUiRuntimeLog("asset " .. tostring(kindLabel) .. ": variant ignored (unknown tier): " .. tostring(variantName))
      else
        out[#out + 1] = {
          index = index,
          name = variantName,
          path = path,
          tier = tier,
          kind = kindLabel,
        }
      end
    end
  end
  return out
end

local function preferredSceneTier()
  syncUi()
  if not ui then
    return "small2"
  end
  if ui.micro then
    return "tiny"
  end
  if ui.compact then
    return "small2"
  end
  if ui.sw >= 1300 and ui.sh >= 900 then
    return "large"
  end
  return "medium"
end

local function estimateOverviewSceneViewport()
  syncUi()
  if not ui or not ui.layout or not ui.layout.body then
    return 0, 0
  end

  local body = ui.layout.body
  if ui.micro then
    local statsH = math.max(18, math.floor(body.h * 0.10))
    local imageH = body.h - statsH - ui.gap
    if imageH + ui.gap >= body.h then
      imageH = body.h
    end
    return body.w - 2, imageH - 2
  end

  local alertsH = ui.compact and math.max(28, sv(34)) or math.max(34, sv(42))
  local mainW = body.w
  local mainH = body.h - alertsH - ui.gap
  local innerW = mainW - ui.pad * 2 - 2
  local innerH = mainH - sv(40) - 2
  return innerW, innerH
end

local function screenSizeRejectReason(sw, sh)
  local width = tonumber(sw) or 0
  local height = tonumber(sh) or 0

  if width <= 0 or height <= 0 then
    return "zero_size"
  end
  if width < 8 or height < 8 then
    return "absurd_screen_size"
  end

  return nil
end

local function assetReloadScreenRejectReason(sw, sh)
  local width = tonumber(sw) or 0
  local height = tonumber(sh) or 0
  if width < MIN_VALID_SCREEN_W or height < MIN_VALID_SCREEN_H then
    return "screen_too_small_for_assets"
  end
  return nil
end

local function viewportRejectReason(viewportW, viewportH)
  local width = tonumber(viewportW) or 0
  local height = tonumber(viewportH) or 0

  if width <= 0 or height <= 0 then
    return "zero_viewport"
  end
  if width < MIN_VALID_VIEWPORT_W or height < MIN_VALID_VIEWPORT_H then
    return "viewport_too_small_for_assets"
  end

  return nil
end

local function buildTierVariantMap(variants, kindLabel)
  local map = {}
  for _, variant in ipairs(variants or {}) do
    local tier = variant.tier
    if tier and ASSET_TIER_INDEX[tier] then
      if not map[tier] then
        map[tier] = {}
      end
      map[tier][#map[tier] + 1] = variant
    end
  end

  for _, tier in ipairs(ASSET_TIER_ORDER) do
    if map[tier] then
      table.sort(map[tier], function(a, b)
        if kindLabel == "reactor" then
          local aTrim = string.find(string.lower(a.name), "trim_", 1, true) and 0 or 1
          local bTrim = string.find(string.lower(b.name), "trim_", 1, true) and 0 or 1
          if aTrim ~= bTrim then
            return aTrim < bTrim
          end
        end
        return tostring(a.name) < tostring(b.name)
      end)
    end
  end

  return map
end

local function addTierCandidate(out, seen, tierMap, tier, reason)
  if not tier or seen[tier] then
    return
  end
  local variants = tierMap[tier]
  if not variants or #variants < 1 then
    return
  end
  out[#out + 1] = {
    tier = tier,
    reason = reason or "fallback",
  }
  seen[tier] = true
end

local function buildReactorTierCandidates(preferredTier, reactorByTier)
  local out = {}
  local seen = {}
  local preferredIndex = ASSET_TIER_INDEX[preferredTier] or ASSET_TIER_INDEX.small2

  addTierCandidate(out, seen, reactorByTier, ASSET_TIER_ORDER[preferredIndex], "exact")
  addTierCandidate(out, seen, reactorByTier, ASSET_TIER_ORDER[preferredIndex - 1], "nearest")
  addTierCandidate(out, seen, reactorByTier, ASSET_TIER_ORDER[preferredIndex + 1], "nearest")

  for index = preferredIndex - 2, 1, -1 do
    addTierCandidate(out, seen, reactorByTier, ASSET_TIER_ORDER[index], "lower_fallback")
  end
  for index = preferredIndex + 2, #ASSET_TIER_ORDER do
    addTierCandidate(out, seen, reactorByTier, ASSET_TIER_ORDER[index], "upper_fallback")
  end

  return out
end

local function buildModuleTierCandidates(reactorTier, moduleByTier)
  local out = {}
  local seen = {}
  local reactorIndex = ASSET_TIER_INDEX[reactorTier] or ASSET_TIER_INDEX.small2

  addTierCandidate(out, seen, moduleByTier, ASSET_TIER_ORDER[reactorIndex], "exact")
  addTierCandidate(out, seen, moduleByTier, ASSET_TIER_ORDER[reactorIndex - 1], "nearest")
  addTierCandidate(out, seen, moduleByTier, ASSET_TIER_ORDER[reactorIndex + 1], "nearest")

  for index = reactorIndex - 2, 1, -1 do
    addTierCandidate(out, seen, moduleByTier, ASSET_TIER_ORDER[index], "lower_fallback")
  end
  for index = reactorIndex + 2, #ASSET_TIER_ORDER do
    addTierCandidate(out, seen, moduleByTier, ASSET_TIER_ORDER[index], "upper_fallback")
  end

  return out
end

local function buildTierPairCandidates(preferredTier, reactorByTier, moduleByTier)
  local out = {}
  local reactorCandidates = buildReactorTierCandidates(preferredTier, reactorByTier)

  for _, reactorCandidate in ipairs(reactorCandidates) do
    local moduleCandidates = buildModuleTierCandidates(reactorCandidate.tier, moduleByTier)
    for _, moduleCandidate in ipairs(moduleCandidates) do
      out[#out + 1] = {
        reactorTier = reactorCandidate.tier,
        reactorReason = reactorCandidate.reason,
        moduleTier = moduleCandidate.tier,
        moduleReason = moduleCandidate.reason,
        requestedModuleTier = reactorCandidate.tier,
      }
    end
  end

  return out
end

local function isTierPairCompatible(reactorTier, moduleTier)
  local reactorIndex = ASSET_TIER_INDEX[reactorTier] or 0
  local moduleIndex = ASSET_TIER_INDEX[moduleTier] or 0
  if reactorIndex == 0 or moduleIndex == 0 then
    return false
  end
  return math.abs(reactorIndex - moduleIndex) <= 2
end

local function resolveOverviewStackSpacing(options)
  syncUi()
  -- Keep a single source of truth for OVERVIEW spacing calibration.
  local profile = OverviewCalibration.resolveStackProfile(ui)
  local smallPad = ui and ui.smallPad or 0
  local spacingScale = tonumber(options and options.spacingScale) or 1.0
  if spacingScale <= 0 then
    spacingScale = 1.0
  end
  local moduleGap = math.max(1, math.floor((smallPad * (profile.moduleGapMul or 0)) * spacingScale + 0.5))
  local reactorGap = math.max(2, math.floor((smallPad * (profile.reactorGapMul or 0)) * spacingScale + 0.5))
  local stackOffsetY = math.floor((profile.stackOffsetY or 0) * spacingScale + 0.5)

  return {
    moduleGap = moduleGap,
    reactorGap = reactorGap,
    stackOffsetY = stackOffsetY,
    moduleOffsetX = profile.moduleOffsetX or 0,
    reactorOffsetX = profile.reactorOffsetX or 0,
    topPad = profile.topPad or 0,
    bottomPad = profile.bottomPad or 0,
    sidePad = profile.sidePad or 0,
    maxWFill = profile.maxWFill or 1,
    maxHFill = profile.maxHFill or 1,
    spacingScale = spacingScale,
  }
end

-- Forward declaration: used by viewport fit helpers defined above
-- the concrete implementation lower in this module.
local resolveOverviewVisualBounds

local function reactorFitsViewport(reactorVariant, viewportW, viewportH)
  if not reactorVariant then
    return false
  end
  if not viewportW or not viewportH then
    return true
  end
  local spacing = resolveOverviewStackSpacing()
  local visual = resolveOverviewVisualBounds(viewportW, viewportH, spacing)
  return reactorVariant.width <= visual.availableW and reactorVariant.height <= visual.availableH
end

local function pairFitsViewport(reactorVariant, moduleVariant, viewportW, viewportH)
  if not reactorVariant then
    return false, 0, 0
  end

  local spacing = resolveOverviewStackSpacing()
  local gap = spacing.reactorGap
  local requiredW = reactorVariant.width
  local requiredH = reactorVariant.height

  if moduleVariant then
    requiredW = math.max(requiredW, moduleVariant.width)
    requiredH = requiredH + gap + moduleVariant.height
  end

  if not viewportW or not viewportH then
    return true, requiredW, requiredH, requiredW, requiredH
  end
  local spacingVisual = resolveOverviewVisualBounds(viewportW, viewportH, spacing)
  local availableW = spacingVisual.availableW
  local availableH = spacingVisual.availableH
  return requiredW <= availableW and requiredH <= availableH, requiredW, requiredH, availableW, availableH
end

local function shouldReplaceReactorFallback(currentFallback, candidateFallback, preferredTier, viewportW, viewportH)
  if not candidateFallback or not candidateFallback.reactor then
    return false
  end
  if not currentFallback or not currentFallback.reactor then
    return true
  end

  local currentFits = reactorFitsViewport(currentFallback.reactor, viewportW, viewportH)
  local candidateFits = reactorFitsViewport(candidateFallback.reactor, viewportW, viewportH)
  if currentFits ~= candidateFits then
    return candidateFits
  end

  local preferredIndex = ASSET_TIER_INDEX[preferredTier] or ASSET_TIER_INDEX.small2
  local currentIndex = ASSET_TIER_INDEX[currentFallback.reactorTier] or preferredIndex
  local candidateIndex = ASSET_TIER_INDEX[candidateFallback.reactorTier] or preferredIndex

  local currentDelta = math.abs(currentIndex - preferredIndex)
  local candidateDelta = math.abs(candidateIndex - preferredIndex)
  if candidateDelta ~= currentDelta then
    return candidateDelta < currentDelta
  end

  local currentArea = (currentFallback.reactor.width or 0) * (currentFallback.reactor.height or 0)
  local candidateArea = (candidateFallback.reactor.width or 0) * (candidateFallback.reactor.height or 0)
  return candidateArea > currentArea
end

local function classifyAssetError(err)
  local low = string.lower(compactError(err))
  if string.find(low, "fichier absent", 1, true) or string.find(low, "not found", 1, true) then
    return "file_missing"
  end
  if isVramError(low) then
    return "vram_alloc_failed"
  end
  if string.find(low, "decode", 1, true) or string.find(low, "invalid", 1, true) then
    return "decode_failed"
  end
  return "decode_failed"
end

local function logAssetLoadFailure(kindLabel, variant, err)
  local classified = classifyAssetError(err)
  appendUiRuntimeLog(
    "asset " .. tostring(kindLabel)
      .. ": load failed variant=" .. tostring(variant.name)
      .. " tier=" .. tostring(variant.tier)
      .. " class=" .. tostring(classified)
      .. " detail=" .. compactError(err)
  )

  if classified == "vram_alloc_failed" then
    appendUiRuntimeLog("asset " .. tostring(kindLabel) .. ": variant_too_large probable for " .. tostring(variant.name))
  end

  return classified
end

local function tryDecodeVariant(kindLabel, variant)
  local img, err = loadPng(variant.path)
  if img then
    return {
      name = variant.name,
      path = variant.path,
      tier = variant.tier,
      image = img,
      width = img.getWidth(),
      height = img.getHeight(),
    }, nil
  end

  return nil, logAssetLoadFailure(kindLabel, variant, err)
end

local function loadScenePair(preferredTier, viewportW, viewportH)
  local reactorVariants = normalizeAssetVariants(ASSET_REACTOR_VARIANTS, "reactor")
  local moduleVariants = normalizeAssetVariants(ASSET_LASER_MODULE_VARIANTS, "laser_module")
  local reactorByTier = buildTierVariantMap(reactorVariants, "reactor")
  local moduleByTier = buildTierVariantMap(moduleVariants, "laser_module")

  local hasReactorTier = false
  local hasModuleTier = false
  for _, tier in ipairs(ASSET_TIER_ORDER) do
    if reactorByTier[tier] and #reactorByTier[tier] > 0 then
      hasReactorTier = true
    end
    if moduleByTier[tier] and #moduleByTier[tier] > 0 then
      hasModuleTier = true
    end
  end

  if not hasReactorTier then
    appendUiRuntimeLog("asset scene: no reactor tier available")
    appendUiRuntimeLog("asset scene final: reactorLoaded=no laserLoaded=no reactorTier=none laserTier=none mode=none reason=no_reactor_tier_available")
    return nil, "no_reactor_tier_available"
  end

  local pairCandidates = buildTierPairCandidates(preferredTier, reactorByTier, moduleByTier)
  appendUiRuntimeLog(
    "asset scene: requestedReactorTier=" .. tostring(preferredTier)
      .. " hasModuleTier=" .. tostring(hasModuleTier)
      .. " viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
      .. " pairCandidates=" .. tostring(#pairCandidates)
  )

  if #pairCandidates > 0 then
    for index, candidate in ipairs(pairCandidates) do
      appendUiRuntimeLog(
        "asset pair candidate #" .. tostring(index)
          .. ": reactorTier=" .. tostring(candidate.reactorTier)
          .. " (" .. tostring(candidate.reactorReason) .. ")"
          .. " moduleTierReq=" .. tostring(candidate.requestedModuleTier)
          .. " moduleTier=" .. tostring(candidate.moduleTier)
          .. " (" .. tostring(candidate.moduleReason) .. ")"
      )
    end
  elseif not hasModuleTier then
    appendUiRuntimeLog("asset scene: no module tier available, reactor-only fallback mode enabled")
  end

  local reactorTierCandidates = buildReactorTierCandidates(preferredTier, reactorByTier)
  local sawVramError = false
  local reactorFallback = nil

  for _, reactorCandidate in ipairs(reactorTierCandidates) do
    local reactorTier = reactorCandidate.tier
    local reactorList = reactorByTier[reactorTier] or {}
    local moduleCandidates = buildModuleTierCandidates(reactorTier, moduleByTier)
    appendUiRuntimeLog(
      "asset scene: try reactorTier=" .. tostring(reactorTier)
        .. " (" .. tostring(reactorCandidate.reason) .. ")"
        .. " reactorVariants=" .. tostring(#reactorList)
        .. " moduleCandidates=" .. tostring(#moduleCandidates)
    )

    for _, reactorVariant in ipairs(reactorList) do
      local reactorSelected, reactorErrClass = tryDecodeVariant("reactor", reactorVariant)
      if reactorSelected then
        local fallbackCandidate = {
          reactor = reactorSelected,
          reactorTier = reactorTier,
          requestedTier = preferredTier,
        }
        if shouldReplaceReactorFallback(reactorFallback, fallbackCandidate, preferredTier, viewportW, viewportH) then
          reactorFallback = fallbackCandidate
        end

        for _, moduleCandidate in ipairs(moduleCandidates) do
          local moduleTier = moduleCandidate.tier
          local moduleList = moduleByTier[moduleTier] or {}

          if not isTierPairCompatible(reactorTier, moduleTier) then
            appendUiRuntimeLog(
              "asset pair rejected: class=incompatible_pair"
                .. " reactorTierReq=" .. tostring(preferredTier)
                .. " reactorTier=" .. tostring(reactorTier)
                .. " moduleTierReq=" .. tostring(reactorTier)
                .. " moduleTier=" .. tostring(moduleTier)
                .. " reactorVariant=" .. tostring(reactorVariant.name)
            )
          else
            for _, moduleVariant in ipairs(moduleList) do
              appendUiRuntimeLog(
                "asset pair try: reactorTierReq=" .. tostring(preferredTier)
                  .. " reactorTier=" .. tostring(reactorTier)
                  .. " moduleTierReq=" .. tostring(reactorTier)
                  .. " moduleTier=" .. tostring(moduleTier)
                  .. " moduleReason=" .. tostring(moduleCandidate.reason)
                  .. " reactorVariant=" .. tostring(reactorVariant.name)
                  .. " moduleVariant=" .. tostring(moduleVariant.name)
              )

              local moduleSelected, moduleErrClass = tryDecodeVariant("laser_module", moduleVariant)
              local pairFailureClass = moduleErrClass
              if moduleSelected then
                local pairFits, pairRequiredW, pairRequiredH, pairAvailableW, pairAvailableH =
                  pairFitsViewport(reactorSelected, moduleSelected, viewportW, viewportH)
                if not pairFits then
                  appendUiRuntimeLog(
                    "asset pair rejected: class=viewport_overflow"
                      .. " reactorVariant=" .. tostring(reactorVariant.name)
                      .. " moduleVariant=" .. tostring(moduleVariant.name)
                      .. " viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
                      .. " available=" .. tostring(pairAvailableW or "n/a") .. "x" .. tostring(pairAvailableH or "n/a")
                      .. " required=" .. tostring(pairRequiredW) .. "x" .. tostring(pairRequiredH)
                  )
                  pairFailureClass = "viewport_overflow"
                  moduleSelected = nil
                  pcall(collectgarbage, "collect")
                else
                  local usedFallback = (reactorTier ~= preferredTier) or (moduleTier ~= reactorTier)
                  if moduleTier ~= reactorTier then
                    appendUiRuntimeLog(
                      "asset pair selected: module fallback chosen"
                        .. " requested=" .. tostring(reactorTier)
                        .. " selected=" .. tostring(moduleTier)
                    )
                  end

                  appendUiRuntimeLog(
                    "asset pair selected: reactor=" .. tostring(reactorVariant.name)
                      .. " module=" .. tostring(moduleVariant.name)
                      .. " usedFallback=" .. tostring(usedFallback)
                  )
                  appendUiRuntimeLog(
                    "asset scene final: reactorLoaded=yes laserLoaded=yes"
                      .. " reactorTier=" .. tostring(reactorTier)
                      .. " laserTier=" .. tostring(moduleTier)
                      .. " viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
                      .. " mode=pair reason=pair_selected"
                  )

                  return {
                    reactor = reactorSelected,
                    module = moduleSelected,
                    reactorTier = reactorTier,
                    moduleTier = moduleTier,
                    requestedTier = preferredTier,
                    usedFallback = usedFallback,
                    sawVramError = sawVramError,
                    reactorOnly = false,
                  }, nil
                end
              end

              if pairFailureClass == "vram_alloc_failed" then
                sawVramError = true
              end

              if pairFailureClass then
                appendUiRuntimeLog(
                  "asset pair failed: class=" .. tostring(pairFailureClass)
                    .. " reactorVariant=" .. tostring(reactorVariant.name)
                    .. " moduleVariant=" .. tostring(moduleVariant.name)
                    .. " reactorTier=" .. tostring(reactorTier)
                    .. " moduleTier=" .. tostring(moduleTier)
                )
              end
            end
          end
        end

        if reactorFallback and reactorFallback.reactor ~= reactorSelected then
          reactorSelected = nil
        end
        pcall(collectgarbage, "collect")
      elseif reactorErrClass == "vram_alloc_failed" then
        sawVramError = true
      end
    end
  end

  if reactorFallback and reactorFallback.reactor then
    local reactorFits, reactorRequiredW, reactorRequiredH, reactorAvailableW, reactorAvailableH =
      pairFitsViewport(reactorFallback.reactor, nil, viewportW, viewportH)
    if not reactorFits then
      appendUiRuntimeLog(
        "asset scene: reactor fallback rejected"
          .. " class=viewport_overflow"
          .. " viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
          .. " available=" .. tostring(reactorAvailableW or "n/a") .. "x" .. tostring(reactorAvailableH or "n/a")
          .. " required=" .. tostring(reactorRequiredW) .. "x" .. tostring(reactorRequiredH)
      )
      appendUiRuntimeLog(
        "asset scene final: reactorLoaded=no laserLoaded=no reactorTier=none laserTier=none"
          .. " viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
          .. " mode=none reason=reactor_overflow"
      )
      return nil, "reactor_overflow"
    end

    appendUiRuntimeLog(
      "asset scene: no full pair loaded, using reactor-only fallback"
        .. " reactorTier=" .. tostring(reactorFallback.reactorTier)
        .. " requestedTier=" .. tostring(preferredTier)
        .. " class=no_pair_loaded"
    )
    appendUiRuntimeLog(
      "asset scene final: reactorLoaded=yes laserLoaded=no"
        .. " reactorTier=" .. tostring(reactorFallback.reactorTier)
        .. " laserTier=none"
        .. " viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
        .. " mode=reactor-only reason=no_pair_loaded"
    )
    return {
      reactor = reactorFallback.reactor,
      module = nil,
      reactorTier = reactorFallback.reactorTier,
      moduleTier = "none",
      requestedTier = preferredTier,
      usedFallback = true,
      sawVramError = sawVramError,
      reactorOnly = true,
    }, "no_pair_loaded"
  end

  appendUiRuntimeLog("asset scene: no_pair_loaded (no reactor usable)")
  appendUiRuntimeLog(
    "asset scene final: reactorLoaded=no laserLoaded=no reactorTier=none laserTier=none"
      .. " viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
      .. " mode=none reason=" .. tostring(sawVramError and "no_scene_pair_vram" or "no_pair_loaded")
  )
  return nil, sawVramError and "no_scene_pair_vram" or "no_pair_loaded"
end

local function refreshVisualEffectLevel()
  syncUi()
  local level = "normal"
  if ui and ui.micro then
    level = "minimal"
  elseif state.visual.vramFallback or not images.reactor or not images.laserModule then
    level = "lite"
  elseif ui and ui.compact then
    level = "lite"
  end
  state.visual.effectLevel = level
  appendUiRuntimeLog("effects level: " .. tostring(level))
end

local function tryLoadAssets(reason)
  syncUi()
  reason = tostring(reason or "manual")
  local screenW = ui and ui.sw or 0
  local screenH = ui and ui.sh or 0
  local screen = tostring(ui and (ui.sw .. "x" .. ui.sh) or "n/a")
  local hadPreviousReactor = (#images.reactorVariants > 0) or (images.reactor ~= nil)
  local hadPreviousModule = (#images.laserModuleVariants > 0) or (images.laserModule ~= nil)
  local hadPreviousVisual = hadPreviousReactor
  local previousReactor = hadPreviousReactor and tostring(state.visual.reactorAsset or "runtime") or "none"
  local previousModule = hadPreviousModule and tostring(state.visual.moduleAsset or "runtime") or "none"
  local requestedTier = preferredSceneTier()
  local viewportW, viewportH = estimateOverviewSceneViewport()
  local rejectReason = screenSizeRejectReason(screenW, screenH)
    or assetReloadScreenRejectReason(screenW, screenH)
    or viewportRejectReason(viewportW, viewportH)

  if rejectReason then
    local rejectKey = table.concat({
      tostring(screenW),
      tostring(screenH),
      tostring(viewportW or "n/a"),
      tostring(viewportH or "n/a"),
      tostring(rejectReason),
      tostring(hadPreviousVisual and "preserve" or "none"),
    }, "|")
    local shouldLogReject = rejectKey ~= displayState.lastInvalidViewportKey
    if shouldLogReject then
      appendUiRuntimeLog(
        "screen invalid: width=" .. tostring(screenW)
          .. " height=" .. tostring(screenH)
          .. " reason=" .. tostring(rejectReason)
      )
      appendUiRuntimeLog(
        "asset reload skipped: invalid screen size"
          .. " reason=" .. tostring(rejectReason)
          .. " screen=" .. tostring(screenW) .. "x" .. tostring(screenH)
          .. " viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
          .. " preservePrevious=" .. tostring(hadPreviousVisual and "yes" or "no")
      )
      displayState.lastInvalidViewportKey = rejectKey
    end

    if hadPreviousVisual then
      state.visual.sceneMode = hadPreviousModule and "pair" or "reactor-only"
      state.visual.lastAssetReason = reason .. ":skip_invalid_viewport"
      state.visual.vramFallback = state.visual.vramFallback or false
      if shouldLogReject then
        appendUiRuntimeLog(
          "asset scene preserved: previous "
            .. tostring(state.visual.sceneMode or "reactor-only")
            .. " kept"
        )
      end
    else
      state.visual.lastAssetReason = reason .. ":skip_invalid_viewport_no_scene"
      if shouldLogReject then
        appendUiRuntimeLog("asset scene preserved: none available, reload refused")
      end
    end
    refreshVisualEffectLevel()
    return false, rejectReason
  end

  displayState.lastInvalidViewportKey = nil

  appendUiRuntimeLog(
    "asset reload start: reason=" .. reason
      .. ", screen=" .. screen
      .. ", requestedTier=" .. tostring(requestedTier)
      .. ", viewport=" .. tostring(viewportW or "n/a") .. "x" .. tostring(viewportH or "n/a")
      .. ", previousPair=" .. tostring(previousReactor) .. "/" .. tostring(previousModule)
  )

  local scene, loadErr = loadScenePair(requestedTier, viewportW, viewportH)
  if scene and scene.reactor then
    -- Atomic swap: keep active assets untouched until a complete scene decision is ready.
    images.reactorVariants = { scene.reactor }
    images.reactor = scene.reactor.image
    local appliedSceneMode = "reactor-only"

    if scene.module then
      images.laserModuleVariants = { scene.module }
      images.laserModule = scene.module.image
      appliedSceneMode = "pair"
    else
      images.laserModuleVariants = {}
      images.laserModule = nil
      appliedSceneMode = "reactor-only"
    end

    state.visual.reactorAsset = scene.reactor.name
    state.visual.moduleAsset = scene.module and scene.module.name or "none"
    state.visual.sceneMode = appliedSceneMode
    state.visual.vramFallback = scene.sawVramError or scene.usedFallback or scene.reactorOnly or false
    state.visual.lastAssetReason = reason

    appendUiRuntimeLog(
      "asset reload applied: reactor=" .. tostring(scene.reactor.name)
        .. " module=" .. tostring(scene.module and scene.module.name or "none")
        .. " reactorTier=" .. tostring(scene.reactorTier)
        .. " moduleTier=" .. tostring(scene.moduleTier)
        .. " reactorOnly=" .. tostring(scene.reactorOnly)
        .. " fallback=" .. tostring(scene.usedFallback)
    )
    appendUiRuntimeLog(
      "asset active scene: mode=" .. tostring(appliedSceneMode)
        .. " reactorPresent=yes laserPresent=" .. tostring(scene.module and "yes" or "no")
        .. " reactorAsset=" .. tostring(state.visual.reactorAsset)
        .. " laserAsset=" .. tostring(state.visual.moduleAsset)
    )
  else
    if hadPreviousVisual then
      local preservedMode = hadPreviousModule and "pair" or "reactor-only"
      appendUiRuntimeLog(
        "asset reload failed, preserving previous visual state: "
          .. tostring(previousReactor) .. "/" .. tostring(previousModule)
          .. " reason=" .. tostring(loadErr)
      )
      state.visual.sceneMode = preservedMode
      state.visual.vramFallback = true
      state.visual.lastAssetReason = reason .. ":preserve_previous"
      appendUiRuntimeLog(
        "asset active scene: mode=" .. tostring(preservedMode)
          .. " reactorPresent=yes laserPresent=" .. tostring(hadPreviousModule and "yes" or "no")
          .. " reactorAsset=" .. tostring(state.visual.reactorAsset)
          .. " laserAsset=" .. tostring(state.visual.moduleAsset)
          .. " reason=preserve_previous"
      )
    else
      appendUiRuntimeLog("asset reload failed: no previous valid pair available, placeholder may be shown (reason=" .. tostring(loadErr) .. ")")
      images.reactorVariants = {}
      images.reactor = nil
      images.laserModuleVariants = {}
      images.laserModule = nil
      state.visual.reactorAsset = "none"
      state.visual.moduleAsset = "none"
      state.visual.sceneMode = "none"
      state.visual.vramFallback = true
      state.visual.lastAssetReason = reason .. ":no_pair"
      appendUiRuntimeLog("asset active scene: mode=none reactorPresent=no laserPresent=no reason=" .. tostring(loadErr or "no_pair"))
    end
  end

  refreshVisualEffectLevel()
  pcall(collectgarbage, "collect")
  return scene ~= nil, loadErr
end

local function getFallbackReactorVariant()
  if #images.reactorVariants > 0 then
    return images.reactorVariants[1]
  end

  if images.reactor then
    return {
      name = "runtime",
      image = images.reactor,
      width = images.reactor.getWidth(),
      height = images.reactor.getHeight(),
    }
  end

  return nil
end

local function getFallbackLaserModuleVariant()
  if #images.laserModuleVariants > 0 then
    return images.laserModuleVariants[1]
  end

  if images.laserModule then
    return {
      name = "runtime",
      image = images.laserModule,
      width = images.laserModule.getWidth(),
      height = images.laserModule.getHeight(),
    }
  end

  return nil
end

local lastLayoutFallbackLogKey = nil
local lastLayoutFallbackRejectLogKey = nil
local lastLayoutVisualRejectLogKey = nil
local lastLayoutHardRejectLogKey = nil
local lastOverviewPairReductionLogKey = nil
local lastOverviewPairAcceptedLogKey = nil

function resolveOverviewVisualBounds(slotW, slotH, spacing)
  local sidePad = math.max(0, math.floor(spacing.sidePad or 0))
  local topPad = math.max(0, math.floor(spacing.topPad or 0))
  local bottomPad = math.max(0, math.floor(spacing.bottomPad or 0))
  local availableW = math.max(1, slotW - sidePad * 2)
  local availableH = math.max(1, slotH - topPad - bottomPad)

  return {
    availableW = availableW,
    availableH = availableH,
    sidePad = sidePad,
    topPad = topPad,
    bottomPad = bottomPad,
    maxWFill = tonumber(spacing.maxWFill) or 1.0,
    maxHFill = tonumber(spacing.maxHFill) or 1.0,
  }
end

local function shouldReplaceLayoutCandidate(current, candidate)
  if not candidate then
    return false
  end
  if not current then
    return true
  end
  if (candidate.rank or 0) ~= (current.rank or 0) then
    return (candidate.rank or 0) > (current.rank or 0)
  end
  if (candidate.score or 0) ~= (current.score or 0) then
    return (candidate.score or 0) > (current.score or 0)
  end
  if (candidate.requiredH or 0) ~= (current.requiredH or 0) then
    return (candidate.requiredH or 0) < (current.requiredH or 0)
  end
  return (candidate.requiredW or 0) < (current.requiredW or 0)
end

local function chooseStackLayout(slotW, slotH, moduleCount, options)
  syncUi()
  options = type(options) == "table" and options or {}
  local spacing = resolveOverviewStackSpacing(options)
  local visual = resolveOverviewVisualBounds(slotW, slotH, spacing)
  local gap = spacing.reactorGap
  local moduleGap = spacing.moduleGap
  local bestPairCapped = nil
  local bestPairFit = nil
  local bestReactorCapped = nil
  local bestReactorFit = nil
  local visualReject = nil
  local hardReject = nil

  local reactors = #images.reactorVariants > 0 and images.reactorVariants or {}
  local modules = #images.laserModuleVariants > 0 and images.laserModuleVariants or {}

  if #reactors == 0 then
    local fallbackReactor = getFallbackReactorVariant()
    if not fallbackReactor then
      return nil
    end
    reactors = { fallbackReactor }
  end

  if #modules == 0 then
    local fallbackModule = getFallbackLaserModuleVariant()
    if fallbackModule then
      modules = { fallbackModule }
    end
  end

  local function isPairCandidate(candidate)
    return candidate and candidate.module ~= nil and (tonumber(candidate.moduleCount) or 0) > 0
  end

  local function annotateSelection(candidate, selectionClass, selectionReason)
    if candidate then
      candidate.selectionClass = selectionClass
      candidate.selectionReason = selectionReason
    end
    return candidate
  end

  local function mergeBestCandidate(current, candidate)
    if shouldReplaceLayoutCandidate(current, candidate) then
      return candidate
    end
    return current
  end

  local function registerCandidate(candidate)
    local fitsAvailable = candidate.requiredW <= visual.availableW and candidate.requiredH <= visual.availableH
    if not fitsAvailable then
      if (not hardReject) or (candidate.requiredW * candidate.requiredH > hardReject.requiredW * hardReject.requiredH) then
        hardReject = candidate
      end
      return
    end

    local withinCap = candidate.fillW <= visual.maxWFill and candidate.fillH <= visual.maxHFill
    if withinCap then
      if isPairCandidate(candidate) then
        bestPairCapped = mergeBestCandidate(bestPairCapped, candidate)
      else
        bestReactorCapped = mergeBestCandidate(bestReactorCapped, candidate)
      end
      return
    end

    if isPairCandidate(candidate) then
      bestPairFit = mergeBestCandidate(bestPairFit, candidate)
    else
      bestReactorFit = mergeBestCandidate(bestReactorFit, candidate)
    end
    if (not visualReject) or (candidate.fillW + candidate.fillH > visualReject.fillW + visualReject.fillH) then
      visualReject = candidate
    end
  end

  for _, reactorVariant in ipairs(reactors) do
    local reactorRequiredW = reactorVariant.width
    local reactorRequiredH = reactorVariant.height
    registerCandidate({
      reactor = reactorVariant,
      module = nil,
      moduleCount = 0,
      rank = 1,
      score = reactorVariant.width * reactorVariant.height,
      requiredW = reactorRequiredW,
      requiredH = reactorRequiredH,
      fillW = reactorRequiredW / math.max(1, visual.availableW),
      fillH = reactorRequiredH / math.max(1, visual.availableH),
      moduleGap = moduleGap,
      reactorGap = gap,
      stackOffsetY = spacing.stackOffsetY,
      moduleOffsetX = spacing.moduleOffsetX,
      reactorOffsetX = spacing.reactorOffsetX,
      topPad = visual.topPad,
      bottomPad = visual.bottomPad,
      sidePad = visual.sidePad,
      availableW = visual.availableW,
      availableH = visual.availableH,
      spacingScale = spacing.spacingScale,
    })

    if moduleCount > 0 and #modules > 0 then
      for _, moduleVariant in ipairs(modules) do
        local modulesBlockH = (moduleVariant.height * moduleCount) + (moduleGap * math.max(0, moduleCount - 1))
        local requiredH = reactorVariant.height + gap + modulesBlockH
        local requiredW = math.max(reactorVariant.width, moduleVariant.width)
        local score = (reactorVariant.width * reactorVariant.height * 1000) + (moduleVariant.width * moduleVariant.height)
        registerCandidate({
          reactor = reactorVariant,
          module = moduleVariant,
          moduleCount = moduleCount,
          rank = 2,
          score = score,
          requiredW = requiredW,
          requiredH = requiredH,
          modulesBlockH = modulesBlockH,
          fillW = requiredW / math.max(1, visual.availableW),
          fillH = requiredH / math.max(1, visual.availableH),
          moduleGap = moduleGap,
          reactorGap = gap,
          stackOffsetY = spacing.stackOffsetY,
          moduleOffsetX = spacing.moduleOffsetX,
          reactorOffsetX = spacing.reactorOffsetX,
          topPad = visual.topPad,
          bottomPad = visual.bottomPad,
          sidePad = visual.sidePad,
          availableW = visual.availableW,
          availableH = visual.availableH,
          spacingScale = spacing.spacingScale,
        })
      end
    end
  end

  local bestCapped = mergeBestCandidate(bestReactorCapped, bestPairCapped)
  local bestFit = mergeBestCandidate(bestReactorFit, bestPairFit)
  local preferPair = options.preferPair == true
  local responsiveMode = tostring(options.responsiveMode or (ui and (ui.micro and "micro" or (ui.compact and "compact" or "large")) or "large"))

  if preferPair then
    if bestPairCapped then
      return annotateSelection(bestPairCapped, "pair_capped", "pair_available")
    end

    if bestPairFit then
      local visualLogKey = table.concat({
        tostring(slotW),
        tostring(slotH),
        tostring(visual.availableW),
        tostring(visual.availableH),
        tostring(bestPairFit.requiredW),
        tostring(bestPairFit.requiredH),
        tostring(bestPairFit.reactor and bestPairFit.reactor.name or "none"),
        tostring(bestPairFit.module and bestPairFit.module.name or "none"),
        "prefer_pair",
      }, "|")
      if visualLogKey ~= lastLayoutVisualRejectLogKey then
        appendUiRuntimeLog(
          "layout fallback selected: class=visual_margin_cap"
            .. " strategy=prefer_pair"
            .. " mode=" .. tostring(responsiveMode)
            .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
            .. " availableViewport=" .. tostring(visual.availableW) .. "x" .. tostring(visual.availableH)
            .. " required=" .. tostring(bestPairFit.requiredW) .. "x" .. tostring(bestPairFit.requiredH)
            .. " fillW=" .. string.format("%.2f", bestPairFit.fillW or 0)
            .. " fillH=" .. string.format("%.2f", bestPairFit.fillH or 0)
            .. " cap=" .. tostring(visual.maxWFill) .. "," .. tostring(visual.maxHFill)
        )
        lastLayoutVisualRejectLogKey = visualLogKey
      end
      return annotateSelection(bestPairFit, "pair_visual_margin_cap", "pair_preferred_over_cap")
    end

    if bestReactorCapped then
      local fallbackReason = "pair_unavailable"
      if hardReject then
        fallbackReason = "hard_overflow"
      elseif visualReject then
        fallbackReason = responsiveMode == "micro" and "micro_constraint" or "visual_margin_cap"
      elseif responsiveMode == "micro" then
        fallbackReason = "micro_constraint"
      end
      local fallbackLogKey = table.concat({
        tostring(slotW),
        tostring(slotH),
        tostring(bestReactorCapped.reactor and bestReactorCapped.reactor.name or "none"),
        tostring(fallbackReason),
      }, "|")
      if fallbackLogKey ~= lastLayoutFallbackLogKey then
        appendUiRuntimeLog(
          "layout fallback: reactor-only selected"
            .. " mode=" .. tostring(responsiveMode)
            .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
            .. " reason=" .. tostring(fallbackReason)
        )
        lastLayoutFallbackLogKey = fallbackLogKey
      end
      return annotateSelection(bestReactorCapped, "reactor_capped", fallbackReason)
    end

    if bestReactorFit then
      local fitReason = responsiveMode == "micro" and "micro_constraint" or "visual_margin_cap"
      return annotateSelection(bestReactorFit, "reactor_visual_margin_cap", fitReason)
    end
  end

  if bestCapped then
    return annotateSelection(bestCapped, isPairCandidate(bestCapped) and "pair_capped" or "reactor_capped", "default_selection")
  end

  if bestFit then
    local visualLogKey = table.concat({
      tostring(slotW),
      tostring(slotH),
      tostring(visual.availableW),
      tostring(visual.availableH),
      tostring(bestFit.requiredW),
      tostring(bestFit.requiredH),
      tostring(bestFit.reactor and bestFit.reactor.name or "none"),
      tostring(bestFit.module and bestFit.module.name or "none"),
    }, "|")
    if visualLogKey ~= lastLayoutVisualRejectLogKey then
      appendUiRuntimeLog(
        "layout fallback selected: class=visual_margin_cap"
          .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
          .. " availableViewport=" .. tostring(visual.availableW) .. "x" .. tostring(visual.availableH)
          .. " required=" .. tostring(bestFit.requiredW) .. "x" .. tostring(bestFit.requiredH)
          .. " fillW=" .. string.format("%.2f", bestFit.fillW or 0)
          .. " fillH=" .. string.format("%.2f", bestFit.fillH or 0)
          .. " cap=" .. tostring(visual.maxWFill) .. "," .. tostring(visual.maxHFill)
      )
      lastLayoutVisualRejectLogKey = visualLogKey
    end
    return annotateSelection(bestFit, isPairCandidate(bestFit) and "pair_visual_margin_cap" or "reactor_visual_margin_cap", "visual_margin_cap")
  end

  local fallbackReactor = getFallbackReactorVariant()
  local slotFits = fallbackReactor and fallbackReactor.width <= visual.availableW and fallbackReactor.height <= visual.availableH
  if fallbackReactor and slotFits then
    local fallbackLogKey = table.concat({
      tostring(fallbackReactor.name or "runtime"),
      tostring(slotW),
      tostring(slotH),
      tostring(visual.availableW),
      tostring(visual.availableH),
      tostring(fallbackReactor.width),
      tostring(fallbackReactor.height),
      "fit",
    }, "|")
    if fallbackLogKey ~= lastLayoutFallbackLogKey then
      appendUiRuntimeLog(
        "layout fallback: reactor-only selected"
          .. " reactor=" .. tostring(fallbackReactor.name or "runtime")
          .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
          .. " availableViewport=" .. tostring(visual.availableW) .. "x" .. tostring(visual.availableH)
          .. " reactorSize=" .. tostring(fallbackReactor.width) .. "x" .. tostring(fallbackReactor.height)
          .. " reason=visual_margin_cap"
      )
      lastLayoutFallbackLogKey = fallbackLogKey
    end
    return annotateSelection({
      reactor = fallbackReactor,
      module = nil,
      moduleCount = 0,
      score = fallbackReactor.width * fallbackReactor.height,
      requiredW = fallbackReactor.width,
      requiredH = fallbackReactor.height,
      fillW = fallbackReactor.width / math.max(1, visual.availableW),
      fillH = fallbackReactor.height / math.max(1, visual.availableH),
      moduleGap = moduleGap,
      reactorGap = gap,
      stackOffsetY = spacing.stackOffsetY,
      moduleOffsetX = spacing.moduleOffsetX,
      reactorOffsetX = spacing.reactorOffsetX,
      topPad = visual.topPad,
      bottomPad = visual.bottomPad,
      sidePad = visual.sidePad,
      availableW = visual.availableW,
      availableH = visual.availableH,
      spacingScale = spacing.spacingScale,
    }, "reactor_only_fallback", "visual_margin_cap")
  elseif fallbackReactor then
    local rejectLogKey = table.concat({
      tostring(slotW),
      tostring(slotH),
      tostring(visual.availableW),
      tostring(visual.availableH),
      tostring(fallbackReactor.width),
      tostring(fallbackReactor.height),
    }, "|")
    if rejectLogKey ~= lastLayoutFallbackRejectLogKey then
      appendUiRuntimeLog(
        "layout fallback rejected: class=viewport_overflow"
          .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
          .. " availableViewport=" .. tostring(visual.availableW) .. "x" .. tostring(visual.availableH)
          .. " reactorSize=" .. tostring(fallbackReactor.width) .. "x" .. tostring(fallbackReactor.height)
      )
      lastLayoutFallbackRejectLogKey = rejectLogKey
    end
  end

  if hardReject then
    local hardLogKey = table.concat({
      tostring(slotW),
      tostring(slotH),
      tostring(visual.availableW),
      tostring(visual.availableH),
      tostring(hardReject.requiredW or 0),
      tostring(hardReject.requiredH or 0),
      tostring(hardReject.reactor and hardReject.reactor.name or "none"),
      tostring(hardReject.module and hardReject.module.name or "none"),
    }, "|")
    if hardLogKey ~= lastLayoutHardRejectLogKey then
      appendUiRuntimeLog(
        "layout rejected: class=hard_overflow"
          .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
          .. " availableViewport=" .. tostring(visual.availableW) .. "x" .. tostring(visual.availableH)
          .. " required=" .. tostring(hardReject.requiredW or 0) .. "x" .. tostring(hardReject.requiredH or 0)
      )
      lastLayoutHardRejectLogKey = hardLogKey
    end
  elseif visualReject then
    local visualRejectKey = table.concat({
      tostring(slotW),
      tostring(slotH),
      tostring(visual.availableW),
      tostring(visual.availableH),
      tostring(visualReject.requiredW or 0),
      tostring(visualReject.requiredH or 0),
      tostring(visualReject.reactor and visualReject.reactor.name or "none"),
      tostring(visualReject.module and visualReject.module.name or "none"),
    }, "|")
    if visualRejectKey ~= lastLayoutVisualRejectLogKey then
      appendUiRuntimeLog(
        "layout rejected: class=visual_margin_cap"
          .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
          .. " availableViewport=" .. tostring(visual.availableW) .. "x" .. tostring(visual.availableH)
          .. " required=" .. tostring(visualReject.requiredW or 0) .. "x" .. tostring(visualReject.requiredH or 0)
          .. " fillW=" .. string.format("%.2f", visualReject.fillW or 0)
          .. " fillH=" .. string.format("%.2f", visualReject.fillH or 0)
          .. " cap=" .. tostring(visual.maxWFill) .. "," .. tostring(visual.maxHFill)
      )
      lastLayoutVisualRejectLogKey = visualRejectKey
    end
  end

  return nil
end

local function reductionScalesForMode(responsiveMode, slotW, slotH)
  if responsiveMode == "micro" then
    local out = { 1.00, 0.90, 0.82, 0.74 }
    if (tonumber(slotH) or 0) <= 220 then
      out[#out + 1] = 0.66
    end
    return out
  end
  if responsiveMode == "compact" then
    local out = { 1.00, 0.92, 0.84 }
    if (tonumber(slotH) or 0) <= 340 then
      out[#out + 1] = 0.76
    end
    if (tonumber(slotH) or 0) <= 240 then
      out[#out + 1] = 0.68
    end
    return out
  end
  return { 1.00 }
end

local function chooseOverviewStackLayout(slotW, slotH, configuredModuleCount)
  syncUi()
  local maxCount = math.max(1, tonumber(configuredModuleCount) or 1)
  local reactorOnlyFallback = nil
  local responsiveMode = ui and (ui.micro and "micro" or (ui.compact and "compact" or "large")) or "large"
  local reductionScales = reductionScalesForMode(responsiveMode, slotW, slotH)

  for count = maxCount, 1, -1 do
    for _, spacingScale in ipairs(reductionScales) do
      local layout = chooseStackLayout(slotW, slotH, count, {
        preferPair = true,
        responsiveMode = responsiveMode,
        spacingScale = spacingScale,
      })
      if layout and layout.reactor then
        layout.configuredModuleCount = maxCount
        layout.drawnModuleCount = layout.module and count or 0
        layout.spacingScale = spacingScale

        if layout.module then
          if count < maxCount or spacingScale < 0.999 then
            local reductionLogKey = table.concat({
              tostring(slotW),
              tostring(slotH),
              tostring(maxCount),
              tostring(count),
              string.format("%.2f", spacingScale),
              tostring(layout.reactor and layout.reactor.name or "none"),
              tostring(layout.module and layout.module.name or "none"),
            }, "|")
            if reductionLogKey ~= lastOverviewPairReductionLogKey then
              appendUiRuntimeLog(
                "layout pair compact reduction applied"
                  .. " mode=" .. tostring(responsiveMode)
                  .. " configured=" .. tostring(maxCount)
                  .. " drawn=" .. tostring(count)
                  .. " spacingScale=" .. string.format("%.2f", spacingScale)
                  .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
                  .. " reactor=" .. tostring(layout.reactor and layout.reactor.name or "none")
                  .. " module=" .. tostring(layout.module and layout.module.name or "none")
              )
              lastOverviewPairReductionLogKey = reductionLogKey
            end
          else
            local acceptedLogKey = table.concat({
              tostring(slotW),
              tostring(slotH),
              tostring(maxCount),
              tostring(count),
              tostring(layout.reactor and layout.reactor.name or "none"),
              tostring(layout.module and layout.module.name or "none"),
              tostring(responsiveMode),
            }, "|")
            if acceptedLogKey ~= lastOverviewPairAcceptedLogKey then
              appendUiRuntimeLog(
                "layout pair accepted"
                  .. " mode=" .. tostring(responsiveMode)
                  .. " configured=" .. tostring(maxCount)
                  .. " drawn=" .. tostring(count)
                  .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
                  .. " reactor=" .. tostring(layout.reactor and layout.reactor.name or "none")
                  .. " module=" .. tostring(layout.module and layout.module.name or "none")
              )
              lastOverviewPairAcceptedLogKey = acceptedLogKey
            end
          end
          return layout
        end

        if not reactorOnlyFallback then
          layout.fallbackReason = layout.selectionReason
            or (responsiveMode == "micro" and "micro_constraint" or "pair_unavailable")
          reactorOnlyFallback = layout
        end
      end
    end
  end

  if not reactorOnlyFallback then
    local fallbackLayout = chooseStackLayout(slotW, slotH, 0, {
      preferPair = false,
      responsiveMode = responsiveMode,
    })
    if fallbackLayout and fallbackLayout.reactor then
      fallbackLayout.configuredModuleCount = maxCount
      fallbackLayout.drawnModuleCount = 0
      fallbackLayout.fallbackReason = fallbackLayout.selectionReason or "reactor_only_layout"
      reactorOnlyFallback = fallbackLayout
    end
  end

  if reactorOnlyFallback then
    local fallbackKey = table.concat({
      tostring(slotW),
      tostring(slotH),
      tostring(maxCount),
      tostring(reactorOnlyFallback.reactor and reactorOnlyFallback.reactor.name or "none"),
      tostring(reactorOnlyFallback.fallbackReason or "pair_unavailable"),
      tostring(responsiveMode),
    }, "|")
    if fallbackKey ~= lastLayoutFallbackLogKey then
      appendUiRuntimeLog(
        "layout fallback reactor-only reason=" .. tostring(reactorOnlyFallback.fallbackReason or "pair_unavailable")
          .. " responsiveMode=" .. tostring(responsiveMode)
          .. " configuredModules=" .. tostring(maxCount)
          .. " drawnModules=0"
          .. " slot=" .. tostring(slotW) .. "x" .. tostring(slotH)
          .. " spacingScale=" .. string.format("%.2f", tonumber(reactorOnlyFallback.spacingScale) or 1.00)
      )
      lastLayoutFallbackLogKey = fallbackKey
    end
    return reactorOnlyFallback
  end

  return nil
end



  return {
    screenSizeRejectReason = screenSizeRejectReason,
    tryLoadAssets = tryLoadAssets,
    refreshVisualEffectLevel = refreshVisualEffectLevel,
    getFallbackReactorVariant = getFallbackReactorVariant,
    getFallbackLaserModuleVariant = getFallbackLaserModuleVariant,
    chooseStackLayout = chooseStackLayout,
    chooseOverviewStackLayout = chooseOverviewStackLayout,
  }
end

return M
