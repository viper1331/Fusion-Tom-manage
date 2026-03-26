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
  VALIDATING = "VALIDATING",
  DOWNLOAD_FAILED = "DOWNLOAD FAILED",
  READY_TO_APPLY = "READY TO APPLY",
  APPLYING = "APPLYING",
  APPLY_FAILED = "APPLY FAILED",
  ROLLBACK_DONE = "ROLLBACK DONE",
  ROLLBACK_FAILED = "ROLLBACK FAILED",
}

local INTEGRITY_STATUS = {
  PENDING = "INTEGRITY PENDING",
  OK = "INTEGRITY OK",
  HASH_FAILED = "HASH CHECK FAILED",
  STAGING_INVALID = "STAGING INVALID",
}

local UpdateVersion = assert(dofile("core/update/version.lua"))
local UpdateManifest = assert(dofile("core/update/manifest.lua"))
local UpdateClient = assert(dofile("core/update/client.lua"))
local UpdateApply = assert(dofile("core/update/apply.lua"))
local ResponsiveLayout = assert(dofile("ui/helpers/layout.lua"))
local NavigationView = assert(dofile("ui/components/navigation.lua"))
local UpdatePageView = assert(dofile("ui/pages/update_page.lua"))
local ControlPageView = assert(dofile("ui/pages/control_page.lua"))
local FuelPageView = assert(dofile("ui/pages/fuel_page.lua"))
local OverviewPageView = assert(dofile("ui/pages/overview_page.lua"))
local OverviewGraphicsView = assert(dofile("ui/pages/overview_graphics.lua"))
local TelemetryRuntime = assert(dofile("core/runtime/telemetry_runtime.lua"))
local ActionRuntime = assert(dofile("core/runtime/action_runtime.lua"))
local AppBootstrap = assert(dofile("core/app/bootstrap.lua"))
local AppRouter = assert(dofile("core/app/router.lua"))
local AppMainLoop = assert(dofile("core/app/main_loop.lua"))

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
    remoteBranch = UPDATE_CFG.branch,
    remoteCommit = "n/a",
    manifestUrl = "n/a",
    remoteStatus = UPDATE_STATUS.IDLE,
    statusDetail = "waiting for check",
    statusAt = "never",
    filesToUpdate = 0,
    downloadedFiles = 0,
    lastCheck = "never",
    lastApply = "never",
    lastDownload = "never",
    lastError = "none",
    integrityStatus = INTEGRITY_STATUS.PENDING,
    integrityDetail = "awaiting validation",
    lastCheckSummary = "not checked",
    logs = {},
    remoteManifest = nil,
    remoteManifestText = nil,
    remoteSource = nil,
    localManifest = nil,
    pendingFiles = {},
    downloaded = false,
    applyConfirmArmed = false,
    canRollback = false,
    downloadProgress = {
      phase = UPDATE_STATUS.IDLE,
      totalFiles = 0,
      completedFiles = 0,
      totalBytesExpected = 0,
      totalBytesCompleted = 0,
      currentFile = "-",
      currentFileSize = 0,
      percent = 0,
      note = "idle",
    },
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

-- Reactor/laser rendering and related animations are delegated
-- to ui/pages/overview_graphics.lua to keep this entrypoint stable.

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
  return ResponsiveLayout.splitVertical(r, topRatio, gap or ui.gap)
end

local function splitHorizontal(r, leftRatio, gap)
  return ResponsiveLayout.splitHorizontal(r, leftRatio, gap or ui.gap)
end

-- === Devices / telemetry ===
local function firstLine(s)
  s = tostring(s or "")
  local idx = string.find(s, "\n", 1, true)
  if idx then
    return string.sub(s, 1, idx - 1)
  end
  return s
end

local function nowMs()
  if os.epoch then
    return os.epoch("utc")
  end

  return math.floor((os.clock() or 0) * 1000)
end

local telemetryRuntime = TelemetryRuntime.create({
  devices = DEVICES,
  control = CONTROL,
  state = state,
  colors = C,
  clamp = clamp,
  round = round,
})

local function safeCall(name, method, ...)
  return telemetryRuntime.safeCall(name, method, ...)
end

local function pollLiveData(force)
  return telemetryRuntime.pollLiveData(force)
end

local function invalidateWrapped(name)
  telemetryRuntime.invalidateWrapped(name)
end

-- === Actions (device controls) ===
local actionRuntime = ActionRuntime.create({
  devices = DEVICES,
  control = CONTROL,
  state = state,
  safeCall = safeCall,
  firstLine = firstLine,
  clamp = clamp,
})

local function relaySideConfigured(key)
  return actionRuntime.relaySideConfigured(key)
end

local function setRelayState(key, enabled)
  return actionRuntime.setRelayState(key, enabled)
end

local function pulseRelay(key, duration)
  return actionRuntime.pulseRelay(key, duration)
end

local function openFuelFeed(enable)
  return actionRuntime.openFuelFeed(enable)
end

local function processPendingTimer(timerId)
  return actionRuntime.processPendingTimer(timerId)
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
  if status == UPDATE_STATUS.VALIDATING then
    return C.yellow
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

local function setDownloadProgress(progress)
  if type(state.update.downloadProgress) ~= "table" then
    state.update.downloadProgress = {}
  end

  local current = state.update.downloadProgress
  if type(progress) == "table" then
    if type(progress.phase) == "string" and progress.phase ~= "" then
      current.phase = progress.phase
    end
    if type(progress.totalFiles) == "number" then
      current.totalFiles = math.max(0, math.floor(progress.totalFiles))
    end
    if type(progress.completedFiles) == "number" then
      current.completedFiles = math.max(0, math.floor(progress.completedFiles))
    end
    if type(progress.totalBytesExpected) == "number" then
      current.totalBytesExpected = math.max(0, math.floor(progress.totalBytesExpected))
    end
    if type(progress.totalBytesCompleted) == "number" then
      current.totalBytesCompleted = math.max(0, math.floor(progress.totalBytesCompleted))
    end
    if type(progress.currentFile) == "string" and progress.currentFile ~= "" then
      current.currentFile = progress.currentFile
    end
    if type(progress.currentFileSize) == "number" then
      current.currentFileSize = math.max(0, math.floor(progress.currentFileSize))
    end
    if type(progress.note) == "string" and progress.note ~= "" then
      current.note = firstLine(progress.note)
    end
  end

  current.phase = current.phase or UPDATE_STATUS.IDLE
  current.totalFiles = math.max(0, math.floor(current.totalFiles or 0))
  current.completedFiles = math.max(0, math.floor(current.completedFiles or 0))
  current.totalBytesExpected = math.max(0, math.floor(current.totalBytesExpected or 0))
  current.totalBytesCompleted = math.max(0, math.floor(current.totalBytesCompleted or 0))
  current.currentFile = current.currentFile or "-"
  current.currentFileSize = math.max(0, math.floor(current.currentFileSize or 0))
  current.note = current.note or "idle"

  local percent = 0
  if current.totalBytesExpected > 0 then
    percent = (current.totalBytesCompleted * 100) / current.totalBytesExpected
  elseif current.totalFiles > 0 then
    percent = (current.completedFiles * 100) / current.totalFiles
  end

  current.percent = round(clamp(percent, 0, 100), 1)
end

local function resetDownloadProgress(phase, note)
  setDownloadProgress({
    phase = phase or UPDATE_STATUS.IDLE,
    totalFiles = 0,
    completedFiles = 0,
    totalBytesExpected = 0,
    totalBytesCompleted = 0,
    currentFile = "-",
    currentFileSize = 0,
    note = note or "idle",
  })
end

local function sumManifestEntrySizes(fileEntries)
  local total = 0
  for _, entry in ipairs(fileEntries or {}) do
    if type(entry) == "table" and type(entry.size) == "number" and entry.size >= 0 then
      total = total + math.max(0, math.floor(entry.size))
    end
  end
  return total
end

local function integrityStatusColor(status)
  if status == INTEGRITY_STATUS.OK then
    return C.green
  end
  if status == INTEGRITY_STATUS.HASH_FAILED or status == INTEGRITY_STATUS.STAGING_INVALID then
    return C.red
  end
  return C.orange
end

local function shortIntegrityStatus(status)
  if status == INTEGRITY_STATUS.OK then
    return "INT OK"
  end
  if status == INTEGRITY_STATUS.HASH_FAILED then
    return "INT FAIL"
  end
  if status == INTEGRITY_STATUS.STAGING_INVALID then
    return "STG BAD"
  end
  return "INT WAIT"
end

local function setIntegrityStatus(status, detail, logIt)
  state.update.integrityStatus = status or INTEGRITY_STATUS.PENDING
  if type(detail) == "string" and detail ~= "" then
    state.update.integrityDetail = firstLine(detail)
  end
  if logIt then
    appendUpdateLogLine("INTEGRITY " .. tostring(state.update.integrityStatus) .. " | " .. tostring(state.update.integrityDetail))
  end
end

local function setIntegrityFromError(rawErr)
  local raw = firstLine(rawErr or "")
  local lower = string.lower(raw)

  if string.find(lower, "hash mismatch", 1, true)
    or string.find(lower, "hash compute failed", 1, true)
  then
    setIntegrityStatus(INTEGRITY_STATUS.HASH_FAILED, raw, true)
    return
  end

  if string.find(lower, "staging", 1, true)
    or string.find(lower, "manifest hash", 1, true)
    or string.find(lower, "manifest size", 1, true)
    or string.find(lower, "manifest commit", 1, true)
    or string.find(lower, "manifest integrity", 1, true)
    or string.find(lower, "size mismatch in staging", 1, true)
    or string.find(lower, "unsupported hash algorithm", 1, true)
  then
    setIntegrityStatus(INTEGRITY_STATUS.STAGING_INVALID, raw, true)
  end
end

local function shortCommit(commit, length)
  local value = type(commit) == "string" and commit or ""
  if value == "" or value == "n/a" then
    return "n/a"
  end

  local size = math.max(4, math.floor(length or 8))
  if #value <= size then
    return value
  end
  return string.sub(value, 1, size)
end

local function writeTextFile(path, text)
  local fh = fs.open(path, "w")
  if not fh then
    return false, "cannot write file: " .. tostring(path)
  end
  fh.write(text or "")
  fh.close()
  return true
end

local function parseSizeMismatchDetail(raw)
  local path = string.match(raw, "size mismatch for ([^:]+)")
  local expected = string.match(raw, "expected=([0-9]+)")
  local received = string.match(raw, "received=([0-9]+)")
  local url = string.match(raw, "url=(%S+)")
  return path, expected, received, url
end

local function parseHashMismatchDetail(raw)
  local path = string.match(raw, "hash mismatch[^%w]+for ([^:]+)")
  local expected = string.match(raw, "expected=([0-9a-fA-F]+)")
  local received = string.match(raw, "received=([0-9a-fA-F]+)")
  local algo = string.match(raw, "algo=([%w_%-]+)")
  return path, expected, received, algo
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
  if string.find(lower, "url malformed", 1, true) then
    return step .. ": invalid download URL (path/source issue)."
  end
  if string.find(lower, "source incomplete", 1, true) then
    return step .. ": update source is incomplete (owner/repo/branch/commit)."
  end
  if string.find(lower, "manifest commit missing or invalid", 1, true) then
    return step .. ": manifest commit missing/invalid (expected 40-hex sha)."
  end
  if string.find(lower, "requires pinned commit", 1, true) then
    return step .. ": download source must support commit pinning ({commit} or {ref})."
  end
  if string.find(lower, "staging", 1, true) then
    return step .. ": staging is invalid or incomplete. Run DOWNLOAD again."
  end
  if string.find(lower, "hash mismatch", 1, true) then
    local path, expected, received, algo = parseHashMismatchDetail(raw)
    if path and expected and received then
      return step .. ": hash check failed on " .. tostring(path)
        .. " (" .. tostring(algo or "sha256") .. ", expected " .. tostring(expected) .. ", got " .. tostring(received) .. ")."
    end
    return step .. ": hash check failed."
  end
  if string.find(lower, "unsupported hash algorithm", 1, true) then
    return step .. ": unsupported hash algorithm in manifest/source."
  end
  if string.find(lower, "hash compute failed", 1, true) then
    return step .. ": unable to compute local file hash."
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
  setIntegrityFromError(err)
  if step == "DOWNLOAD" then
    setDownloadProgress({
      phase = UPDATE_STATUS.DOWNLOAD_FAILED,
      note = userMessage,
    })
  end
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
    commit = "",
    rawBaseUrl = tostring(UPDATE_CFG.rawBaseUrl or ""),
    defaultHashAlgo = "sha256",
  }

  if type(remoteManifest) == "table" then
    local resolvedCommit = UpdateManifest.resolveCommit(remoteManifest)
    if type(resolvedCommit) == "string" and resolvedCommit ~= "" then
      source.commit = resolvedCommit
    end
  end

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
    if source.commit == "" and type(remoteManifest.source.commit) == "string" and remoteManifest.source.commit ~= "" then
      source.commit = remoteManifest.source.commit
    end
  end

  if type(remoteManifest) == "table" and type(remoteManifest.integrity) == "table" and type(remoteManifest.integrity.defaultHashAlgo) == "string" and remoteManifest.integrity.defaultHashAlgo ~= "" then
    source.defaultHashAlgo = string.lower(remoteManifest.integrity.defaultHashAlgo)
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

local function rawBaseSupportsPinnedRef(rawBaseUrl)
  if type(rawBaseUrl) ~= "string" or rawBaseUrl == "" then
    return false
  end
  return string.find(rawBaseUrl, "{commit}", 1, true) ~= nil or string.find(rawBaseUrl, "{ref}", 1, true) ~= nil
end

local function validateUpdateSource(source, requireCommit)
  requireCommit = requireCommit == true

  if type(source.rawBaseUrl) == "string" and source.rawBaseUrl ~= "" then
    if requireCommit and not rawBaseSupportsPinnedRef(source.rawBaseUrl) then
      return false, "download source requires pinned commit in rawBaseUrl ({commit} or {ref})"
    end
    if requireCommit and not UpdateManifest.isValidCommit(source.commit) then
      return false, "manifest commit missing or invalid (expected 40-hex sha)"
    end
    return true
  end

  if source.owner == "" or source.repo == "" then
    return false, "update source incomplete (owner/repo)"
  end

  if requireCommit then
    if not UpdateManifest.isValidCommit(source.commit) then
      return false, "manifest commit missing or invalid (expected 40-hex sha)"
    end
    return true
  end

  if source.branch == "" then
    return false, "update source incomplete (branch)"
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
  resetDownloadProgress(UPDATE_STATUS.IDLE, "check reset")
  setIntegrityStatus(INTEGRITY_STATUS.PENDING, "manifest validation pending", false)
  state.update.remoteCommit = "n/a"
  state.update.remoteBranch = tostring(UPDATE_CFG.branch or "main")
  state.update.manifestUrl = "n/a"
  state.update.remoteManifestText = nil
  setUpdateStatus(UPDATE_STATUS.CHECKING, "fetching remote manifest", true)
  appendUpdateLogLine("CHECK start: reason=" .. tostring(reason or "manual"))
  appendUpdateLogLine("CHECK configured branch: " .. tostring(UPDATE_CFG.branch or "main"))
  refreshLocalUpdateSnapshot()

  if not UpdateClient.isHttpEnabled() then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, "http disabled in ComputerCraft")
  end

  local source = buildUpdateSource(nil)
  state.update.remoteBranch = tostring(source.branch ~= "" and source.branch or UPDATE_CFG.branch or "main")
  local sourceOk, sourceErr = validateUpdateSource(source, false)
  if not sourceOk then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, sourceErr)
  end

  local manifestPath = resolveManifestPath(nil)
  local manifestUrl = UpdateClient.buildRawUrl(source, manifestPath)
  state.update.manifestUrl = manifestUrl
  appendUpdateLogLine("CHECK manifest url: " .. tostring(manifestUrl))
  local remoteManifest, remoteManifestTextOrErr = UpdateManifest.readRemote(UpdateClient, manifestUrl)
  if not remoteManifest then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, remoteManifestTextOrErr)
  end
  local remoteManifestText = remoteManifestTextOrErr

  local remoteSource = buildUpdateSource(remoteManifest)
  local remoteSourceOk, remoteSourceErr = validateUpdateSource(remoteSource, false)
  if not remoteSourceOk then
    return failUpdateStep("CHECK", UPDATE_STATUS.CHECK_FAILED, remoteSourceErr)
  end

  local manifestReady, manifestCommitOrErr = UpdateManifest.validateDownloadManifest(remoteManifest)
  if manifestReady then
    remoteSource.commit = manifestCommitOrErr
    state.update.remoteCommit = manifestCommitOrErr
  else
    state.update.remoteCommit = "n/a"
    appendUpdateLogLine("CHECK warning: " .. tostring(manifestCommitOrErr))
  end

  state.update.remoteManifest = remoteManifest
  state.update.remoteManifestText = type(remoteManifestText) == "string" and remoteManifestText or nil
  state.update.remoteSource = remoteSource
  state.update.remoteVersion = tostring(remoteManifest.version or "n/a")
  state.update.channel = tostring(remoteManifest.channel or UPDATE_CFG.channel)
  state.update.remoteBranch = tostring(remoteSource.branch ~= "" and remoteSource.branch or state.update.remoteBranch)
  appendUpdateLogLine("CHECK mode: manifest via branch, files pinned by commit")
  appendUpdateLogLine("CHECK session branch=" .. tostring(state.update.remoteBranch) .. ", commit=" .. tostring(state.update.remoteCommit))
  appendUpdateLogLine("CHECK integrity mode: " .. tostring(remoteManifest.integrity and remoteManifest.integrity.mode or "size"))
  state.update.pendingFiles = UpdateManifest.computePendingFiles(state.update.localManifest, remoteManifest)
  state.update.filesToUpdate = #state.update.pendingFiles
  setDownloadProgress({
    phase = state.update.filesToUpdate > 0 and UPDATE_STATUS.UPDATE_AVAILABLE or UPDATE_STATUS.UP_TO_DATE,
    totalFiles = state.update.filesToUpdate,
    completedFiles = 0,
    totalBytesExpected = sumManifestEntrySizes(state.update.pendingFiles),
    totalBytesCompleted = 0,
    currentFile = "-",
    currentFileSize = 0,
    note = state.update.filesToUpdate > 0 and "update files pending download" or "no pending files",
  })
  state.update.lastError = manifestReady and "none" or formatUpdateUserError("CHECK", manifestCommitOrErr)
  setDownloadedState(false, 0)
  if manifestReady then
    if state.update.filesToUpdate > 0 then
      setIntegrityStatus(INTEGRITY_STATUS.PENDING, "manifest hash/size valid; download validation pending", true)
    else
      setIntegrityStatus(INTEGRITY_STATUS.OK, "manifest hash/size valid (up to date)", true)
    end
  else
    setIntegrityStatus(INTEGRITY_STATUS.STAGING_INVALID, firstLine(manifestCommitOrErr), true)
  end

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

  if status == UPDATE_STATUS.UPDATE_AVAILABLE and not manifestReady then
    state.update.lastCheckSummary = "update available (download blocked)"
  else
    state.update.lastCheckSummary = status == UPDATE_STATUS.UPDATE_AVAILABLE and "update available" or "up to date"
  end

  local detail = "local=" .. tostring(state.update.localVersion)
    .. " remote=" .. tostring(state.update.remoteVersion)
    .. " pending=" .. tostring(state.update.filesToUpdate)
    .. " commit=" .. tostring(shortCommit(state.update.remoteCommit, 8))
  if not manifestReady then
    detail = detail .. " (download blocked)"
  end

  setUpdateStatus(status, detail, true)
  appendUpdateLogLine("CHECK done: local=" .. tostring(state.update.localVersion) .. ", remote=" .. tostring(state.update.remoteVersion) .. ", files=" .. tostring(state.update.filesToUpdate) .. ", commit=" .. tostring(state.update.remoteCommit))
  return true, state.update.lastCheckSummary
end

local function performUpdateDownload()
  state.update.applyConfirmArmed = false
  setIntegrityStatus(INTEGRITY_STATUS.PENDING, "download + hash validation in progress", true)
  setUpdateStatus(UPDATE_STATUS.DOWNLOADING, "preparing staging directory", true)
  resetDownloadProgress(UPDATE_STATUS.DOWNLOADING, "preparing staging directory")
  appendUpdateLogLine("DOWNLOAD start")

  if not state.update.remoteManifest then
    local ok, err = performUpdateCheck("download precheck")
    if not ok then
      return false, err
    end
  end

  local remoteManifest = state.update.remoteManifest
  local manifestReady, manifestCommitOrErr = UpdateManifest.validateDownloadManifest(remoteManifest)
  if not manifestReady then
    clearStagingWithLog("manifest invalid for download")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, manifestCommitOrErr)
  end

  local manifestCommit = manifestCommitOrErr
  state.update.remoteCommit = manifestCommit
  local remoteSource = state.update.remoteSource or buildUpdateSource(remoteManifest)
  remoteSource.commit = manifestCommit
  state.update.remoteSource = remoteSource
  state.update.remoteBranch = tostring(remoteSource.branch ~= "" and remoteSource.branch or UPDATE_CFG.branch or "main")
  appendUpdateLogLine("DOWNLOAD mode: manifest branch=" .. tostring(state.update.remoteBranch) .. ", files commit=" .. tostring(manifestCommit))

  local sourceOk, sourceErr = validateUpdateSource(remoteSource, true)
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
  local plannedFiles = remoteManifest.files or {}
  local totalFiles = #plannedFiles
  local totalExpectedBytes = sumManifestEntrySizes(plannedFiles)
  setDownloadProgress({
    phase = UPDATE_STATUS.DOWNLOADING,
    totalFiles = totalFiles,
    completedFiles = 0,
    totalBytesExpected = totalExpectedBytes,
    totalBytesCompleted = 0,
    currentFile = "-",
    currentFileSize = 0,
    note = "download started",
  })
  appendUpdateLogLine("DOWNLOAD files planned: " .. tostring(totalFiles))
  appendUpdateLogLine("DOWNLOAD expected bytes: " .. tostring(totalExpectedBytes))

  local function onDownloadProgress(event)
    if type(event) ~= "table" then
      return
    end

    local phase = type(event.phase) == "string" and event.phase ~= "" and event.phase or UPDATE_STATUS.DOWNLOADING
    local totalFilesEvent = type(event.totalFiles) == "number" and event.totalFiles or state.update.downloadProgress.totalFiles
    local completedFilesEvent = type(event.completedFiles) == "number" and event.completedFiles or state.update.downloadProgress.completedFiles
    local totalBytesExpectedEvent = type(event.totalBytesExpected) == "number" and event.totalBytesExpected or state.update.downloadProgress.totalBytesExpected
    local totalBytesCompletedEvent = type(event.totalBytesCompleted) == "number" and event.totalBytesCompleted or state.update.downloadProgress.totalBytesCompleted
    local currentPath = type(event.path) == "string" and event.path ~= "" and event.path or state.update.downloadProgress.currentFile
    local currentFileSize = 0
    if type(event.expectedSize) == "number" then
      currentFileSize = math.max(0, math.floor(event.expectedSize))
    elseif type(event.receivedSize) == "number" then
      currentFileSize = math.max(0, math.floor(event.receivedSize))
    else
      currentFileSize = state.update.downloadProgress.currentFileSize or 0
    end

    setDownloadProgress({
      phase = phase,
      totalFiles = totalFilesEvent,
      completedFiles = completedFilesEvent,
      totalBytesExpected = totalBytesExpectedEvent,
      totalBytesCompleted = totalBytesCompletedEvent,
      currentFile = currentPath,
      currentFileSize = currentFileSize,
      note = type(event.event) == "string" and event.event or state.update.downloadProgress.note,
    })

    local percent = math.floor((state.update.downloadProgress.percent or 0) + 0.5)
    local progressSummary = tostring(state.update.downloadProgress.completedFiles or 0) .. "/" .. tostring(state.update.downloadProgress.totalFiles or 0)
      .. " files, " .. tostring(state.update.downloadProgress.totalBytesCompleted or 0) .. "/" .. tostring(state.update.downloadProgress.totalBytesExpected or 0)
      .. " bytes (" .. tostring(percent) .. "%)"

    if event.event == "file_start" then
      setUpdateStatus(UPDATE_STATUS.DOWNLOADING, "downloading " .. tostring(currentPath) .. " (" .. progressSummary .. ")", false)
      appendUpdateLogLine("DOWNLOAD file start: " .. tostring(currentPath) .. " expected=" .. tostring(currentFileSize) .. "B url=" .. tostring(event.url or "n/a"))
    elseif event.event == "file_validating" then
      setUpdateStatus(UPDATE_STATUS.VALIDATING, "validating " .. tostring(currentPath), false)
      appendUpdateLogLine("DOWNLOAD file validating: " .. tostring(currentPath) .. " expected=" .. tostring(event.expectedSize or "?") .. "B received=" .. tostring(event.receivedSize or "?") .. "B")
    elseif event.event == "file_done" then
      setUpdateStatus(UPDATE_STATUS.DOWNLOADING, "downloaded " .. tostring(progressSummary), false)
      appendUpdateLogLine("DOWNLOAD progress: " .. tostring(progressSummary))
    elseif event.event == "complete" then
      setUpdateStatus(UPDATE_STATUS.VALIDATING, "download complete, validating staging", false)
      setDownloadProgress({
        phase = UPDATE_STATUS.VALIDATING,
        note = "download complete, validating staging",
      })
      appendUpdateLogLine("DOWNLOAD transfer complete: " .. tostring(progressSummary))
    end
  end

  local downloaded, downloadErr = UpdateClient.downloadFiles(remoteSource, plannedFiles, UPDATE_TEMP_DIR, appendUpdateLogLine, onDownloadProgress)
  if not downloaded then
    clearStagingWithLog("download failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, downloadErr)
  end

  setUpdateStatus(UPDATE_STATUS.VALIDATING, "finalizing staging metadata", true)
  setDownloadProgress({
    phase = UPDATE_STATUS.VALIDATING,
    note = "finalizing staging metadata",
  })

  local stagingContext = {
    remoteVersion = tostring(state.update.remoteVersion or "n/a"),
    manifestVersion = tostring(remoteManifest.version or "n/a"),
    remoteCommit = tostring(manifestCommit or ""),
    channel = tostring(state.update.channel or "stable"),
    checkedAt = tostring(state.update.lastCheck or "never"),
  }

  local marked, markedErr = UpdateApply.markStagingReady(remoteManifest.files, UPDATE_TEMP_DIR, stagingContext)
  if not marked then
    clearStagingWithLog("staging meta failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, markedErr)
  end

  local valid, validErr = UpdateApply.validateStaging(remoteManifest.files, UPDATE_TEMP_DIR, stagingContext, appendUpdateLogLine, "download validation")
  if not valid then
    clearStagingWithLog("staging validation failure")
    setDownloadedState(false, 0)
    return failUpdateStep("DOWNLOAD", UPDATE_STATUS.DOWNLOAD_FAILED, validErr)
  end

  setIntegrityStatus(INTEGRITY_STATUS.OK, "staging integrity validated for commit " .. tostring(shortCommit(manifestCommit, 8)), true)
  setDownloadedState(true, #downloaded)
  setDownloadProgress({
    phase = UPDATE_STATUS.READY_TO_APPLY,
    completedFiles = #downloaded,
    totalFiles = totalFiles,
    totalBytesCompleted = state.update.downloadProgress.totalBytesExpected,
    currentFile = "-",
    currentFileSize = 0,
    note = "ready to apply",
  })
  state.update.lastDownload = nowText()
  state.update.lastError = "none"
  state.update.lastCheckSummary = "ready to apply"
  setUpdateStatus(UPDATE_STATUS.READY_TO_APPLY, "downloaded files=" .. tostring(#downloaded) .. " commit=" .. tostring(shortCommit(manifestCommit, 8)), true)
  appendUpdateLogLine("DOWNLOAD done: files=" .. tostring(#downloaded) .. ", commit=" .. tostring(manifestCommit))

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
  setIntegrityStatus(INTEGRITY_STATUS.PENDING, "pre-apply integrity validation in progress", true)
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
    remoteCommit = tostring(state.update.remoteCommit or ""),
  }

  local stageOk, stageErr = UpdateApply.validateStaging(remoteManifest.files, UPDATE_TEMP_DIR, expectedContext, appendUpdateLogLine, "pre-apply validation")
  if not stageOk then
    clearStagingWithLog("apply refused invalid staging")
    setDownloadedState(false, 0)
    return failUpdateStep("APPLY", UPDATE_STATUS.APPLY_FAILED, stageErr)
  end
  setIntegrityStatus(INTEGRITY_STATUS.OK, "pre-apply staging integrity validated", true)

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
    setIntegrityFromError(applyErr)
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
  if type(state.update.remoteManifestText) == "string" and state.update.remoteManifestText ~= "" then
    local manifestWriteOk, manifestWriteErr = writeTextFile(UPDATE_MANIFEST_FILE, state.update.remoteManifestText)
    if manifestWriteOk then
      appendUpdateLogLine("APPLY refreshed local manifest from checked branch source")
    else
      appendUpdateLogLine("APPLY warning: manifest refresh failed: " .. tostring(manifestWriteErr))
    end
  end

  state.update.lastApply = nowText()
  setDownloadedState(false, 0)
  state.update.pendingFiles = {}
  state.update.filesToUpdate = 0
  state.update.lastError = "none"
  state.update.lastCheckSummary = "up to date"
  refreshLocalUpdateSnapshot()
  setIntegrityStatus(INTEGRITY_STATUS.OK, "applied with validated staging integrity", true)
  setUpdateStatus(UPDATE_STATUS.UP_TO_DATE, "apply completed successfully", true)
  appendUpdateLogLine("APPLY success: local version=" .. tostring(state.update.localVersion) .. ", commit=" .. tostring(state.update.remoteCommit))

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
  setIntegrityStatus(INTEGRITY_STATUS.PENDING, "rollback restored backup; run CHECK", true)
  setUpdateStatus(UPDATE_STATUS.ROLLBACK_DONE, "backup restored", true)
  appendUpdateLogLine("ROLLBACK success: local version=" .. tostring(state.update.localVersion))

  return true, "rollback done"
end

local function requestProgramRestart()
  local entrypoint = "start.lua"
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
  NavigationView.draw({
    rect = r,
    ui = ui,
    pages = PAGES,
    activePage = state.page,
    drawPanel = drawPanel,
    drawButton = drawButton,
  })
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
  UpdatePageView.drawMicro({
    rect = r,
    data = data,
    ui = ui,
    colors = C,
    updateState = state.update,
    drawPanel = drawPanel,
    drawText = drawText,
    drawTextRight = drawTextRight,
    drawButton = drawButton,
    sv = sv,
    shortCommit = shortCommit,
    updateStatusColor = updateStatusColor,
    shortIntegrityStatus = shortIntegrityStatus,
    integrityStatusColor = integrityStatusColor,
  })
end

local function drawUpdatePage(r)
  UpdatePageView.draw({
    rect = r,
    ui = ui,
    colors = C,
    updateState = state.update,
    requireConfirmApply = UPDATE_CFG.requireConfirmApply,
    integrityStatusOk = INTEGRITY_STATUS.OK,
    splitVertical = splitVertical,
    splitHorizontal = splitHorizontal,
    drawPanel = drawPanel,
    drawToggleRow = drawToggleRow,
    drawText = drawText,
    drawGauge = drawGauge,
    drawButton = drawButton,
    sv = sv,
    firstLine = firstLine,
    shortCommit = shortCommit,
    updateStatusColor = updateStatusColor,
    integrityStatusColor = integrityStatusColor,
  })
end

local function drawImageStack(slotX, slotY, slotW, slotH, data, forcedLayout)
  OverviewGraphicsView.drawImageStack({
    slotX = slotX,
    slotY = slotY,
    slotW = slotW,
    slotH = slotH,
    data = data,
    forcedLayout = forcedLayout,
    control = CONTROL,
    ui = ui,
    colors = C,
    state = state,
    gpu = gpu,
    chooseStackLayout = chooseStackLayout,
    drawTextCenter = drawTextCenter,
    textPixelHeight = textPixelHeight,
  })
end

local function drawOverviewReactorLaserScene(slotX, slotY, slotW, slotH, data, layout)
  -- Stable wrapper kept in entrypoint to avoid breaking external expectations.
  drawImageStack(slotX, slotY, slotW, slotH, data, layout)
end

local function drawOverviewPage(r, data)
  OverviewPageView.draw({
    rect = r,
    data = data,
    ui = ui,
    colors = C,
    control = CONTROL,
    gpu = gpu,
    splitVertical = splitVertical,
    splitHorizontal = splitHorizontal,
    chooseOverviewStackLayout = chooseOverviewStackLayout,
    drawPanel = drawPanel,
    drawGauge = drawGauge,
    drawToggleRow = drawToggleRow,
    drawTextCenter = drawTextCenter,
    chooseStateColor = chooseStateColor,
    drawReactorLaserScene = drawOverviewReactorLaserScene,
    sv = sv,
    clamp = clamp,
    round = round,
    textPixelHeight = textPixelHeight,
  })
end

local function drawControlPage(r, data)
  ControlPageView.draw({
    rect = r,
    data = data,
    ui = ui,
    colors = C,
    state = state,
    splitVertical = splitVertical,
    splitHorizontal = splitHorizontal,
    drawPanel = drawPanel,
    drawButton = drawButton,
    drawToggleRow = drawToggleRow,
    chooseStateColor = chooseStateColor,
    relaySideConfigured = relaySideConfigured,
    sv = sv,
  })
end

local function drawFuelPage(r, data)
  FuelPageView.draw({
    rect = r,
    data = data,
    ui = ui,
    colors = C,
    state = state,
    splitVertical = splitVertical,
    drawPanel = drawPanel,
    drawGauge = drawGauge,
    drawToggleRow = drawToggleRow,
    drawButton = drawButton,
    sv = sv,
  })
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

local appWiring = nil

local function setPage(pageId)
  AppRouter.setPage(appWiring.router, pageId)
end

local function handleAction(action)
  AppRouter.handleAction(appWiring.router, action)
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
  AppRouter.drawCurrentPage(appWiring.router, L.body, data)

  drawFooter(L.footer, data)
  gpu.sync()
end

appWiring = AppBootstrap.buildWiring({
  state = state,
  updateCfg = UPDATE_CFG,
  refreshSeconds = REFRESH_SECONDS,
  pageExists = pageExists,
  executeRuntimeCommand = actionRuntime.executeCommand,
  buildUI = buildUI,
  tryLoadAssets = tryLoadAssets,
  refreshLocalUpdateSnapshot = refreshLocalUpdateSnapshot,
  loadUpdateLogTail = loadUpdateLogTail,
  performUpdateCheck = performUpdateCheck,
  performUpdateDownload = performUpdateDownload,
  performUpdateApply = performUpdateApply,
  performUpdateRollback = performUpdateRollback,
  requestProgramRestart = requestProgramRestart,
  pollLiveData = pollLiveData,
  firstLine = firstLine,
  processPendingTimer = processPendingTimer,
  invalidateWrapped = invalidateWrapped,
  hit = hit,
  handleAction = handleAction,
  render = render,
  getButtons = function()
    return buttons
  end,
  drawOverviewPage = drawOverviewPage,
  drawControlPage = drawControlPage,
  drawFuelPage = drawFuelPage,
  drawSystemPage = drawSystemPage,
  drawUpdatePage = drawUpdatePage,
})

local function init()
  AppBootstrap.initialize(appWiring.startup)
end

local function runMainLoop()
  AppMainLoop.run(appWiring.loop)
end

init()
runMainLoop()

if state.restartRequested then
  local target = state.restartTarget or "start.lua"
  if shell and type(shell.run) == "function" then
    shell.run(target)
  else
    os.reboot()
  end
end
