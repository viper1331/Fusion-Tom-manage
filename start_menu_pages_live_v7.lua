-- fusion_ui_menu_pages.lua
-- Interface Tom's Peripherals adaptative avec menu et pages dediees de gestion

-- === Configuration / defaults ===
local CONFIG_FILE = "fusion_config.lua"

local DEFAULTS = {
  ui = {
    startPage = "OVERVIEW",
  },
  devices = {
    modem = "back",
    gpu = "tm_gpu_3",
    logic = "fusionReactorLogicAdapter_0",
    induction = "inductionPort_1",
    laserAmplifier = "laserAmplifier_1",
    laser = "laser_0",
    fusionController = "mekanismgenerators:fusion_reactor_controller_3",
    readers = {
      deuterium = "block_reader_1",
      tritium = "block_reader_2",
      active = "block_reader_7",
      dtFuel = "block_reader_9",
    },
    relays = {
      laserCharge = "redstone_relay_0",
      deuteriumTank = "redstone_relay_1",
      tritiumTank = "redstone_relay_2",
      aux = "redstone_relay_3",
    },
  },
  control = {
    telemetryPollMs = 500,
    laserPulseSeconds = 0.15,
    relayAnalogStrength = 15,
    laserModuleCount = 8,

    relaySides = {
      laserCharge = "",
      deuteriumTank = "",
      tritiumTank = "",
      aux = "",
    },
  },
  runtime = {
    gpuMode = 64,
    refreshSeconds = 0.12,
  },
  update = {
    channel = "stable",
    owner = "viper1331",
    repo = "Fusion-Tom-manage",
    branch = "main",
    manifestPath = "fusion.manifest.json",
    rawBaseUrl = "",
    requireConfirmApply = true,
    autoCheckOnStartup = false,
  },
}

local function deepCopy(value)
  if type(value) ~= "table" then
    return value
  end

  local out = {}
  for k, v in pairs(value) do
    out[k] = deepCopy(v)
  end
  return out
end

local function nonEmptyString(value)
  if type(value) ~= "string" then
    return nil
  end

  if string.find(value, "%S") then
    return value
  end

  return nil
end

local function resolveConfiguredGpuName(configuredName)
  return nonEmptyString(configuredName) or DEFAULTS.devices.gpu
end

local GPU_MODE = DEFAULTS.runtime.gpuMode
local REFRESH_SECONDS = DEFAULTS.runtime.refreshSeconds

-- === Assets ===
local ASSET_REACTOR_VARIANTS = {
  { name = "trim_micro",  path = "assets/reactor_top_trim_micro.png"  },
  { name = "trim_tiny",   path = "assets/reactor_top_trim_tiny.png"   },
  { name = "trim_xsmall", path = "assets/reactor_top_trim_xsmall.png" },
  { name = "trim_small2", path = "assets/reactor_top_trim_small2.png" },
  { name = "trim_small",  path = "assets/reactor_top_trim_small.png"  },
  { name = "trim_medium", path = "assets/reactor_top_trim_medium.png" },
  { name = "trim_large",  path = "assets/reactor_top_trim_large.png"  },
  { name = "small",       path = "assets/reactor_top_small.png"       },
  { name = "medium",      path = "assets/reactor_top_medium.png"      },
  { name = "large",       path = "assets/reactor_top_large.png"       },
  { name = "base",        path = "assets/reactor_top.png"             },
}

local ASSET_LASER_MODULE_VARIANTS = {
  { name = "micro",   path = "assets/laser_module_micro.png"   },
  { name = "tiny",    path = "assets/laser_module_tiny.png"    },
  { name = "xsmall",  path = "assets/laser_module_xsmall.png"  },
  { name = "small2",  path = "assets/laser_module_small2.png"  },
  { name = "small",   path = "assets/laser_module_small.png"   },
  { name = "medium",  path = "assets/laser_module_medium.png"  },
  { name = "large",   path = "assets/laser_module_large.png"   },
}

-- === Runtime config ===
local DEVICES = deepCopy(DEFAULTS.devices)
local CONTROL = deepCopy(DEFAULTS.control)
local UPDATE_CFG = deepCopy(DEFAULTS.update)
local START_PAGE = DEFAULTS.ui.startPage
local UPDATE_VERSION_FILE = "fusion.version"
local UPDATE_MANIFEST_FILE = "fusion.manifest.json"
local UPDATE_LOG_FILE = "update.log"
local UPDATE_TEMP_DIR = "update_tmp"
local UPDATE_BACKUP_DIR = "backup_last"

local UPDATE_STATUS = {
  IDLE = "IDLE",
  CHECKING = "CHECKING",
  CHECK_FAILED = "CHECK FAILED",
  UPDATE_AVAILABLE = "UPDATE AVAILABLE",
  UP_TO_DATE = "UP TO DATE",
  DOWNLOADING = "DOWNLOADING",
  DOWNLOAD_FAILED = "DOWNLOAD FAILED",
  READY_TO_APPLY = "READY TO APPLY",
  APPLYING = "APPLYING",
  APPLY_FAILED = "APPLY FAILED",
  ROLLBACK_DONE = "ROLLBACK DONE",
  ROLLBACK_FAILED = "ROLLBACK FAILED",
}

local UpdateVersion = assert(dofile("core/update/version.lua"))
local UpdateManifest = assert(dofile("core/update/manifest.lua"))
local UpdateClient = assert(dofile("core/update/client.lua"))
local UpdateApply = assert(dofile("core/update/apply.lua"))

-- === External config loader ===
local function loadExternalConfig()
  if not fs.exists(CONFIG_FILE) then
    return
  end

  local ok, cfg = pcall(dofile, CONFIG_FILE)
  if not ok or type(cfg) ~= "table" then
    return
  end

  if type(cfg.ui) == "table" and type(cfg.ui.startPage) == "string" and cfg.ui.startPage ~= "" then
    START_PAGE = string.upper(cfg.ui.startPage)
  end

  if type(cfg.control) == "table" then
    if type(cfg.control.telemetryPollMs) == "number" then
      CONTROL.telemetryPollMs = cfg.control.telemetryPollMs
    end
    if type(cfg.control.laserPulseSeconds) == "number" then
      CONTROL.laserPulseSeconds = cfg.control.laserPulseSeconds
    end
    if type(cfg.control.relayAnalogStrength) == "number" then
      CONTROL.relayAnalogStrength = cfg.control.relayAnalogStrength
    end
    if type(cfg.control.laserModuleCount) == "number" then
      CONTROL.laserModuleCount = math.max(1, math.floor(cfg.control.laserModuleCount))
    end
    if type(cfg.control.relaySides) == "table" then
      for k, v in pairs(cfg.control.relaySides) do
        CONTROL.relaySides[k] = v
      end
    end
  end

  if type(cfg.update) == "table" then
    if type(cfg.update.channel) == "string" and cfg.update.channel ~= "" then
      UPDATE_CFG.channel = cfg.update.channel
    end
    if type(cfg.update.owner) == "string" and cfg.update.owner ~= "" then
      UPDATE_CFG.owner = cfg.update.owner
    end
    if type(cfg.update.repo) == "string" and cfg.update.repo ~= "" then
      UPDATE_CFG.repo = cfg.update.repo
    end
    if type(cfg.update.branch) == "string" and cfg.update.branch ~= "" then
      UPDATE_CFG.branch = cfg.update.branch
    end
    if type(cfg.update.manifestPath) == "string" and cfg.update.manifestPath ~= "" then
      UPDATE_CFG.manifestPath = cfg.update.manifestPath
    end
    if type(cfg.update.rawBaseUrl) == "string" then
      UPDATE_CFG.rawBaseUrl = cfg.update.rawBaseUrl
    end
    if type(cfg.update.requireConfirmApply) == "boolean" then
      UPDATE_CFG.requireConfirmApply = cfg.update.requireConfirmApply
    end
    if type(cfg.update.autoCheckOnStartup) == "boolean" then
      UPDATE_CFG.autoCheckOnStartup = cfg.update.autoCheckOnStartup
    end
  end

  if type(cfg.devices) == "table" then
    for k, v in pairs(cfg.devices) do
      if k == "gpu" and DEVICES.gpu ~= nil then
        local gpuName = nonEmptyString(v)
        if gpuName then
          DEVICES.gpu = gpuName
        end
      elseif type(v) == "string" and DEVICES[k] ~= nil then
        DEVICES[k] = v
      end
    end
    if type(cfg.devices.readers) == "table" then
      for k, v in pairs(cfg.devices.readers) do
        if type(v) == "string" and DEVICES.readers[k] ~= nil then
          DEVICES.readers[k] = v
        end
      end
    end
    if type(cfg.devices.relays) == "table" then
      for k, v in pairs(cfg.devices.relays) do
        if type(v) == "string" and DEVICES.relays[k] ~= nil then
          DEVICES.relays[k] = v
        end
      end
    end
  end
end

loadExternalConfig()

local function initGpuFromConfig()
  local configuredGpuName = resolveConfiguredGpuName(DEVICES.gpu)
  local wrapped = peripheral.wrap(configuredGpuName)
  if wrapped then
    return wrapped, configuredGpuName
  end

  local fallbackGpuName = DEFAULTS.devices.gpu
  if configuredGpuName ~= fallbackGpuName then
    wrapped = peripheral.wrap(fallbackGpuName)
    if wrapped then
      return wrapped, fallbackGpuName
    end
  end

  error("GPU introuvable: " .. tostring(configuredGpuName))
end

local gpu, ACTIVE_GPU_NAME = initGpuFromConfig()
DEVICES.gpu = ACTIVE_GPU_NAME

local C = {
  bg        = 0xFF0D0F12,
  panel     = 0xFF171B22,
  panel2    = 0xFF11151B,
  border    = 0xFF2C3440,
  text      = 0xFFE7EDF5,
  muted     = 0xFF9AA8B8,
  green     = 0xFF40D46A,
  greenDim  = 0xFF173622,
  red       = 0xFFE05252,
  redDim    = 0xFF381717,
  orange    = 0xFFE3A33D,
  orangeDim = 0xFF3A2A10,
  cyan      = 0xFF52C7FF,
  cyanDim   = 0xFF113140,
  yellow    = 0xFFE4C84A,
  purple    = 0xFFC66BFF,
  purpleDim = 0xFF311842,
  blackA0   = 0x00000000,
  overlay   = 0xAA000000,
  barBg     = 0xFF0B0E12,
  white     = 0xFFFFFFFF,
}

local state = {
  page = START_PAGE,
  auto = true,
  manualFuel = false,
  maintenance = false,
  ignitionProfile = 2,
  message = "none",
  lastAction = "idle",
  animTick = 0,
  restartRequested = false,
  restartTarget = nil,

  update = {
    localVersion = "n/a",
    remoteVersion = "n/a",
    channel = UPDATE_CFG.channel,
    remoteStatus = UPDATE_STATUS.IDLE,
    statusDetail = "waiting for check",
    statusAt = "never",
    filesToUpdate = 0,
    downloadedFiles = 0,
    lastCheck = "never",
    lastApply = "never",
    lastDownload = "never",
    lastError = "none",
    lastCheckSummary = "not checked",
    logs = {},
    remoteManifest = nil,
    remoteSource = nil,
    localManifest = nil,
    pendingFiles = {},
    downloaded = false,
    applyConfirmArmed = false,
    canRollback = false,
  },

  live = {
    cache = nil,
    lastPoll = 0,
    pendingTimers = {},
    relayStates = {
      deuteriumTank = false,
      tritiumTank = false,
      laserCharge = false,
      aux = false,
    },
  },
}

local images = {
  reactor = nil,
  reactorVariants = {},
  laserModule = nil,
  laserModuleVariants = {},
}

local buttons = {}
local ui = nil

local PAGES = {
  { id = "OVERVIEW", label = "OVERVIEW" },
  { id = "CONTROL",  label = "CONTROL"  },
  { id = "FUEL",     label = "FUEL"     },
  { id = "SYSTEM",   label = "SYSTEM"   },
  { id = "MAJ",      label = "MAJ"      },
}

local function pageExists(pageId)
  for _, page in ipairs(PAGES) do
    if page.id == pageId then
      return true
    end
  end
  return false
end

if not pageExists(state.page) then
  state.page = "OVERVIEW"
end

local function clamp(v, a, b)
  if v < a then return a end
  if v > b then return b end
  return v
end

local function round(v, n)
  local m = 10 ^ (n or 0)
  return math.floor(v * m + 0.5) / m
end

local function hit(r, x, y)
  return x >= r.x and y >= r.y and x < (r.x + r.w) and y < (r.y + r.h)
end

local function sv(v)
  return math.max(1, math.floor(v * ui.scale + 0.5))
end

local function textPixelHeight(size)
  return 8 * (size or 1)
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

  local ok, img = pcall(function()
    return gpu.decodeImage(table.unpack(bytes))
  end)

  if not ok then
    return nil, img
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

local function tryLoadAssets()
  images.reactorVariants = {}
  images.reactor = nil
  images.laserModuleVariants = {}
  images.laserModule = nil

  for index, variant in ipairs(ASSET_REACTOR_VARIANTS) do
    local name, path

    if type(variant) == "table" then
      name = variant.name or ("variant_" .. tostring(index))
      path = variant.path
    elseif type(variant) == "string" then
      name = "variant_" .. tostring(index)
      path = variant
    end

    if type(path) == "string" and path ~= "" then
      local img, err = loadPng(path)
      if img then
        table.insert(images.reactorVariants, {
          name = name,
          path = path,
          image = img,
          width = img.getWidth(),
          height = img.getHeight(),
        })
      elseif name == "base" then
        print("Asset reactor indisponible: " .. tostring(err))
      end
    end
  end

  if #images.reactorVariants > 0 then
    sortReactorVariants()
    images.reactor = images.reactorVariants[#images.reactorVariants].image
  end

  for index, variant in ipairs(ASSET_LASER_MODULE_VARIANTS) do
    local name, path

    if type(variant) == "table" then
      name = variant.name or ("laser_variant_" .. tostring(index))
      path = variant.path
    elseif type(variant) == "string" then
      name = "laser_variant_" .. tostring(index)
      path = variant
    end

    if type(path) == "string" and path ~= "" then
      local img, err = loadPng(path)
      if img then
        table.insert(images.laserModuleVariants, {
          name = name,
          path = path,
          image = img,
          width = img.getWidth(),
          height = img.getHeight(),
        })
      else
        print("Asset module laser indisponible: " .. tostring(err))
      end
    end
  end

  if #images.laserModuleVariants > 0 then
    sortLaserModuleVariants()
    images.laserModule = images.laserModuleVariants[#images.laserModuleVariants].image
  end
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

local function chooseStackLayout(slotW, slotH, moduleCount)
  local gap = ui and ui.smallPad or 0
  local moduleGap = math.max(1, math.floor(gap * 0.45))
  local best = nil

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

  for _, reactorVariant in ipairs(reactors) do
    local reactorRequiredW = reactorVariant.width
    local reactorRequiredH = reactorVariant.height

    if reactorRequiredW <= slotW and reactorRequiredH <= slotH and not best then
      best = {
        reactor = reactorVariant,
        module = nil,
        moduleCount = 0,
        score = reactorVariant.width * reactorVariant.height,
        requiredW = reactorRequiredW,
        requiredH = reactorRequiredH,
        moduleGap = moduleGap,
      }
    end

    if moduleCount > 0 and #modules > 0 then
      for _, moduleVariant in ipairs(modules) do
        local modulesBlockH = (moduleVariant.height * moduleCount) + (moduleGap * math.max(0, moduleCount - 1))
        local requiredH = reactorVariant.height + gap + modulesBlockH
        local requiredW = math.max(reactorVariant.width, moduleVariant.width)

        if requiredW <= slotW and requiredH <= slotH then
          local score = (reactorVariant.width * reactorVariant.height * 1000) + (moduleVariant.width * moduleVariant.height)
          best = {
            reactor = reactorVariant,
            module = moduleVariant,
            moduleCount = moduleCount,
            score = score,
            requiredW = requiredW,
            requiredH = requiredH,
            modulesBlockH = modulesBlockH,
            moduleGap = moduleGap,
          }
        end
      end
    end
  end

  if best then
    return best
  end

  local fallbackReactor = getFallbackReactorVariant()
  if fallbackReactor and fallbackReactor.width <= slotW and fallbackReactor.height <= slotH then
    return {
      reactor = fallbackReactor,
      module = nil,
      moduleCount = 0,
      score = fallbackReactor.width * fallbackReactor.height,
      requiredW = fallbackReactor.width,
      requiredH = fallbackReactor.height,
      moduleGap = moduleGap,
    }
  end

  return nil
end

local function chooseOverviewStackLayout(slotW, slotH, configuredModuleCount)
  local maxCount = math.max(1, tonumber(configuredModuleCount) or 1)

  for count = maxCount, 0, -1 do
    local layout = chooseStackLayout(slotW, slotH, count)
    if layout and layout.reactor then
      layout.configuredModuleCount = maxCount
      layout.drawnModuleCount = count
      return layout
    end
  end

  return nil
end


local function chooseStateColor(data)
  if data.status == "SCRAM" then return C.red end
  if data.status == "WARNING" then return C.orange end
  if data.status == "STABLE" then return C.green end
  return C.muted
end

local function drawText(x, y, text, color, size)
  local s = tostring(text or "")
  size = size or 1

  local sw, sh = gpu.getSize()
  local tw = gpu.getTextLength(s, size, 0)
  local th = textPixelHeight(size)

  if tw <= 0 then return false end
  if y < 0 or (y + th) > sh then return false end

  if x < 0 then x = 0 end
  if (x + tw) > sw then
    x = sw - tw
  end

  if x < 0 then return false end

  gpu.drawText(x, y, s, color or C.text, C.blackA0, size, 0)
  return true
end

local function drawTextRight(xRight, y, text, color, size)
  local s = tostring(text or "")
  size = size or 1
  local tw = gpu.getTextLength(s, size, 0)
  return drawText(xRight - tw, y, s, color, size)
end

local function drawTextCenter(x, y, w, text, color, size)
  if w <= 0 then return false end

  local s = tostring(text or "")
  size = size or 1
  local tw = gpu.getTextLength(s, size, 0)
  local tx = x + math.floor((w - tw) / 2)

  return drawText(tx, y, s, color, size)
end

local function drawPanel(x, y, w, h, title)
  gpu.filledRectangle(x, y, w, h, C.panel)
  gpu.rectangle(x, y, w, h, C.border)

  if title and title ~= "" then
    drawText(x + ui.pad, y + sv(8), title, C.text, ui.titleSize)
    gpu.line(x + ui.pad, y + ui.titleBarY, x + w - ui.pad, y + ui.titleBarY, C.green)
  end
end

local function drawButton(id, x, y, w, h, text, tone, active)
  local bg, fg

  if tone == "green" then
    bg = active and C.green or C.greenDim
    fg = C.white
  elseif tone == "red" then
    bg = active and C.red or C.redDim
    fg = C.white
  elseif tone == "orange" then
    bg = active and C.orange or C.orangeDim
    fg = C.white
  elseif tone == "purple" then
    bg = active and C.purple or C.purpleDim
    fg = C.white
  else
    bg = active and C.cyan or C.cyanDim
    fg = C.white
  end

  gpu.filledRectangle(x, y, w, h, bg)
  gpu.rectangle(x, y, w, h, C.border)

  local ty = y + math.max(0, math.floor((h - textPixelHeight(1)) / 2))
  drawTextCenter(x, ty, w, text, fg, 1)

  if active then
    buttons[id] = { x = x, y = y, w = w, h = h, id = id }
  end
end

local function drawToggleRow(r, y, label, value, valueColor)
  drawText(r.x + ui.pad, y, label, C.text, 1)
  drawTextRight(r.x + r.w - ui.pad, y, value, valueColor or C.muted, 1)
end

local function drawGauge(x, y, w, h, pct, color, label, valueText)
  local labelY = y - ui.labelOffset
  local fillW = math.floor((w - 4) * clamp(pct, 0, 100) / 100)

  drawText(x, labelY, label, C.text, 1)
  drawTextRight(x + w, labelY, valueText, C.text, 1)

  gpu.filledRectangle(x, y, w, h, C.barBg)
  gpu.rectangle(x, y, w, h, C.border)
  gpu.filledRectangle(x + 2, y + 2, fillW, h - 4, color)
end

local function drawImageSafe(img, x, y)
  if not img then return end
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

local function drawReactorCoreAnimationAt(x, y, w, h, data)
  local mode = resolveAnimationMode(data)
  if mode == "offline" then return end

  local frame = state.animTick or 0
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

local function drawHorizontalCableFlow(x1, x2, y, thickness, mode, reverse, styleScale)
  if x2 < x1 then
    x1, x2 = x2, x1
  end

  local frame = state.animTick or 0
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

local function drawVerticalCableFlow(x, y1, y2, thickness, color, glow, speed, reverse, count)
  if y2 < y1 then
    y1, y2 = y2, y1
  end

  local frame = state.animTick or 0
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

local function drawModuleCableFluxAt(x, y, w, h, data)
  local mode = resolveAnimationMode(data)
  if mode == "offline" then return end

  local cableY = y + math.floor(h * 0.50)
  local thickness = math.max(2, math.floor(h * 0.12))

  local leftOuter = x + math.floor(w * 0.095)
  local leftInner = x + math.floor(w * 0.295)
  local rightInner = x + math.floor(w * 0.695)
  local rightOuter = x + math.floor(w * 0.900)

  drawHorizontalCableFlow(leftOuter, leftInner, cableY, thickness, mode, false, thickness)
  drawHorizontalCableFlow(rightInner, rightOuter, cableY, thickness, mode, true, thickness)
end

local function drawReactorRightCableFluxAt(x, y, w, h, data)
  local mode = resolveAnimationMode(data)
  if mode == "offline" then return end

  local cableY = y + math.floor(h * 0.516)
  local thickness = math.max(2, math.floor(h * 0.018))
  local startX = x + math.floor(w * 0.748)
  local endX = x + math.floor(w * 0.915)

  drawHorizontalCableFlow(startX, endX, cableY, thickness, mode, false, thickness)
end

local function drawReactorBottomGasFluxAt(x, y, w, h, data)
  if not data or not data.formed then return end

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
      drawVerticalCableFlow(cx, topY, bottomY, thickness, channel.color, channel.glow, channel.speed, true, channel.count)
    end
  end
end

local function buildUI()
  gpu.refreshSize()
  gpu.setSize(GPU_MODE)

  local sw, sh = gpu.getSize()
  local scale = math.min(sw / 900, sh / 1400)
  scale = clamp(scale, 0.40, 2.20)

  local micro = sw <= 160 or sh <= 340
  local compact = micro or sw < 760 or (sw / sh) < 0.72

  ui = {
    sw = sw,
    sh = sh,
    scale = scale,
    compact = compact,
    micro = micro,

    margin = micro and math.max(2, math.floor(4 * scale + 0.5)) or math.max(8, math.floor(16 * scale + 0.5)),
    gap = micro and math.max(2, math.floor(4 * scale + 0.5)) or math.max(6, math.floor(12 * scale + 0.5)),
    pad = micro and math.max(3, math.floor(5 * scale + 0.5)) or math.max(8, math.floor(12 * scale + 0.5)),
    smallPad = micro and math.max(1, math.floor(3 * scale + 0.5)) or math.max(6, math.floor(8 * scale + 0.5)),

    headerH = micro and math.max(24, math.floor(28 * scale + 0.5)) or math.max(56, math.floor(72 * scale + 0.5)),
    navH = micro and 0 or math.max(30, math.floor(38 * scale + 0.5)),
    footerH = micro and 0 or math.max(52, math.floor(58 * scale + 0.5)),
    buttonH = micro and math.max(16, math.floor(20 * scale + 0.5)) or math.max(28, math.floor(34 * scale + 0.5)),
    gaugeH = micro and math.max(8, math.floor(10 * scale + 0.5)) or math.max(14, math.floor(18 * scale + 0.5)),

    titleSize = micro and 1 or (scale >= 1.35 and 2 or 1),
    headerTitleSize = micro and 1 or (scale >= 1.20 and 2 or 1),

    titleBarY = micro and math.max(10, math.floor(12 * scale + 0.5)) or math.max(20, math.floor(28 * scale + 0.5)),
    labelOffset = micro and math.max(8, math.floor(10 * scale + 0.5)) or math.max(12, math.floor(18 * scale + 0.5)),
    tooSmall = sw < 96 or sh < 180,
  }

  local m = ui.margin
  local g = ui.gap

  ui.layout = {
    header = { x = m, y = m, w = sw - m * 2, h = ui.headerH },
    nav = { x = m, y = m + ui.headerH + g, w = sw - m * 2, h = ui.navH },
    footer = { x = m, y = sh - m - ui.footerH, w = sw - m * 2, h = ui.footerH },
  }

  local bodyTop
  local bodyBottom

  if micro then
    bodyTop = ui.layout.header.y + ui.layout.header.h + g
    bodyBottom = sh - m
  else
    bodyTop = ui.layout.nav.y + ui.layout.nav.h + g
    bodyBottom = ui.layout.footer.y - g
  end

  ui.layout.body = {
    x = m,
    y = bodyTop,
    w = sw - m * 2,
    h = bodyBottom - bodyTop,
  }
end

local function splitVertical(r, topRatio, gap)
  gap = gap or ui.gap
  local topH = math.floor((r.h - gap) * topRatio)
  return {
    x = r.x, y = r.y, w = r.w, h = topH
  }, {
    x = r.x, y = r.y + topH + gap, w = r.w, h = r.h - topH - gap
  }
end

local function splitHorizontal(r, leftRatio, gap)
  gap = gap or ui.gap
  local leftW = math.floor((r.w - gap) * leftRatio)
  return {
    x = r.x, y = r.y, w = leftW, h = r.h
  }, {
    x = r.x + leftW + gap, y = r.y, w = r.w - leftW - gap, h = r.h
  }
end

-- === Devices / telemetry ===
local wrappedCache = {}
local modem = nil

local function nowMs()
  if os.epoch then
    return os.epoch("utc")
  end

  return math.floor((os.clock() or 0) * 1000)
end

local function refreshWrapped(name)
  if type(name) ~= "string" or name == "" then
    return nil
  end

  local ok, obj = pcall(peripheral.wrap, name)
  if ok and obj then
    wrappedCache[name] = obj
    return obj
  end

  wrappedCache[name] = false
  return nil
end

local function getWrapped(name)
  local cached = wrappedCache[name]
  if cached == false then
    if peripheral.isPresent and peripheral.isPresent(name) then
      return refreshWrapped(name)
    end
    return nil
  end

  if cached then
    return cached
  end

  return refreshWrapped(name)
end

local function getModem()
  if modem then
    return modem
  end

  modem = getWrapped(DEVICES.modem)
  if modem and type(modem.getNamesRemote) == "function" then
    return modem
  end

  modem = nil
  return nil
end

local function safeCall(name, method, ...)
  if type(name) ~= "string" or name == "" then
    return false, "invalid device"
  end

  local obj = getWrapped(name)
  if obj and type(obj[method]) == "function" then
    local ok, result1, result2, result3, result4, result5 = pcall(obj[method], ...)
    if ok then
      return true, result1, result2, result3, result4, result5
    end
  end

  local back = getModem()
  if back and type(back.callRemote) == "function" then
    local ok, result1, result2, result3, result4, result5 = pcall(back.callRemote, name, method, ...)
    if ok then
      return true, result1, result2, result3, result4, result5
    end
  end

  return false, nil
end

local function devicePresent(name)
  if getWrapped(name) then
    return true
  end

  local back = getModem()
  if back and type(back.isPresentRemote) == "function" then
    local ok, result = pcall(back.isPresentRemote, name)
    if ok then
      return result == true
    end
  end

  return false
end

local function safeNumber(v, default)
  if type(v) == "number" then
    return v
  end
  return default or 0
end

local function safeBool(v)
  return v == true
end

local function firstLine(s)
  s = tostring(s or "")
  local idx = string.find(s, "\n", 1, true)
  if idx then
    return string.sub(s, 1, idx - 1)
  end
  return s
end

local function formatCompactNumber(n)
  if type(n) ~= "number" then
    return tostring(n or "n/a")
  end

  local abs = math.abs(n)

  if abs >= 1e15 then
    return string.format("%.2fP", n / 1e15)
  elseif abs >= 1e12 then
    return string.format("%.2fT", n / 1e12)
  elseif abs >= 1e9 then
    return string.format("%.2fG", n / 1e9)
  elseif abs >= 1e6 then
    return string.format("%.2fM", n / 1e6)
  elseif abs >= 1e3 then
    return string.format("%.2fk", n / 1e3)
  end

  return tostring(round(n, 2))
end

local function formatRate(n, suffix)
  return formatCompactNumber(safeNumber(n, 0)) .. (suffix or "")
end

local function formatPercent(p)
  if type(p) ~= "number" then
    return "n/a"
  end
  return tostring(math.floor(p * 100 + 0.5)) .. " %"
end

local function formatEnergy(n)
  return formatCompactNumber(safeNumber(n, 0)) .. " FE"
end

local function formatTemperatureMK(kelvin)
  local mk = safeNumber(kelvin, 0) / 1000000
  return mk, string.format("%.1f MK", mk)
end

local function tableCount(t)
  if type(t) ~= "table" then
    return 0
  end

  local c = 0
  for _ in pairs(t) do
    c = c + 1
  end
  return c
end

local function readReaderData(name)
  local ok, data = safeCall(name, "getBlockData")
  if not ok or type(data) ~= "table" then
    return {
      ok = false,
      present = devicePresent(name),
      amount = 0,
      amountText = "n/a",
      id = "n/a",
      active = false,
    }
  end

  local amount = 0
  local chemId = "n/a"

  if type(data.chemical_tanks) == "table" and type(data.chemical_tanks[1]) == "table" then
    local stored = data.chemical_tanks[1].stored
    if type(stored) == "table" then
      amount = safeNumber(stored.amount, 0)
      chemId = stored.id or chemId
    end
  end

  if amount == 0 and type(data.chemical_amount) == "number" then
    amount = data.chemical_amount
    chemId = data.chemical_id or chemId
  end

  local isCreative = amount >= 9e18
  local amountText = isCreative and "creative" or formatCompactNumber(amount)
  local active = (data.active_state == 1) or (data.active == true)

  return {
    ok = true,
    present = true,
    id = chemId,
    amount = amount,
    amountText = amountText,
    active = active,
    redstone = safeNumber(data.redstone, 0),
    currentRedstone = safeNumber(data.current_redstone, 0),
    raw = data,
  }
end

local function getHohlraumLoaded()
  local ok, item = safeCall(DEVICES.logic, "getHohlraum")
  if ok and type(item) == "table" then
    local name = item.name or ""
    local count = safeNumber(item.count, 0)
    if name ~= "" and name ~= "minecraft:air" and count > 0 then
      return true
    end
  end

  local okList, items = safeCall(DEVICES.fusionController, "list")
  if okList and type(items) == "table" then
    for _, item in pairs(items) do
      if type(item) == "table" and item.name == "mekanismgenerators:hohlraum" and safeNumber(item.count, 0) > 0 then
        return true
      end
    end
  end

  return false
end

local function buildAlerts(data)
  local alerts = {}

  if not data.logicPresent then
    alerts[#alerts + 1] = "logic adapter offline"
  end
  if not data.formed then
    alerts[#alerts + 1] = "structure invalid"
  end
  if data.formed and not data.hohlraumLoaded then
    alerts[#alerts + 1] = "hohlraum missing"
  end
  if data.formed and data.laserAmplifierPct < 0.2 then
    alerts[#alerts + 1] = "laser low"
  end
  if data.formed and data.dtPct < 5 and data.ignited then
    alerts[#alerts + 1] = "dt low"
  end
  if data.maintenance then
    alerts[#alerts + 1] = "maintenance"
  end

  if #alerts == 0 then
    return "none", alerts
  end

  return alerts[1], alerts
end

local function resolveStatus(data)
  if not data.logicPresent or not data.formed then
    return "OFFLINE", "OFFLINE / NOT FORMED"
  end

  if data.maintenance then
    return "WARNING", "FORMED / MAINTENANCE"
  end

  if data.ignited then
    if data.alerts ~= "none" then
      return "WARNING", "FORMED / ONLINE / CHECK"
    end
    return "STABLE", "FORMED / ONLINE / SAFE"
  end

  if data.hohlraumLoaded and data.laserAmplifierPct >= 0.99 then
    return "FORMED", "FORMED / READY / LASER"
  end

  return "FORMED", "FORMED / STANDBY"
end

local function pollLiveData(force)
  local now = nowMs()
  if not force and state.live.cache and (now - state.live.lastPoll) < CONTROL.telemetryPollMs then
    return state.live.cache
  end

  local logicPresent = devicePresent(DEVICES.logic)
  local inductionPresent = devicePresent(DEVICES.induction)
  local amplifierPresent = devicePresent(DEVICES.laserAmplifier)
  local laserPresent = devicePresent(DEVICES.laser)

  local formed = false
  local ignited = false
  local logicMode = "OFFLINE"
  local injectionRate = 0
  local productionRate = 0
  local plasmaRaw = 0
  local caseRaw = 0

  local ok, value = safeCall(DEVICES.logic, "isFormed")
  if ok then formed = safeBool(value) end

  ok, value = safeCall(DEVICES.logic, "isIgnited")
  if ok then ignited = safeBool(value) end

  ok, value = safeCall(DEVICES.logic, "getLogicMode")
  if ok then logicMode = tostring(value or "UNKNOWN") end

  ok, value = safeCall(DEVICES.logic, "getInjectionRate")
  if ok then injectionRate = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.logic, "getProductionRate")
  if ok then productionRate = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.logic, "getPlasmaTemperature")
  if ok then plasmaRaw = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.logic, "getCaseTemperature")
  if ok then caseRaw = safeNumber(value, 0) end

  local dtPct = 0
  local dPct = 0
  local tPct = 0
  local waterPct = 0
  local steamPct = 0
  local dtNeeded = 0
  local dNeeded = 0
  local tNeeded = 0
  local activeCooled = false
  local environmentalLoss = 0
  local transferLoss = 0

  ok, value = safeCall(DEVICES.logic, "getDTFuelFilledPercentage")
  if ok then dtPct = safeNumber(value, 0) * 100 end

  ok, value = safeCall(DEVICES.logic, "getDeuteriumFilledPercentage")
  if ok then dPct = safeNumber(value, 0) * 100 end

  ok, value = safeCall(DEVICES.logic, "getTritiumFilledPercentage")
  if ok then tPct = safeNumber(value, 0) * 100 end

  ok, value = safeCall(DEVICES.logic, "getWaterFilledPercentage")
  if ok then waterPct = safeNumber(value, 0) * 100 end

  ok, value = safeCall(DEVICES.logic, "getSteamFilledPercentage")
  if ok then steamPct = safeNumber(value, 0) * 100 end

  ok, value = safeCall(DEVICES.logic, "getDTFuelNeeded")
  if ok then dtNeeded = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.logic, "getDeuteriumNeeded")
  if ok then dNeeded = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.logic, "getTritiumNeeded")
  if ok then tNeeded = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.logic, "isActiveCooledLogic")
  if ok then activeCooled = safeBool(value) end

  ok, value = safeCall(DEVICES.logic, "getEnvironmentalLoss")
  if ok then environmentalLoss = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.logic, "getTransferLoss")
  if ok then transferLoss = safeNumber(value, 0) end

  local energy = 0
  local energyMax = 0
  local energyPct = 0
  local lastInput = 0
  local lastOutput = 0
  local transferCap = 0
  local inductionMode = false
  local inductionFormed = false

  ok, value = safeCall(DEVICES.induction, "getEnergy")
  if ok then energy = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.induction, "getMaxEnergy")
  if ok then energyMax = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.induction, "getEnergyFilledPercentage")
  if ok then energyPct = safeNumber(value, 0) * 100 end

  ok, value = safeCall(DEVICES.induction, "getLastInput")
  if ok then lastInput = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.induction, "getLastOutput")
  if ok then lastOutput = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.induction, "getTransferCap")
  if ok then transferCap = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.induction, "getMode")
  if ok then inductionMode = safeBool(value) end

  ok, value = safeCall(DEVICES.induction, "isFormed")
  if ok then inductionFormed = safeBool(value) end

  local amplifierEnergy = 0
  local amplifierMax = 0
  local amplifierPct = 0
  local amplifierMode = "n/a"
  local amplifierDelay = 0

  ok, value = safeCall(DEVICES.laserAmplifier, "getEnergy")
  if ok then amplifierEnergy = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.laserAmplifier, "getMaxEnergy")
  if ok then amplifierMax = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.laserAmplifier, "getEnergyFilledPercentage")
  if ok then amplifierPct = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.laserAmplifier, "getRedstoneMode")
  if ok then amplifierMode = tostring(value or "n/a") end

  ok, value = safeCall(DEVICES.laserAmplifier, "getDelay")
  if ok then amplifierDelay = safeNumber(value, 0) end

  local laserEnergy = 0
  local laserMax = 0
  local laserPct = 0

  ok, value = safeCall(DEVICES.laser, "getEnergy")
  if ok then laserEnergy = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.laser, "getMaxEnergy")
  if ok then laserMax = safeNumber(value, 0) end

  ok, value = safeCall(DEVICES.laser, "getEnergyFilledPercentage")
  if ok then laserPct = safeNumber(value, 0) end

  local readerD = readReaderData(DEVICES.readers.deuterium)
  local readerT = readReaderData(DEVICES.readers.tritium)
  local readerDT = readReaderData(DEVICES.readers.dtFuel)
  local readerActive = readReaderData(DEVICES.readers.active)

  local plasmaMK, plasmaText = formatTemperatureMK(plasmaRaw)
  local caseMK, caseText = formatTemperatureMK(caseRaw)

  local data = {
    unitName = "FUSION REACTOR - UNIT 01",

    logicPresent = logicPresent,
    inductionPresent = inductionPresent,
    amplifierPresent = amplifierPresent,
    laserPresent = laserPresent,

    formed = formed,
    ignited = ignited,
    online = formed and ignited,
    maintenance = state.maintenance,

    logicMode = logicMode,
    injectionRateValue = injectionRate,
    injection = tostring(math.floor(injectionRate + 0.5)) .. " mB/t",
    productionRate = productionRate,
    productionText = formatRate(productionRate, " FE/t"),

    plasmaRaw = plasmaRaw,
    plasmaMK = plasmaMK,
    plasmaText = plasmaText,

    caseRaw = caseRaw,
    caseMK = caseMK,
    caseText = caseText,

    energy = energy,
    energyMax = energyMax,
    energyPct = clamp(energyPct, 0, 100),
    energyText = formatEnergy(energy),
    energyMaxText = formatEnergy(energyMax),
    energyFlowIn = formatRate(lastInput, " FE/t"),
    energyFlowOut = formatRate(lastOutput, " FE/t"),
    transferCapText = formatRate(transferCap, " FE/t"),
    inductionMode = inductionMode and "INPUT" or "OUTPUT",
    inductionFormed = inductionFormed,

    dPct = clamp(dPct, 0, 100),
    tPct = clamp(tPct, 0, 100),
    dtPct = clamp(dtPct, 0, 100),
    waterPct = clamp(waterPct, 0, 100),
    steamPct = clamp(steamPct, 0, 100),
    dNeeded = dNeeded,
    tNeeded = tNeeded,
    dtNeeded = dtNeeded,

    activeCooled = activeCooled,
    environmentalLossText = formatRate(environmentalLoss, " FE/t"),
    transferLossText = formatRate(transferLoss, " FE/t"),

    laserAmplifierEnergy = amplifierEnergy,
    laserAmplifierMax = amplifierMax,
    laserAmplifierPct = amplifierPct,
    laserAmplifierText = formatEnergy(amplifierEnergy),
    laserAmplifierMode = amplifierMode,
    laserAmplifierDelay = amplifierDelay,

    laserEnergy = laserEnergy,
    laserMax = laserMax,
    laserPct = laserPct,
    laserText = formatEnergy(laserEnergy),

    hohlraumLoaded = getHohlraumLoaded(),

    readers = {
      deuterium = readerD,
      tritium = readerT,
      dtFuel = readerDT,
      active = readerActive,
    },

    relayStates = state.live.relayStates,
    relayConfig = CONTROL.relaySides,
  }

  data.laserReady = amplifierPresent and amplifierPct >= 0.99
  data.activeReader = readerActive.active and "ACTIVE" or "IDLE"
  data.activeReaderColor = readerActive.active and C.green or C.muted

  data.alerts, data.alertList = buildAlerts(data)
  data.status, data.stateText = resolveStatus(data)

  state.live.cache = data
  state.live.lastPoll = now
  return data
end

local function relaySideConfigured(key)
  local side = CONTROL.relaySides[key]
  if type(side) == "string" and side ~= "" then
    return side
  end
  return nil
end

-- === Actions (device controls) ===
local function setRelayState(key, enabled)
  local relayName = DEVICES.relays[key]
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

  safeCall(relayName, "setAnalogOutput", side, enabled and CONTROL.relayAnalogStrength or 0)
  state.live.relayStates[key] = enabled
  return true, (enabled and "enabled " or "disabled ") .. tostring(key)
end

local function pulseRelay(key, duration)
  local relayName = DEVICES.relays[key]
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

  local timerId = os.startTimer(duration or CONTROL.laserPulseSeconds)
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

local function getDataSummary(data)
  if state.page == "MAJ" then
    return state.update.remoteStatus or UPDATE_STATUS.IDLE
  end

  if not data.logicPresent then
    return "logic offline"
  end

  if data.alerts ~= "none" then
    return data.alerts
  end

  if data.ignited then
    return "stable"
  end

  if data.formed then
    return "formed"
  end

  return "offline"
end

-- === Update subsystem ===
local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return tostring(nowMs())
end

local function loadUpdateLogTail(maxLines)
  maxLines = math.max(1, math.floor(maxLines or 10))
  state.update.logs = {}

  if not fs.exists(UPDATE_LOG_FILE) then
    return
  end

  local fh = fs.open(UPDATE_LOG_FILE, "r")
  if not fh then
    return
  end

  local text = fh.readAll() or ""
  fh.close()

  local lines = {}
  for line in string.gmatch(text, "[^\r\n]+") do
    lines[#lines + 1] = line
  end

  local startAt = math.max(1, #lines - maxLines + 1)
  for i = startAt, #lines do
    state.update.logs[#state.update.logs + 1] = lines[i]
  end
end

local function appendUpdateLogLine(message)
  local entry = "[" .. nowText() .. "] " .. tostring(message or "event")
  local fh = fs.open(UPDATE_LOG_FILE, "a")
  if fh then
    fh.writeLine(entry)
    fh.close()
  end
  loadUpdateLogTail(12)
end

local function updateStatusColor(status)
  if status == UPDATE_STATUS.UP_TO_DATE then
    return C.green
  end
  if status == UPDATE_STATUS.UPDATE_AVAILABLE or status == UPDATE_STATUS.READY_TO_APPLY then
    return C.orange
  end
  if status == UPDATE_STATUS.CHECKING or status == UPDATE_STATUS.DOWNLOADING or status == UPDATE_STATUS.APPLYING then
    return C.cyan
  end
  if status == UPDATE_STATUS.ROLLBACK_DONE then
    return C.yellow
  end
  if status == UPDATE_STATUS.CHECK_FAILED or status == UPDATE_STATUS.DOWNLOAD_FAILED or status == UPDATE_STATUS.APPLY_FAILED or status == UPDATE_STATUS.ROLLBACK_FAILED then
    return C.red
  end
  return C.muted
end

local function setUpdateStatus(status, detail, logIt)
  state.update.remoteStatus = status or UPDATE_STATUS.IDLE
  state.update.statusDetail = firstLine(detail or "")
  state.update.statusAt = nowText()
  if logIt then
    appendUpdateLogLine("STATUS " .. tostring(state.update.remoteStatus) .. " | " .. tostring(state.update.statusDetail))
  end
end

local function setDownloadedState(flag, count)
  state.update.downloaded = flag == true
  state.update.downloadedFiles = state.update.downloaded and math.max(0, math.floor(count or 0)) or 0
  if not state.update.downloaded then
    state.update.applyConfirmArmed = false
  end
end

local function parseSizeMismatchDetail(raw)
  local path = string.match(raw, "size mismatch for ([^:]+)")
  local expected = string.match(raw, "expected=([0-9]+)")
  local received = string.match(raw, "received=([0-9]+)")
  local url = string.match(raw, "url=(%S+)")
  return path, expected, received, url
end

local function formatUpdateUserError(step, err)
  local raw = firstLine(err or "unknown error")
  local lower = string.lower(raw)

  if string.find(lower, "http disabled", 1, true) then
    return step .. ": HTTP disabled. Enable HTTP in ComputerCraft config."
  end
  if string.find(lower, "http 404", 1, true) then
    return step .. ": remote file not found (404). Check owner/repo/branch/manifestPath."
  end
  if string.find(lower, "source incomplete", 1, true) then
    return step .. ": update source is incomplete (owner/repo/branch)."
  end
  if string.find(lower, "staging", 1, true) then
    return step .. ": staging is invalid or incomplete. Run DOWNLOAD again."
  end
  if string.find(lower, "size mismatch", 1, true) then
    local path, expected, received = parseSizeMismatchDetail(raw)
    if path and expected and received then
      return step .. ": integrity mismatch on " .. tostring(path)
        .. " (expected " .. tostring(expected) .. " bytes, got " .. tostring(received) .. ")."
    end
    return step .. ": file integrity check failed (size mismatch)."
  end
  if string.find(lower, "manifest", 1, true) then
    return step .. ": manifest issue: " .. raw
  end

  return step .. ": " .. raw
end

local function failUpdateStep(step, status, err)
  local userMessage = formatUpdateUserError(step, err)
  state.update.lastError = userMessage
  state.update.lastCheckSummary = string.lower(step) .. " failed"
  setUpdateStatus(status, userMessage, false)
  appendUpdateLogLine(step .. " failed (raw): " .. tostring(firstLine(err)))
  appendUpdateLogLine(step .. " failed (ui): " .. tostring(userMessage))
  return false, userMessage
end

local function clearStagingWithLog(reason)
  local ok, err = UpdateApply.clearPath(UPDATE_TEMP_DIR)
  if ok then
    appendUpdateLogLine("STAGING cleared (" .. tostring(reason or "cleanup") .. ")")
    return true
  end

  appendUpdateLogLine("STAGING cleanup failed (" .. tostring(reason or "cleanup") .. "): " .. tostring(err))
  return false, err
end

local function buildUpdateSource(remoteManifest)
  local source = {
    owner = tostring(UPDATE_CFG.owner or ""),
    repo = tostring(UPDATE_CFG.repo or ""),
    branch = tostring(UPDATE_CFG.branch or "main"),
    rawBaseUrl = tostring(UPDATE_CFG.rawBaseUrl or ""),
  }

  if type(remoteManifest) == "table" and type(remoteManifest.source) == "table" then
    if source.rawBaseUrl == "" and type(remoteManifest.source.rawBaseUrl) == "string" and remoteManifest.source.rawBaseUrl ~= "" then
      source.rawBaseUrl = remoteManifest.source.rawBaseUrl
    end
    if source.owner == "" and type(remoteManifest.source.owner) == "string" then
      source.owner = remoteManifest.source.owner
    end
    if source.repo == "" and type(remoteManifest.source.repo) == "string" then
      source.repo = remoteManifest.source.repo
    end
    if source.branch == "" and type(remoteManifest.source.branch) == "string" then
      source.branch = remoteManifest.source.branch
    end
  end

  return source
end

local function resolveManifestPath(remoteManifest)
  if type(UPDATE_CFG.manifestPath) == "string" and UPDATE_CFG.manifestPath ~= "" then
    return UPDATE_CFG.manifestPath
  end

  if type(remoteManifest) == "table" and type(remoteManifest.source) == "table" and type(remoteManifest.source.manifestPath) == "string" and remoteManifest.source.manifestPath ~= "" then
    return remoteManifest.source.manifestPath
  end

  return UPDATE_MANIFEST_FILE
end

local function validateUpdateSource(source)
  if type(source.rawBaseUrl) == "string" and source.rawBaseUrl ~= "" then
    return true
  end

  if source.owner == "" or source.repo == "" or source.branch == "" then
    return false, "update source incomplete (owner/repo/branch)"
  end

  return true
end

local function refreshLocalUpdateSnapshot()
  local localVersion, versionErr = UpdateVersion.readLocalVersion(UPDATE_VERSION_FILE)
  if localVersion then
    state.update.localVersion = localVersion
  else
    state.update.localVersion = "n/a"
    state.update.lastError = firstLine(versionErr or "version read failed")
  end

  local localManifest, manifestErr = UpdateManifest.readLocal(UPDATE_MANIFEST_FILE)
  if localManifest then
    state.update.localManifest = localManifest
    state.update.channel = tostring(localManifest.channel or UPDATE_CFG.channel)
  else
    state.update.localManifest = nil
    state.update.lastError = firstLine(manifestErr or "manifest read failed")
  end

  local backupMeta = UpdateApply.loadBackupMeta(UPDATE_BACKUP_DIR)
  state.update.canRollback = backupMeta ~= nil
end

local function performUpdateCheck(reason)
  state.update.applyConfirmArmed = false
  state.update.lastCheck = nowText()
  setDownloadedState(false, 0)
  setUpdateStatus(UPDATE_STATUS.CHECKING, "fetching remote manifest", true)
  appendUpdateLogLine("CHECK start: reason=" .. tostring(reason or "manual"))
  refreshLocalUpdateSnapshot()

  if not UpdateClient.isHttpEnabled() then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, "http disabled in ComputerCraft")
  end

  local source = buildUpdateSource(nil)
  local sourceOk, sourceErr = validateUpdateSource(source)
  if not sourceOk then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, sourceErr)
  end

  local manifestPath = resolveManifestPath(nil)
  local manifestUrl = UpdateClient.buildRawUrl(source, manifestPath)
  appendUpdateLogLine("CHECK manifest url: " .. tostring(manifestUrl))
  local remoteManifest, remoteErr = UpdateManifest.readRemote(UpdateClient, manifestUrl)
  if not remoteManifest then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, remoteErr)
  end

  local remoteSource = buildUpdateSource(remoteManifest)
  local remoteSourceOk, remoteSourceErr = validateUpdateSource(remoteSource)
  if not remoteSourceOk then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, remoteSourceErr)
  end

  state.update.remoteManifest = remoteManifest
  state.update.remoteSource = remoteSource
  state.update.remoteVersion = tostring(remoteManifest.version or "n/a")
  state.update.channel = tostring(remoteManifest.channel or UPDATE_CFG.channel)
  appendUpdateLogLine("CHECK integrity mode: " .. tostring(remoteManifest.integrity and remoteManifest.integrity.mode or "size"))
  state.update.pendingFiles = UpdateManifest.computePendingFiles(state.update.localManifest, remoteManifest)
  state.update.filesToUpdate = #state.update.pendingFiles
  state.update.lastError = "none"
  setDownloadedState(false, 0)

  local newer, cmpErr = UpdateVersion.isRemoteNewer(state.update.localVersion, state.update.remoteVersion)
  local status = UPDATE_STATUS.UP_TO_DATE
  if newer == nil then
    if state.update.filesToUpdate > 0 then
      status = UPDATE_STATUS.UPDATE_AVAILABLE
    else
      status = UPDATE_STATUS.UP_TO_DATE
    end
    if cmpErr then
      appendUpdateLogLine("CHECK warning: " .. tostring(cmpErr))
    end
  elseif newer or state.update.filesToUpdate > 0 then
    status = UPDATE_STATUS.UPDATE_AVAILABLE
  else
    status = UPDATE_STATUS.UP_TO_DATE
  end

  state.update.lastCheckSummary = status == UPDATE_STATUS.UPDATE_AVAILABLE and "update available" or "up to date"
  setUpdateStatus(status, "local=" .. tostring(state.update.localVersion) .. " remote=" .. tostring(state.update.remoteVersion) .. " pending=" .. tostring(state.update.filesToUpdate), true)
  appendUpdateLogLine("CHECK done: local=" .. tostring(state.update.localVersion) .. ", remote=" .. tostring(state.update.remoteVersion) .. ", files=" .. tostring(state.update.filesToUpdate))
  return true, state.update.lastCheckSummary
end

local function performUpdateDownload()
  state.update.applyConfirmArmed = false
  setUpdateStatus(UPDATE_STATUS.DOWNLOADING, "preparing staging directory", true)
  appendUpdateLogLine("DOWNLOAD start")

  if not state.update.remoteManifest then
    local ok, err = performUpdateCheck("download precheck")
    if not ok then
      return false, err
    end
  end

  local remoteManifest = state.update.remoteManifest
  local remoteSource = state.update.remoteSource or buildUpdateSource(remoteManifest)
  local sourceOk, sourceErr = validateUpdateSource(remoteSource)
  if not sourceOk then
    clearStagingWithLog("source invalid")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, sourceErr)
  end

  local clearOk, clearErr = clearStagingWithLog("before download")
  if not clearOk then
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, clearErr)
  end

  fs.makeDir(UPDATE_TEMP_DIR)
  appendUpdateLogLine("DOWNLOAD files planned: " .. tostring(#(remoteManifest.files or {})))

  local downloaded, downloadErr = UpdateClient.downloadFiles(remoteSource, remoteManifest.files, UPDATE_TEMP_DIR, appendUpdateLogLine)
  if not downloaded then
    clearStagingWithLog("download failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, downloadErr)
  end

  local stagingContext = {
    remoteVersion = tostring(state.update.remoteVersion or "n/a"),
    manifestVersion = tostring(remoteManifest.version or "n/a"),
    channel = tostring(state.update.channel or "stable"),
    checkedAt = tostring(state.update.lastCheck or "never"),
  }

  local marked, markedErr = UpdateApply.markStagingReady(remoteManifest.files, UPDATE_TEMP_DIR, stagingContext)
  if not marked then
    clearStagingWithLog("staging meta failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, markedErr)
  end

  local valid, validErr = UpdateApply.validateStaging(remoteManifest.files, UPDATE_TEMP_DIR, stagingContext)
  if not valid then
    clearStagingWithLog("staging validation failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, validErr)
  end

  setDownloadedState(true, #downloaded)
  state.update.lastDownload = nowText()
  state.update.lastError = "none"
  state.update.lastCheckSummary = "ready to apply"
  setUpdateStatus(UPDATE_STATUS.READY_TO_APPLY, "downloaded files=" .. tostring(#downloaded), true)
  appendUpdateLogLine("DOWNLOAD done: files=" .. tostring(#downloaded))

  return true, "ready to apply (" .. tostring(#downloaded) .. " files)"
end

local function performUpdateApply()
  if UPDATE_CFG.requireConfirmApply and not state.update.applyConfirmArmed then
    state.update.applyConfirmArmed = true
    setUpdateStatus(UPDATE_STATUS.READY_TO_APPLY, "confirmation required before apply", true)
    appendUpdateLogLine("APPLY waiting confirmation")
    return false, "confirmation required: press APPLY again"
  end

  state.update.applyConfirmArmed = false
  setUpdateStatus(UPDATE_STATUS.APPLYING, "validating staging and applying update", true)
  appendUpdateLogLine("APPLY start")

  local remoteManifest = state.update.remoteManifest
  if not remoteManifest then
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, "check required before apply")
  end

  if not state.update.downloaded then
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, "download required before apply")
  end

  local expectedContext = {
    remoteVersion = tostring(state.update.remoteVersion or "n/a"),
    manifestVersion = tostring(remoteManifest.version or "n/a"),
  }

  local stageOk, stageErr = UpdateApply.validateStaging(remoteManifest.files, UPDATE_TEMP_DIR, expectedContext)
  if not stageOk then
    clearStagingWithLog("apply refused invalid staging")
    setDownloadedState(false, 0)
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, stageErr)
  end

  local context = {
    previousVersion = state.update.localVersion,
    previousManifestVersion = state.update.localManifest and state.update.localManifest.version or "n/a",
  }

  local backupOk, backupErr = UpdateApply.createBackup(remoteManifest.files, UPDATE_BACKUP_DIR, context, appendUpdateLogLine)
  if not backupOk then
    setDownloadedState(false, 0)
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, backupErr)
  end

  local applied, applyErr = UpdateApply.applyFromStaging(remoteManifest.files, UPDATE_TEMP_DIR, appendUpdateLogLine)
  if not applied then
    setUpdateStatus(UPDATE_STATUS.APPLY_FAILED, "apply failed, rollback attempt started", true)
    local rolledBack, rollbackErr = UpdateApply.rollback(UPDATE_BACKUP_DIR, appendUpdateLogLine)
    if rolledBack then
      clearStagingWithLog("after automatic rollback")
      setDownloadedState(false, 0)
      state.update.lastApply = nowText() .. " (auto rollback)"
      state.update.lastError = formatUpdateUserError("APPLY", applyErr)
      state.update.lastCheckSummary = "rollback done after apply failure"
      setUpdateStatus(UPDATE_STATUS.ROLLBACK_DONE, "automatic rollback completed", true)
      appendUpdateLogLine("APPLY failed -> automatic rollback done: " .. tostring(firstLine(applyErr)))
      refreshLocalUpdateSnapshot()
      return false, state.update.lastError .. " (automatic rollback done)"
    end

    clearStagingWithLog("after failed apply/rollback")
    setDownloadedState(false, 0)
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, "apply failed: " .. tostring(applyErr) .. " ; rollback failed: " .. tostring(rollbackErr))
  end

  clearStagingWithLog("after apply success")
  state.update.lastApply = nowText()
  setDownloadedState(false, 0)
  state.update.pendingFiles = {}
  state.update.filesToUpdate = 0
  state.update.lastError = "none"
  state.update.lastCheckSummary = "up to date"
  refreshLocalUpdateSnapshot()
  setUpdateStatus(UPDATE_STATUS.UP_TO_DATE, "apply completed successfully", true)
  appendUpdateLogLine("APPLY success: local version=" .. tostring(state.update.localVersion))

  return true, "apply done"
end

local function performUpdateRollback()
  state.update.applyConfirmArmed = false
  appendUpdateLogLine("ROLLBACK start")

  local rolledBack, rollbackErr = UpdateApply.rollback(UPDATE_BACKUP_DIR, appendUpdateLogLine)
  if not rolledBack then
    setDownloadedState(false, 0)
    return failUpdateStep("ROLLBACK", UPDATE_STATUS.ROLLBACK_FAILED, rollbackErr)
  end

  clearStagingWithLog("after manual rollback")
  state.update.lastApply = nowText() .. " (rollback)"
  setDownloadedState(false, 0)
  state.update.lastError = "none"
  state.update.lastCheckSummary = "rollback done"
  refreshLocalUpdateSnapshot()
  setUpdateStatus(UPDATE_STATUS.ROLLBACK_DONE, "backup restored", true)
  appendUpdateLogLine("ROLLBACK success: local version=" .. tostring(state.update.localVersion))

  return true, "rollback done"
end

local function requestProgramRestart()
  local entrypoint = "start_menu_pages_live_v7.lua"
  if state.update.localManifest and type(state.update.localManifest.entrypoint) == "string" and state.update.localManifest.entrypoint ~= "" then
    entrypoint = state.update.localManifest.entrypoint
  elseif state.update.remoteManifest and type(state.update.remoteManifest.entrypoint) == "string" and state.update.remoteManifest.entrypoint ~= "" then
    entrypoint = state.update.remoteManifest.entrypoint
  end

  state.restartTarget = entrypoint
  state.restartRequested = true
  appendUpdateLogLine("RESTART requested: " .. tostring(entrypoint))
  os.queueEvent("fusion_restart")
  return true, "restart queued: " .. tostring(entrypoint)
end

-- === Rendering ===
local function drawHeader(r, data)
  drawPanel(r.x, r.y, r.w, r.h, nil)
  drawTextCenter(r.x, r.y + sv(10), r.w, data.unitName, C.text, ui.headerTitleSize)

  local capsuleX = r.x + ui.pad
  local capsuleW = r.w - ui.pad * 2
  local capsuleY = r.y + math.floor(r.h * 0.55)
  local capsuleH = math.max(16, sv(18))
  local stateColor = chooseStateColor(data)

  gpu.filledRectangle(capsuleX, capsuleY, capsuleW, capsuleH, C.panel2)
  gpu.rectangle(capsuleX, capsuleY, capsuleW, capsuleH, C.border)
  drawTextCenter(capsuleX, capsuleY + 3, capsuleW, data.stateText, stateColor, 1)
end

local function drawNav(r)
  drawPanel(r.x, r.y, r.w, r.h, nil)

  local innerX = r.x + ui.smallPad
  local innerY = r.y + ui.smallPad
  local innerW = r.w - ui.smallPad * 2
  local innerH = r.h - ui.smallPad * 2
  local tabGap = ui.smallPad
  local count = #PAGES
  local tabW = math.floor((innerW - tabGap * (count - 1)) / count)

  for i, page in ipairs(PAGES) do
    local bx = innerX + (i - 1) * (tabW + tabGap)
    local tone = state.page == page.id and "cyan" or "purple"
    drawButton("PAGE_" .. page.id, bx, innerY, tabW, innerH, page.label, tone, true)
  end
end

local function drawFooter(r, data)
  drawPanel(r.x, r.y, r.w, r.h, "STATUS BAR")

  local leftX = r.x + ui.pad
  local rightX = r.x + r.w - ui.pad
  local y1 = r.y + sv(12)
  local y2 = y1 + sv(18)

  drawText(leftX, y1, "PAGE", C.text, 1)
  drawTextRight(rightX, y1, state.page, C.cyan, 1)

  drawText(leftX, y2, "INFO", C.text, 1)
  drawTextRight(rightX, y2, getDataSummary(data), data.alerts == "none" and C.green or C.orange, 1)
end

local function drawMicroHeader(r, data)
  gpu.filledRectangle(r.x, r.y, r.w, r.h, C.panel)
  gpu.rectangle(r.x, r.y, r.w, r.h, C.border)

  local leftText = "FR-U1"
  local rightText = data.status == "STABLE" and "ON" or data.status
  local centerText = "Lx" .. tostring(CONTROL.laserModuleCount)
  local navW = math.max(24, math.floor(r.w * 0.24))
  local navH = math.max(12, r.h - 2)
  local navX = r.x + r.w - navW - 1
  local navY = r.y + 1
  local navId = state.page == "MAJ" and "PAGE_OVERVIEW" or "PAGE_MAJ"
  local navLabel = state.page == "MAJ" and "HOME" or "MAJ"

  drawText(r.x + ui.pad, r.y + 2, leftText, C.text, 1)
  drawTextCenter(r.x, r.y + 2, r.w, centerText, C.yellow, 1)
  drawTextRight(navX - ui.smallPad, r.y + 2, rightText, chooseStateColor(data), 1)
  drawButton(navId, navX, navY, navW, navH, navLabel, "purple", true)
end

local function drawMicroOverview(r, data)
  drawPanel(r.x, r.y, r.w, r.h, nil)

  local statsH = math.max(44, math.floor(r.h * 0.16))
  local imageH = r.h - statsH - ui.gap

  local imageRect = {
    x = r.x,
    y = r.y,
    w = r.w,
    h = imageH,
  }

  local statsRect = {
    x = r.x,
    y = imageRect.y + imageRect.h + ui.gap,
    w = r.w,
    h = statsH,
  }

  gpu.filledRectangle(imageRect.x, imageRect.y, imageRect.w, imageRect.h, C.white)
  drawImageStack(imageRect.x + 1, imageRect.y + 1, imageRect.w - 2, imageRect.h - 2, data)

  gpu.filledRectangle(statsRect.x, statsRect.y, statsRect.w, statsRect.h, C.panel)
  gpu.rectangle(statsRect.x, statsRect.y, statsRect.w, statsRect.h, C.border)

  local y = statsRect.y + 4
  drawText(statsRect.x + ui.pad, y, "P", C.text, 1)
  drawTextRight(statsRect.x + statsRect.w - ui.pad, y, tostring(round(data.plasmaMK, 0)) .. " MK", C.text, 1)

  y = y + 12
  drawText(statsRect.x + ui.pad, y, "E", C.text, 1)
  drawTextRight(statsRect.x + statsRect.w - ui.pad, y, tostring(math.floor(data.energyPct or 0)) .. "%", C.green, 1)

  y = y + 12
  drawText(statsRect.x + ui.pad, y, "DT", C.text, 1)
  drawTextRight(statsRect.x + statsRect.w - ui.pad, y, tostring(math.floor(data.dtPct or 0)) .. "%", C.yellow, 1)

  y = y + 12
  drawText(statsRect.x + ui.pad, y, "LG", C.text, 1)
  drawTextRight(statsRect.x + statsRect.w - ui.pad, y, data.logicMode or "UNK", C.cyan, 1)
end

local function drawMicroMajPage(r, data)
  drawPanel(r.x, r.y, r.w, r.h, "MAJ")

  local infoH = math.max(64, math.floor(r.h * 0.46))
  local infoRect = { x = r.x + ui.smallPad, y = r.y + sv(18), w = r.w - ui.smallPad * 2, h = infoH }
  local actionsRect = {
    x = r.x + ui.smallPad,
    y = infoRect.y + infoRect.h + ui.smallPad,
    w = r.w - ui.smallPad * 2,
    h = r.h - infoH - sv(18) - ui.smallPad * 2,
  }

  local rowY = infoRect.y + 2
  drawText(infoRect.x + 1, rowY, "LV", C.text, 1)
  drawTextRight(infoRect.x + infoRect.w - 1, rowY, state.update.localVersion, C.cyan, 1)

  rowY = rowY + 10
  drawText(infoRect.x + 1, rowY, "RV", C.text, 1)
  drawTextRight(infoRect.x + infoRect.w - 1, rowY, state.update.remoteVersion, C.yellow, 1)

  rowY = rowY + 10
  drawText(infoRect.x + 1, rowY, "ST", C.text, 1)
  drawTextRight(infoRect.x + infoRect.w - 1, rowY, state.update.remoteStatus, updateStatusColor(state.update.remoteStatus), 1)

  rowY = rowY + 10
  drawText(infoRect.x + 1, rowY, "FILES", C.text, 1)
  drawTextRight(infoRect.x + infoRect.w - 1, rowY, tostring(state.update.filesToUpdate), state.update.filesToUpdate > 0 and C.orange or C.green, 1)

  rowY = rowY + 10
  drawText(infoRect.x + 1, rowY, "ERR", C.text, 1)
  drawTextRight(infoRect.x + infoRect.w - 1, rowY, state.update.lastError == "none" and "-" or firstLine(state.update.lastError), state.update.lastError == "none" and C.muted or C.red, 1)

  local pad = 1
  local gap = math.max(1, math.floor(ui.smallPad * 0.6))
  local bw = math.floor((actionsRect.w - gap) / 2)
  local bh = math.max(11, math.floor((actionsRect.h - gap * 2) / 3))
  local x1 = actionsRect.x + pad
  local x2 = x1 + bw + gap
  local y1 = actionsRect.y + pad
  local y2 = y1 + bh + gap
  local y3 = y2 + bh + gap

  drawButton("UPDATE_CHECK", x1, y1, bw, bh, "CHECK", "cyan", true)
  drawButton("UPDATE_DOWNLOAD", x2, y1, bw, bh, "DL", "purple", true)
  drawButton("UPDATE_APPLY", x1, y2, bw, bh, "APPLY", "green", state.update.downloaded)
  drawButton("UPDATE_ROLLBACK", x2, y2, bw, bh, "ROLL", "orange", state.update.canRollback)
  drawButton("UPDATE_RESTART", x1, y3, bw * 2 + gap, bh, "RESTART", "red", true)
end

local function drawUpdatePage(r)
  local topRatio = ui.compact and 0.68 or 0.72
  local top, actions = splitVertical(r, topRatio)
  local statusRect, logRect

  if ui.compact then
    statusRect, logRect = splitVertical(top, 0.54)
  else
    statusRect, logRect = splitHorizontal(top, 0.52)
  end

  drawPanel(statusRect.x, statusRect.y, statusRect.w, statusRect.h, "MAJ STATUS")
  local baseY = statusRect.y + sv(54)
  local step = math.max(12, sv(16))
  local statusRows = {
    { label = "STATUS", value = state.update.remoteStatus, color = updateStatusColor(state.update.remoteStatus) },
    { label = "DETAIL", value = state.update.statusDetail ~= "" and state.update.statusDetail or "-", color = C.muted },
    { label = "LOCAL VERSION", value = state.update.localVersion, color = C.cyan },
    { label = "REMOTE VERSION", value = state.update.remoteVersion, color = C.yellow },
    { label = "CHANNEL", value = state.update.channel, color = C.text },
    { label = "FILES TO UPDATE", value = tostring(state.update.filesToUpdate), color = state.update.filesToUpdate > 0 and C.orange or C.green },
    { label = "LAST CHECK", value = state.update.lastCheck, color = C.text },
    { label = "LAST APPLY", value = state.update.lastApply, color = C.text },
    { label = "LAST DOWNLOAD", value = state.update.lastDownload, color = C.text },
    { label = "CHECK SUMMARY", value = state.update.lastCheckSummary, color = C.muted },
    { label = "LAST ERROR", value = state.update.lastError == "none" and "-" or firstLine(state.update.lastError), color = state.update.lastError == "none" and C.muted or C.red },
  }

  local maxRows = math.max(4, math.floor((statusRect.h - sv(58)) / step))
  local rowCount = math.min(maxRows, #statusRows)
  for i = 1, rowCount do
    local row = statusRows[i]
    drawToggleRow(statusRect, baseY + step * (i - 1), row.label, row.value, row.color)
  end

  drawPanel(logRect.x, logRect.y, logRect.w, logRect.h, "MAJ LOG")
  local logY = logRect.y + sv(54)
  local maxLogLines = math.max(3, math.floor((logRect.h - sv(62)) / step))
  local totalLines = #state.update.logs
  local startIndex = math.max(1, totalLines - maxLogLines + 1)
  local lineIndex = 0

  if totalLines == 0 then
    drawText(logRect.x + ui.pad, logY, "no update log yet", C.muted, 1)
  else
    for i = startIndex, totalLines do
      local line = state.update.logs[i]
      local low = string.lower(line)
      local color = (string.find(low, "failed", 1, true) or string.find(low, "error", 1, true)) and C.red or C.text
      drawText(logRect.x + ui.pad, logY + step * lineIndex, firstLine(line), color, 1)
      lineIndex = lineIndex + 1
    end
  end

  drawPanel(actions.x, actions.y, actions.w, actions.h, "MAJ ACTIONS")
  local pad = ui.pad
  local gap = ui.gap
  local usableW = actions.w - pad * 2
  local bh = math.max(ui.buttonH, sv(34))
  local y1 = actions.y + sv(54)
  local y2 = y1 + bh + sv(10)

  local bw3 = math.floor((usableW - gap * 2) / 3)
  local x1 = actions.x + pad
  local x2 = x1 + bw3 + gap
  local x3 = x2 + bw3 + gap

  drawButton("UPDATE_CHECK", x1, y1, bw3, bh, "[CHECK]", "cyan", true)
  drawButton("UPDATE_DOWNLOAD", x2, y1, bw3, bh, "[DOWNLOAD]", "purple", true)
  drawButton("UPDATE_APPLY", x3, y1, bw3, bh, UPDATE_CFG.requireConfirmApply and (state.update.applyConfirmArmed and "[APPLY CONFIRM]" or "[APPLY]") or "[APPLY]", "green", state.update.downloaded)

  local bw2 = math.floor((usableW - gap) / 2)
  drawButton("UPDATE_ROLLBACK", x1, y2, bw2, bh, "[ROLLBACK]", "orange", state.update.canRollback)
  drawButton("UPDATE_RESTART", x1 + bw2 + gap, y2, bw2, bh, "[RESTART]", "red", true)
end

local function drawImageStack(slotX, slotY, slotW, slotH, data, forcedLayout)
  local configuredModuleCount = math.max(1, tonumber(CONTROL.laserModuleCount) or 1)
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
      drawImageSafe(moduleVariant.image, moduleX, moduleY)
      drawModuleCableFluxAt(moduleX, moduleY, moduleVariant.width, moduleVariant.height, data)
    end
    startY = startY + modulesBlockH + gap
  else
    local moduleTextY = startY + math.max(0, math.floor((ui.smallPad + textPixelHeight(1)) / 2))
    drawTextCenter(slotX, moduleTextY, slotW, "LASER x" .. tostring(configuredCount), C.muted, 1)
    startY = startY + ui.smallPad + textPixelHeight(1) + ui.smallPad
  end

  local reactorX = slotX + math.floor((slotW - reactorVariant.width) / 2)
  drawImageSafe(reactorVariant.image, reactorX, startY)
  drawReactorCoreAnimationAt(reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawReactorRightCableFluxAt(reactorX, startY, reactorVariant.width, reactorVariant.height, data)
  drawReactorBottomGasFluxAt(reactorX, startY, reactorVariant.width, reactorVariant.height, data)

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

local function drawOverviewPage(r, data)
  local alertsH = math.max(62, sv(72))
  local main = { x = r.x, y = r.y, w = r.w, h = r.h - alertsH - ui.gap }
  local alerts = { x = r.x, y = main.y + main.h + ui.gap, w = r.w, h = alertsH }

  local candidateRatios = ui.compact and {1.00, 0.72, 0.66, 0.60, 0.56, 0.52} or {0.64, 0.60, 0.56, 0.52, 0.50, 0.48}
  local left, right, selectedRatio, overviewLayout
  local infoMinW = ui.compact and math.max(110, math.floor(main.w * 0.45)) or math.max(140, math.floor(main.w * 0.28))

  for _, ratio in ipairs(candidateRatios) do
    local testLeft, testRight
    if ui.compact then
      local splitH = math.floor((main.h - ui.gap) * ratio)
      testLeft = { x = main.x, y = main.y, w = main.w, h = splitH }
      testRight = { x = main.x, y = main.y + splitH + ui.gap, w = main.w, h = main.h - splitH - ui.gap }
    else
      local splitW = math.floor((main.w - ui.gap) * ratio)
      testLeft = { x = main.x, y = main.y, w = splitW, h = main.h }
      testRight = { x = main.x + splitW + ui.gap, y = main.y, w = main.w - splitW - ui.gap, h = main.h }
    end

    local innerX = testLeft.x + ui.pad
    local innerY = testLeft.y + sv(38)
    local innerW = testLeft.w - ui.pad * 2
    local innerH = testLeft.h - sv(46)

    if innerW > 20 and innerH > 20 then
      local imgInset = 1
      local imgX = innerX + imgInset
      local imgY = innerY + imgInset
      local imgW = innerW - imgInset * 2
      local imgH = innerH - imgInset * 2
      local fit = chooseOverviewStackLayout(imgW, imgH, CONTROL.laserModuleCount)

      if fit and fit.reactor and (ui.compact or testRight.w >= infoMinW) and testRight.h >= math.max(120, sv(160)) then
        left, right, selectedRatio, overviewLayout = testLeft, testRight, ratio, fit
        break
      end
    end
  end

  if not left then
    if ui.compact then
      left, right = splitVertical(main, 0.66)
    else
      left, right = splitHorizontal(main, 0.60)
    end

    local innerX = left.x + ui.pad
    local innerY = left.y + sv(38)
    local innerW = left.w - ui.pad * 2
    local innerH = left.h - sv(46)
    overviewLayout = chooseOverviewStackLayout(math.max(8, innerW - 2), math.max(8, innerH - 2), CONTROL.laserModuleCount)
  end

  drawPanel(left.x, left.y, left.w, left.h, "REACTOR")
  local innerX = left.x + ui.pad
  local innerY = left.y + sv(38)
  local innerW = left.w - ui.pad * 2
  local innerH = left.h - sv(46)
  gpu.filledRectangle(innerX, innerY, innerW, innerH, C.white)
  gpu.rectangle(innerX, innerY, innerW, innerH, C.border)

  local imgInset = 1
  local imgX = innerX + imgInset
  local imgY = innerY + imgInset
  local imgW = innerW - imgInset * 2
  local imgH = innerH - imgInset * 2

  drawImageStack(imgX, imgY, imgW, imgH, data, overviewLayout)

  local badgeW = math.max(90, sv(116))
  local badgeH = math.max(16, sv(18))
  local badgeX = innerX + innerW - badgeW - ui.smallPad
  local badgeY = innerY + ui.smallPad
  local statusColor = chooseStateColor(data)

  gpu.filledRectangle(badgeX, badgeY, badgeW, badgeH, C.panel)
  gpu.rectangle(badgeX, badgeY, badgeW, badgeH, C.border)
  drawTextCenter(badgeX, badgeY + math.max(0, math.floor((badgeH - textPixelHeight(1)) / 2)), badgeW, data.status, statusColor, 1)

  local countBadgeW = math.max(90, sv(116))
  local countBadgeH = badgeH
  local countBadgeX = badgeX
  local countBadgeY = badgeY + badgeH + math.max(2, math.floor(ui.smallPad * 0.5))
  gpu.filledRectangle(countBadgeX, countBadgeY, countBadgeW, countBadgeH, C.panel)
  gpu.rectangle(countBadgeX, countBadgeY, countBadgeW, countBadgeH, C.border)
  drawTextCenter(countBadgeX, countBadgeY + math.max(0, math.floor((countBadgeH - textPixelHeight(1)) / 2)), countBadgeW, "LASER x" .. tostring(CONTROL.laserModuleCount), C.yellow, 1)

  drawPanel(right.x, right.y, right.w, right.h, "POWER & FUEL")
  local px = right.x + ui.pad
  local pw = right.w - ui.pad * 2
  local topY = right.y + sv(50)
  local rowGap = sv(16)
  local step = ui.gaugeH + rowGap

  local availableH = right.h - sv(120)
  local gaugeCount = availableH < (step * 5) and 4 or 5

  drawGauge(px, topY, pw, ui.gaugeH, data.energyPct, C.green, "ENERGY", data.energyText)
  drawGauge(px, topY + step, pw, ui.gaugeH, clamp(data.caseMK, 0, 100), C.orange, "CASE", tostring(round(data.caseMK, 1)) .. " MK")
  drawGauge(px, topY + step * 2, pw, ui.gaugeH, data.dPct, C.green, "D", tostring(data.dPct) .. " %")
  drawGauge(px, topY + step * 3, pw, ui.gaugeH, data.tPct, C.cyan, "T", tostring(data.tPct) .. " %")
  if gaugeCount >= 5 then
    drawGauge(px, topY + step * 4, pw, ui.gaugeH, data.dtPct, C.yellow, "DT", tostring(data.dtPct) .. " %")
  end

  local fy = right.y + right.h - (gaugeCount >= 5 and sv(72) or sv(54))
  drawToggleRow(right, fy, "INJECTION", data.injection, C.text)
  drawToggleRow(right, fy + sv(18), "PRODUCTION", data.productionText, C.green)
  drawToggleRow(right, fy + sv(36), "LOGIC", data.logicMode, C.cyan)
  if gaugeCount >= 5 then
    drawToggleRow(right, fy + sv(54), "LASER", data.laserReady and "READY" or "NOT READY", data.laserReady and C.green or C.red)
  end

  drawPanel(alerts.x, alerts.y, alerts.w, alerts.h, "ALERTS")
  local ty = alerts.y + math.max(0, math.floor((alerts.h - textPixelHeight(1)) / 2))
  drawTextCenter(alerts.x, ty, alerts.w, data.alerts or "none", data.alerts == "none" and C.green or C.orange, 1)
end

local function drawControlPage(r, data)
  local left, right
  if ui.compact then
    left, right = splitVertical(r, 0.54)
  else
    left, right = splitHorizontal(r, 0.52)
  end

  drawPanel(left.x, left.y, left.w, left.h, "COMMAND CENTER")

  local pad = ui.pad
  local gap = ui.gap
  local bw = math.floor((left.w - pad * 2 - gap) / 2)
  local bh = math.max(ui.buttonH, sv(36))
  local x1 = left.x + pad
  local x2 = x1 + bw + gap
  local y1 = left.y + sv(54)
  local y2 = y1 + bh + sv(12)
  local y3 = y2 + bh + sv(12)

  drawButton("START", x1, y1, bw, bh, "[START]", "green", true)
  drawButton("STOP", x2, y1, bw, bh, "[STOP]", "red", true)
  drawButton("AUTO", x1, y2, bw, bh, state.auto and "[AUTO UI ON]" or "[AUTO UI OFF]", "orange", true)
  drawButton("SCRAM", x2, y2, bw, bh, "[SCRAM]", "red", true)
  drawButton("FIRE_LASER", x1, y3, bw, bh, "[FIRE LASER]", "cyan", true)
  drawButton("FILL_HOHLRAUM", x2, y3, bw, bh, "[HOHLRAUM]", "purple", true)

  local infoY = y3 + bh + sv(18)
  drawToggleRow(left, infoY, "MODE", data.logicMode, C.cyan)
  drawToggleRow(left, infoY + sv(18), "STATUS", data.status, chooseStateColor(data))
  drawToggleRow(left, infoY + sv(36), "AMPLIFIER", data.laserAmplifierText, data.laserReady and C.green or C.orange)
  drawToggleRow(left, infoY + sv(54), "LAST ACTION", state.lastAction, C.cyan)

  drawPanel(right.x, right.y, right.w, right.h, "MANAGEMENT")
  local rx = right.x + ui.pad
  local rw = right.w - ui.pad * 2
  local rowY = right.y + sv(54)

  drawToggleRow(right, rowY, "IGNITION PROFILE (UI)", "P" .. tostring(state.ignitionProfile), C.yellow)
  drawToggleRow(right, rowY + sv(18), "MANUAL FUEL", state.manualFuel and "OPEN" or "CLOSED", state.manualFuel and C.orange or C.muted)
  drawToggleRow(right, rowY + sv(36), "MAINTENANCE", state.maintenance and "ON" or "OFF", state.maintenance and C.orange or C.muted)
  drawToggleRow(right, rowY + sv(54), "LASER RELAY", relaySideConfigured("laserCharge") or "UNSET", relaySideConfigured("laserCharge") and C.green or C.orange)
  drawToggleRow(right, rowY + sv(72), "DEUT RELAY", relaySideConfigured("deuteriumTank") or "UNSET", relaySideConfigured("deuteriumTank") and C.green or C.orange)
  drawToggleRow(right, rowY + sv(90), "TRIT RELAY", relaySideConfigured("tritiumTank") or "UNSET", relaySideConfigured("tritiumTank") and C.green or C.orange)
  drawToggleRow(right, rowY + sv(108), "HOHLRAUM", data.hohlraumLoaded and "LOADED" or "MISSING", data.hohlraumLoaded and C.green or C.red)

  local by1 = right.y + right.h - sv(122)
  local bw2 = math.floor((rw - gap) / 2)
  local bx1 = rx
  local bx2 = rx + bw2 + gap

  drawButton("PROFILE_PREV", bx1, by1, bw2, bh, "[PROFILE UI -]", "purple", true)
  drawButton("PROFILE_NEXT", bx2, by1, bw2, bh, "[PROFILE UI +]", "purple", true)
  drawButton("MANUAL_FUEL", bx1, by1 + bh + sv(12), bw2, bh, state.manualFuel and "[FUEL CLOSE]" or "[FUEL OPEN]", "orange", true)
  drawButton("MAINTENANCE", bx2, by1 + bh + sv(12), bw2, bh, state.maintenance and "[MAINT OFF]" or "[MAINT ON]", "orange", true)
end

local function drawFuelPage(r, data)
  local top, bottom = splitVertical(r, 0.56)

  drawPanel(top.x, top.y, top.w, top.h, "FUEL MANAGEMENT")
  local x = top.x + ui.pad
  local w = top.w - ui.pad * 2
  local topY = top.y + sv(54)
  local step = ui.gaugeH + sv(20)

  drawGauge(x, topY, w, ui.gaugeH, data.dPct, C.green, "DEUTERIUM CORE", tostring(math.floor(data.dPct + 0.5)) .. " %")
  drawGauge(x, topY + step, w, ui.gaugeH, data.tPct, C.cyan, "TRITIUM CORE", tostring(math.floor(data.tPct + 0.5)) .. " %")
  drawGauge(x, topY + step * 2, w, ui.gaugeH, data.dtPct, C.yellow, "D-T CORE", tostring(math.floor(data.dtPct + 0.5)) .. " %")
  drawGauge(x, topY + step * 3, w, ui.gaugeH, data.energyPct, C.green, "ENERGY BUFFER", data.energyText)

  local infoY = top.y + top.h - sv(92)
  drawToggleRow(top, infoY, "SUPPLY D", data.readers.deuterium.amountText, data.readers.deuterium.ok and C.green or C.orange)
  drawToggleRow(top, infoY + sv(18), "SUPPLY T", data.readers.tritium.amountText, data.readers.tritium.ok and C.cyan or C.orange)
  drawToggleRow(top, infoY + sv(36), "SUPPLY DT", data.readers.dtFuel.amountText, data.readers.dtFuel.ok and C.yellow or C.orange)
  drawToggleRow(top, infoY + sv(54), "ACTIVE READER", data.activeReader, data.activeReaderColor)

  drawPanel(bottom.x, bottom.y, bottom.w, bottom.h, "FUEL ACTIONS")
  local pad = ui.pad
  local gap = ui.gap
  local bw = math.floor((bottom.w - pad * 2 - gap) / 2)
  local bh = math.max(ui.buttonH, sv(36))
  local x1 = bottom.x + pad
  local x2 = x1 + bw + gap
  local y1 = bottom.y + sv(54)
  local y2 = y1 + bh + sv(12)

  drawButton("MANUAL_FUEL", x1, y1, bw, bh, state.manualFuel and "[FUEL CLOSE]" or "[FUEL OPEN]", "orange", true)
  drawButton("FILL_HOHLRAUM", x2, y1, bw, bh, "[LOAD HOHLRAUM]", "purple", true)
  drawButton("PROFILE_PREV", x1, y2, bw, bh, "[PROFILE UI -]", "purple", true)
  drawButton("PROFILE_NEXT", x2, y2, bw, bh, "[PROFILE UI +]", "purple", true)
end

local function drawSystemPage(r, data)
  local left, right
  if ui.compact then
    left, right = splitVertical(r, 0.50)
  else
    left, right = splitHorizontal(r, 0.50)
  end

  drawPanel(left.x, left.y, left.w, left.h, "SYSTEM INFO")
  local rowY = left.y + sv(54)
  drawToggleRow(left, rowY, "GPU", ACTIVE_GPU_NAME, C.cyan)
  drawToggleRow(left, rowY + sv(18), "SCREEN", tostring(ui.sw) .. "x" .. tostring(ui.sh), C.text)
  drawToggleRow(left, rowY + sv(36), "MODE", tostring(GPU_MODE), C.text)
  drawToggleRow(left, rowY + sv(54), "LOGIC", data.logicPresent and "ONLINE" or "OFFLINE", data.logicPresent and C.green or C.red)
  drawToggleRow(left, rowY + sv(72), "INDUCTION", data.inductionPresent and "ONLINE" or "OFFLINE", data.inductionPresent and C.green or C.red)
  drawToggleRow(left, rowY + sv(90), "AMPLIFIER", data.amplifierPresent and "ONLINE" or "OFFLINE", data.amplifierPresent and C.green or C.red)
  drawToggleRow(left, rowY + sv(108), "LASER", data.laserPresent and "ONLINE" or "OFFLINE", data.laserPresent and C.green or C.red)
  drawToggleRow(left, rowY + sv(126), "FLOW IN/OUT", data.energyFlowIn .. " / " .. data.energyFlowOut, C.text)
  drawToggleRow(left, rowY + sv(144), "TRANSFER CAP", data.transferCapText, C.text)
  drawToggleRow(left, rowY + sv(162), "MESSAGE", state.message, C.green)

  local refreshY = left.y + left.h - sv(56)
  local bw = left.w - ui.pad * 2
  drawButton("RELOAD_ASSETS", left.x + ui.pad, refreshY, bw, math.max(ui.buttonH, sv(36)), "[RELOAD ASSETS]", "cyan", true)

  drawPanel(right.x, right.y, right.w, right.h, "VISUAL CHECK")
  local innerX = right.x + ui.pad
  local innerY = right.y + sv(38)
  local innerW = right.w - ui.pad * 2
  local innerH = right.h - sv(46)
  gpu.filledRectangle(innerX, innerY, innerW, innerH, C.white)
  gpu.rectangle(innerX, innerY, innerW, innerH, C.border)
  drawImageStack(innerX + ui.smallPad, innerY + ui.smallPad, innerW - ui.smallPad * 2, innerH - ui.smallPad * 2, data)

  local infoBaseY = innerY + innerH - sv(74)
  drawText(innerX + ui.smallPad, infoBaseY, "LOGIC MODE", C.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoBaseY, data.logicMode, C.cyan, 1)
  drawText(innerX + ui.smallPad, infoBaseY + sv(18), "ACTIVE COOL", C.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoBaseY + sv(18), data.activeCooled and "ON" or "OFF", data.activeCooled and C.cyan or C.muted, 1)
  drawText(innerX + ui.smallPad, infoBaseY + sv(36), "ENV LOSS", C.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoBaseY + sv(36), data.environmentalLossText, C.orange, 1)
  drawText(innerX + ui.smallPad, infoBaseY + sv(54), "XFER LOSS", C.text, 1)
  drawTextRight(innerX + innerW - ui.smallPad, infoBaseY + sv(54), data.transferLossText, C.orange, 1)
end

local function readFusionData(force)
  return pollLiveData(force)
end

local function setPage(pageId)
  if not pageExists(pageId) then
    state.message = "unknown page: " .. tostring(pageId)
    return
  end

  state.page = pageId
  if pageId ~= "MAJ" then
    state.update.applyConfirmArmed = false
  end
  state.lastAction = "page:" .. pageId:lower()
  state.message = "page " .. pageId:lower()
end

local function handleAction(action)
  if string.sub(action, 1, 5) == "PAGE_" then
    setPage(string.sub(action, 6))
    return
  end

  state.lastAction = action

  if action == "AUTO" then
    -- UI-only toggle: kept for operator workflows, not bound to reactor logic.
    state.auto = not state.auto
    state.message = state.auto and "ui-state only: auto flag enabled" or "ui-state only: auto flag disabled"

  elseif action == "START" then
    local okFuel, msgFuel = openFuelFeed(true)
    local okPulse, msgPulse = pulseRelay("laserCharge", CONTROL.laserPulseSeconds)

    if okFuel or okPulse then
      state.message = "start: " .. firstLine(msgFuel or "") .. " | " .. firstLine(msgPulse or "")
    else
      state.message = "start blocked: relay sides not configured"
    end

  elseif action == "STOP" then
    local okFuel, msgFuel = openFuelFeed(false)
    if okFuel then
      state.message = "stop: " .. firstLine(msgFuel)
    else
      state.message = "stop blocked: relay sides not configured"
    end

  elseif action == "SCRAM" then
    local okFuel, msgFuel = openFuelFeed(false)
    local okLaser, msgLaser = setRelayState("laserCharge", false)
    if okFuel or okLaser then
      state.message = "scram: " .. firstLine(msgFuel or "") .. " | " .. firstLine(msgLaser or "")
    else
      state.message = "scram blocked: relay sides not configured"
    end

  elseif action == "FIRE_LASER" then
    local ok, msg = pulseRelay("laserCharge", CONTROL.laserPulseSeconds)
    state.message = ok and firstLine(msg) or ("laser blocked: " .. firstLine(msg))

  elseif action == "FILL_HOHLRAUM" then
    state.message = "manual hohlraum required"

  elseif action == "MANUAL_FUEL" then
    local target = not state.manualFuel
    local ok, msg = openFuelFeed(target)
    state.message = ok and firstLine(msg) or ("fuel blocked: " .. firstLine(msg))

  elseif action == "MAINTENANCE" then
    state.maintenance = not state.maintenance
    state.message = state.maintenance and "maintenance enabled" or "maintenance disabled"

  elseif action == "PROFILE_PREV" then
    -- UI-only selector: reserved for future ignition profile bindings.
    state.ignitionProfile = clamp(state.ignitionProfile - 1, 1, 5)
    state.message = "ui-state only: profile p" .. tostring(state.ignitionProfile)

  elseif action == "PROFILE_NEXT" then
    state.ignitionProfile = clamp(state.ignitionProfile + 1, 1, 5)
    state.message = "ui-state only: profile p" .. tostring(state.ignitionProfile)

  elseif action == "RELOAD_ASSETS" then
    tryLoadAssets()
    state.message = "assets reloaded"

  elseif action == "UPDATE_CHECK" then
    local ok, msg = performUpdateCheck("manual")
    state.message = ok and ("MAJ CHECK -> " .. tostring(state.update.remoteStatus) .. " (" .. firstLine(msg) .. ")") or ("MAJ CHECK ERROR -> " .. firstLine(msg))

  elseif action == "UPDATE_DOWNLOAD" then
    local ok, msg = performUpdateDownload()
    state.message = ok and ("MAJ DOWNLOAD -> " .. tostring(state.update.remoteStatus) .. " (" .. firstLine(msg) .. ")") or ("MAJ DOWNLOAD ERROR -> " .. firstLine(msg))

  elseif action == "UPDATE_APPLY" then
    local ok, msg = performUpdateApply()
    state.message = ok and ("MAJ APPLY -> " .. tostring(state.update.remoteStatus) .. " (" .. firstLine(msg) .. ")") or ("MAJ APPLY ERROR -> " .. firstLine(msg))

  elseif action == "UPDATE_ROLLBACK" then
    local ok, msg = performUpdateRollback()
    state.message = ok and ("MAJ ROLLBACK -> " .. tostring(state.update.remoteStatus) .. " (" .. firstLine(msg) .. ")") or ("MAJ ROLLBACK ERROR -> " .. firstLine(msg))

  elseif action == "UPDATE_RESTART" then
    local ok, msg = requestProgramRestart()
    state.message = ok and firstLine(msg) or ("restart failed: " .. firstLine(msg))

  else
    state.message = action
  end

  pollLiveData(true)
end

local function render()
  buildUI()
  buttons = {}

  if ui.tooSmall then
    gpu.fill(C.bg)
    local m = ui.margin
    drawPanel(m, m, ui.sw - m * 2, ui.sh - m * 2, "FUSION UI")
    drawTextCenter(m, m + 20, ui.sw - m * 2, "screen too small", C.orange, 1)
    drawTextCenter(m, m + 34, ui.sw - m * 2, ui.sw .. "x" .. ui.sh, C.muted, 1)
    gpu.sync()
    return
  end

  state.animTick = (state.animTick + 1) % 1000000
  local data = readFusionData(false)
  local L = ui.layout

  gpu.fill(C.bg)

  if ui.micro then
    drawMicroHeader(L.header, data)
    if state.page == "MAJ" then
      drawMicroMajPage(L.body, data)
    else
      drawMicroOverview(L.body, data)
    end
    gpu.sync()
    return
  end

  drawHeader(L.header, data)
  drawNav(L.nav)

  if state.page == "OVERVIEW" then
    drawOverviewPage(L.body, data)
  elseif state.page == "CONTROL" then
    drawControlPage(L.body, data)
  elseif state.page == "FUEL" then
    drawFuelPage(L.body, data)
  elseif state.page == "SYSTEM" then
    drawSystemPage(L.body, data)
  else
    drawUpdatePage(L.body)
  end

  drawFooter(L.footer, data)
  gpu.sync()
end

local function init()
  buildUI()
  tryLoadAssets()
  refreshLocalUpdateSnapshot()
  loadUpdateLogTail(12)
  if UPDATE_CFG.autoCheckOnStartup then
    local ok, msg = performUpdateCheck("startup")
    state.message = ok and ("maj startup: " .. firstLine(msg)) or ("maj startup failed: " .. firstLine(msg))
  end
  pollLiveData(true)
  render()
end

local function onTouch(x, y)
  for _, btn in pairs(buttons) do
    if hit(btn, x, y) then
      handleAction(btn.id)
      render()
      return
    end
  end
end

init()

local timer = os.startTimer(REFRESH_SECONDS)

while true do
  local event, p1, p2, p3 = os.pullEvent()

  if event == "timer" then
    if p1 == timer then
      render()
      timer = os.startTimer(REFRESH_SECONDS)
    elseif processPendingTimer(p1) then
      pollLiveData(true)
      render()
    end

  elseif event == "tm_monitor_touch" then
    onTouch(p2, p3)

  elseif event == "peripheral" or event == "peripheral_detach" then
    wrappedCache[p1] = nil
    pollLiveData(true)
    render()

  elseif event == "fusion_restart" then
    break

  elseif event == "key_up" and p1 == keys.t then
    break
  end
end

if state.restartRequested then
  local target = state.restartTarget or "start_menu_pages_live_v7.lua"
  if shell and type(shell.run) == "function" then
    shell.run(target)
  else
    os.reboot()
  end
end
