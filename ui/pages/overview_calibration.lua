local M = {}

-- Central source of OVERVIEW geometry calibration shared by runtime layout
-- selection and renderer placement to avoid drift between modules.

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for key, item in pairs(value) do
    out[key] = deepCopy(item)
  end
  return out
end

local STACK_PROFILES = {
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
  ultra_compact_5x4_ou_6x4 = {
    moduleGapMul = 0.26,
    reactorGapMul = 0.95,
    stackOffsetY = 0,
    moduleOffsetX = 0,
    reactorOffsetX = 0,
    topPad = 1,
    bottomPad = 1,
    sidePad = 0,
    maxWFill = 0.98,
    maxHFill = 0.97,
  },
  ultra_compact_4x4 = {
    moduleGapMul = 0.16,
    reactorGapMul = 0.70,
    stackOffsetY = 0,
    moduleOffsetX = 0,
    reactorOffsetX = 0,
    topPad = 0,
    bottomPad = 0,
    sidePad = 0,
    maxWFill = 1.00,
    maxHFill = 1.00,
  },
}

local ANNOTATION_PROFILES = {
  large = {
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
  },
  compact = {
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
  },
  micro = {
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
  },
}

local PORT_CHANNELS = {
  -- Strict left -> right order from field calibration.
  { key = "tritium", ratio = 0.334, color = 0xFF4DE06D },
  { key = "dtFuel", ratio = 0.452, color = 0xFFB26BFF },
  { key = "deuterium", ratio = 0.567, color = 0xFFFF5A5A },
}

function M.resolveMode(ui)
  if type(ui) == "table" then
    local explicitClass = tostring(ui.overviewScreenClass or "")
    if explicitClass == "ultra_compact_5x4_ou_6x4" or explicitClass == "ultra_compact_4x4" then
      return explicitClass
    end
    local responsiveMode = tostring(ui.overviewResponsiveMode or "")
    if responsiveMode == "ultra_compact_5x4_ou_6x4" or responsiveMode == "ultra_compact_4x4" then
      return responsiveMode
    end
    if ui.micro then
      return "micro"
    end
    if ui.compact then
      return "compact"
    end
  elseif ui == "micro"
    or ui == "compact"
    or ui == "large"
    or ui == "ultra_compact_5x4_ou_6x4"
    or ui == "ultra_compact_4x4" then
    return ui
  end
  return "large"
end

function M.resolveStackProfile(ui)
  local mode = M.resolveMode(ui)
  return deepCopy(STACK_PROFILES[mode] or STACK_PROFILES.large), mode
end

function M.resolveAnnotationProfile(ui, slotW, slotH)
  local mode = M.resolveMode(ui)
  if mode == "ultra_compact_5x4_ou_6x4" or mode == "ultra_compact_4x4" then
    return {
      enabled = false,
      mode = mode,
      reason = "ultra_compact_callouts_disabled",
    }
  end

  if slotW < 86 or slotH < 86 then
    return {
      enabled = false,
      mode = mode,
      reason = "viewport_too_small",
    }
  end

  local profile = deepCopy(ANNOTATION_PROFILES[mode] or ANNOTATION_PROFILES.large)
  profile.enabled = true
  profile.mode = mode
  return profile
end

function M.getPortChannels()
  return deepCopy(PORT_CHANNELS)
end

return M
