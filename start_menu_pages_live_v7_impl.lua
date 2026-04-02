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
    integrityMode = "size+hash",
    requireConfirmApply = true,
    autoCheckOnStartup = false,
  },
  validation = {
    overviewSource = "terrain",
    overviewScenario = "offline",
  },
  logging = {
    level = "INFO",
    files = {
      runtime = "ui_runtime.log",
      update = "update.log",
      rescue = "/rescue_update.log",
    },
    telemetrySnapshotSeconds = 10,
    loopEventDebug = false,
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

local function normalizeIntegrityMode(value)
  local raw = string.lower(nonEmptyString(value) or "")
  if raw == "size-only" or raw == "size_only" or raw == "sizeonly" then
    return "size-only"
  end
  return "size+hash"
end

local function normalizeLogLevel(value)
  local raw = string.upper(nonEmptyString(value) or "INFO")
  if raw == "DEBUG" or raw == "INFO" or raw == "WARN" or raw == "ERROR" then
    return raw
  end
  return "INFO"
end

local OverviewValidation = assert(dofile("core/runtime/overview_validation.lua"))

local function normalizeOverviewValidationSource(value)
  return OverviewValidation.normalizeSource(value)
end

local function normalizeOverviewValidationScenario(value)
  return OverviewValidation.normalizeScenario(value)
end

local GPU_MODE = DEFAULTS.runtime.gpuMode
local REFRESH_SECONDS = DEFAULTS.runtime.refreshSeconds
local AssetRegistry = assert(dofile("ui/helpers/asset_registry.lua"))
local ASSET_REACTOR_VARIANTS = {}
local ASSET_LASER_MODULE_VARIANTS = {}

-- === Runtime config ===
local DEVICES = deepCopy(DEFAULTS.devices)
local CONTROL = deepCopy(DEFAULTS.control)
local UPDATE_CFG = deepCopy(DEFAULTS.update)
local VALIDATION_CFG = deepCopy(DEFAULTS.validation)
local LOGGING_CFG = deepCopy(DEFAULTS.logging)
local START_PAGE = DEFAULTS.ui.startPage
local UPDATE_VERSION_FILE = "fusion.version"
local UPDATE_MANIFEST_FILE = "fusion.manifest.json"
local UPDATE_LOG_FILE = LOGGING_CFG.files.update
local UI_RUNTIME_LOG_FILE = LOGGING_CFG.files.runtime
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
  VALIDATION_FAILED = "VALIDATION FAILED",
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
local GpuSafe = assert(dofile("ui/helpers/gpu_safe.lua"))
local OverviewSceneRuntime = assert(dofile("ui/helpers/overview_scene_runtime.lua"))
local Views = {
  Navigation = assert(dofile("ui/components/navigation.lua")),
  Update = assert(dofile("ui/pages/update_page.lua")),
  Control = assert(dofile("ui/pages/control_page.lua")),
  Fuel = assert(dofile("ui/pages/fuel_page.lua")),
  System = assert(dofile("ui/pages/system_page.lua")),
}
local OverviewCalibration = assert(dofile("ui/pages/overview_calibration.lua"))
Views.Overview = assert(dofile("ui/pages/overview_page.lua"))
Views.OverviewGraphics = assert(dofile("ui/pages/overview_graphics.lua"))
local TelemetryRuntime = assert(dofile("core/runtime/telemetry_runtime.lua"))
local ActionRuntime = assert(dofile("core/runtime/action_runtime.lua"))
local UpdateRuntime = assert(dofile("core/runtime/update_runtime.lua"))
local AppBootstrap = assert(dofile("core/app/bootstrap.lua"))
local AppRouter = assert(dofile("core/app/router.lua"))
local AppMainLoop = assert(dofile("core/app/main_loop.lua"))
local LoggerModule = assert(dofile("core/logging/logger.lua"))

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
    if type(cfg.update.integrityMode) == "string" and cfg.update.integrityMode ~= "" then
      UPDATE_CFG.integrityMode = normalizeIntegrityMode(cfg.update.integrityMode)
    end
    if type(cfg.update.requireConfirmApply) == "boolean" then
      UPDATE_CFG.requireConfirmApply = cfg.update.requireConfirmApply
    end
    if type(cfg.update.autoCheckOnStartup) == "boolean" then
      UPDATE_CFG.autoCheckOnStartup = cfg.update.autoCheckOnStartup
    end
  end

  if type(cfg.validation) == "table" then
    if type(cfg.validation.overviewSource) == "string" and cfg.validation.overviewSource ~= "" then
      VALIDATION_CFG.overviewSource = normalizeOverviewValidationSource(cfg.validation.overviewSource)
    end
    if type(cfg.validation.overviewScenario) == "string" and cfg.validation.overviewScenario ~= "" then
      VALIDATION_CFG.overviewScenario = normalizeOverviewValidationScenario(cfg.validation.overviewScenario)
    end
  end

  if type(cfg.logging) == "table" then
    if cfg.logging.level ~= nil then
      LOGGING_CFG.level = normalizeLogLevel(cfg.logging.level)
    end
    if type(cfg.logging.telemetrySnapshotSeconds) == "number" then
      LOGGING_CFG.telemetrySnapshotSeconds = math.max(1, math.floor(cfg.logging.telemetrySnapshotSeconds))
    end
    if type(cfg.logging.loopEventDebug) == "boolean" then
      LOGGING_CFG.loopEventDebug = cfg.logging.loopEventDebug
    end
    if type(cfg.logging.files) == "table" then
      if nonEmptyString(cfg.logging.files.runtime) then
        LOGGING_CFG.files.runtime = cfg.logging.files.runtime
      end
      if nonEmptyString(cfg.logging.files.update) then
        LOGGING_CFG.files.update = cfg.logging.files.update
      end
      if nonEmptyString(cfg.logging.files.rescue) then
        LOGGING_CFG.files.rescue = cfg.logging.files.rescue
      end
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
UPDATE_CFG.integrityMode = normalizeIntegrityMode(UPDATE_CFG.integrityMode)
VALIDATION_CFG.overviewSource = normalizeOverviewValidationSource(VALIDATION_CFG.overviewSource)
VALIDATION_CFG.overviewScenario = normalizeOverviewValidationScenario(VALIDATION_CFG.overviewScenario)
LOGGING_CFG.level = normalizeLogLevel(LOGGING_CFG.level)
UPDATE_LOG_FILE = nonEmptyString(LOGGING_CFG.files.update) or UPDATE_LOG_FILE
UI_RUNTIME_LOG_FILE = nonEmptyString(LOGGING_CFG.files.runtime) or UI_RUNTIME_LOG_FILE

local appLogger = LoggerModule.create({
  level = LOGGING_CFG.level,
  defaultSink = "runtime",
  files = {
    runtime = UI_RUNTIME_LOG_FILE,
    update = UPDATE_LOG_FILE,
    rescue = nonEmptyString(LOGGING_CFG.files.rescue) or DEFAULTS.logging.files.rescue,
  },
})

local function logWithLevel(level, category, message, context, sink)
  if not appLogger then
    return false
  end

  local method = string.lower(tostring(level or "INFO"))
  local fn = appLogger[method]
  if type(fn) == "function" then
    return fn(category, message, context, sink or "runtime")
  end

  return appLogger.info(category, message, context, sink or "runtime")
end

local function initGpuFromConfig()
  local configuredGpuName = resolveConfiguredGpuName(DEVICES.gpu)
  logWithLevel("INFO", "BOOT", "gpu init attempt", {
    configured = tostring(configuredGpuName),
    fallback = tostring(DEFAULTS.devices.gpu),
  })
  local wrapped = peripheral.wrap(configuredGpuName)
  if wrapped then
    logWithLevel("INFO", "BOOT", "gpu init success", {
      device = tostring(configuredGpuName),
      mode = tostring(GPU_MODE),
    })
    return wrapped, configuredGpuName
  end

  local fallbackGpuName = DEFAULTS.devices.gpu
  if configuredGpuName ~= fallbackGpuName then
    logWithLevel("WARN", "BOOT", "gpu init fallback attempt", {
      configured = tostring(configuredGpuName),
      fallback = tostring(fallbackGpuName),
    })
    wrapped = peripheral.wrap(fallbackGpuName)
    if wrapped then
      logWithLevel("INFO", "BOOT", "gpu init fallback success", {
        device = tostring(fallbackGpuName),
      })
      return wrapped, fallbackGpuName
    end
  end

  logWithLevel("ERROR", "BOOT", "gpu init failed", {
    configured = tostring(configuredGpuName),
    fallback = tostring(fallbackGpuName),
  })
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
  visual = {
    effectLevel = "normal",
    vramFallback = false,
    screenSize = "n/a",
    reactorAsset = "none",
    moduleAsset = "none",
    sceneMode = "none",
    lastAssetReason = "startup",
    validationSource = VALIDATION_CFG.overviewSource,
    validationScenario = VALIDATION_CFG.overviewScenario,
  },

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
    integrityMode = UPDATE_CFG.integrityMode,
    hashValidationRequired = true,
    hashValidated = false,
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
    validationProgress = {
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

state.update.integrityMode = normalizeIntegrityMode(state.update.integrityMode or UPDATE_CFG.integrityMode)
state.update.hashValidationRequired = state.update.integrityMode ~= "size-only"
state.update.hashValidated = not state.update.hashValidationRequired

local images = {
  reactor = nil,
  reactorVariants = {},
  laserModule = nil,
  laserModuleVariants = {},
}

local buttons = {}
local ui = nil
local displayState = {
  lastWidth = -1,
  lastHeight = -1,
  invalidScreen = false,
  lastInvalidScreenKey = nil,
  lastInvalidViewportKey = nil,
  lastInvalidRenderKey = nil,
  lastScreenClassKey = nil,
  lastSurvivalModeKey = nil,
  lastPanelCollapseKey = nil,
}

local MIN_VALID_SCREEN_W = 32
local MIN_VALID_SCREEN_H = 32
local MIN_VALID_VIEWPORT_W = 16
local MIN_VALID_VIEWPORT_H = 16

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

local function runtimeNowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  if os.epoch then
    return tostring(os.epoch("utc"))
  end
  return tostring(math.floor((os.clock() or 0) * 1000))
end

local function inferRuntimeLogCategory(messageText)
  local lower = string.lower(tostring(messageText or ""))
  if string.find(lower, "overview", 1, true) ~= nil
    or string.find(lower, "callout", 1, true) ~= nil
    or string.find(lower, "annotation", 1, true) ~= nil then
    return "OVERVIEW"
  end
  if string.find(lower, "asset", 1, true) ~= nil
    or string.find(lower, "variant", 1, true) ~= nil
    or string.find(lower, "scene", 1, true) ~= nil then
    return "ASSETS"
  end
  if string.find(lower, "effect", 1, true) ~= nil
    or string.find(lower, "degradation", 1, true) ~= nil
    or string.find(lower, "animation", 1, true) ~= nil
    or string.find(lower, "flux", 1, true) ~= nil then
    return "ANIMATIONS"
  end
  if string.find(lower, "clamp", 1, true) ~= nil
    or string.find(lower, "clipped", 1, true) ~= nil
    or string.find(lower, "boundary", 1, true) ~= nil
    or string.find(lower, "gpu", 1, true) ~= nil then
    return "GPU"
  end
  if string.find(lower, "resize", 1, true) ~= nil
    or string.find(lower, "screen size", 1, true) ~= nil then
    return "INPUT"
  end
  return "BOOT"
end

local function inferRuntimeLogLevel(messageText)
  local lower = string.lower(tostring(messageText or ""))
  if string.find(lower, " failed", 1, true) ~= nil
    or string.find(lower, "error", 1, true) ~= nil
    or string.find(lower, "out of", 1, true) ~= nil then
    return "ERROR"
  end
  if string.find(lower, "warn", 1, true) ~= nil
    or string.find(lower, "fallback", 1, true) ~= nil
    or string.find(lower, "clamped", 1, true) ~= nil then
    return "WARN"
  end
  return "INFO"
end

local function appendUiRuntimeLog(message, options)
  local messageText = message
  local context = nil
  local level = nil
  local category = nil

  if type(message) == "table" then
    messageText = message.message or message.text or message.msg or "event"
    context = type(message.context) == "table" and message.context or nil
    level = message.level
    category = message.category
  end
  if type(options) == "table" then
    if type(options.context) == "table" then
      context = options.context
    end
    if options.level ~= nil then
      level = options.level
    end
    if options.category ~= nil then
      category = options.category
    end
  end

  local finalMessage = tostring(messageText or "event")
  local finalCategory = tostring(category or inferRuntimeLogCategory(finalMessage))
  local finalLevel = normalizeLogLevel(level or inferRuntimeLogLevel(finalMessage))

  local ok = logWithLevel(finalLevel, finalCategory, finalMessage, context, "runtime")
  if not ok then
    local entry = "[" .. runtimeNowText() .. "] [" .. finalLevel .. "] [" .. finalCategory .. "] " .. finalMessage
    local fh = fs.open(UI_RUNTIME_LOG_FILE, "a")
    if fh then
      fh.writeLine(entry)
      fh.close()
    end
  end
end

do
  local registry = AssetRegistry.resolveRuntimeRegistry({
    fs = fs,
    log = appendUiRuntimeLog,
  })
  ASSET_REACTOR_VARIANTS = registry.reactorVariants or {}
  ASSET_LASER_MODULE_VARIANTS = registry.laserModuleVariants or {}
end

local overviewSceneRuntime = OverviewSceneRuntime.create({
  fs = fs,
  gpu = gpu,
  colors = C,
  state = state,
  images = images,
  control = CONTROL,
  overviewCalibration = OverviewCalibration,
  appendUiRuntimeLog = appendUiRuntimeLog,
  assetReactorVariants = ASSET_REACTOR_VARIANTS,
  assetLaserModuleVariants = ASSET_LASER_MODULE_VARIANTS,
  displayState = displayState,
  minValidScreenW = MIN_VALID_SCREEN_W,
  minValidScreenH = MIN_VALID_SCREEN_H,
  minValidViewportW = MIN_VALID_VIEWPORT_W,
  minValidViewportH = MIN_VALID_VIEWPORT_H,
  sv = sv,
  getUi = function()
    return ui
  end,
})

local screenSizeRejectReason = overviewSceneRuntime.screenSizeRejectReason
local refreshVisualEffectLevel = overviewSceneRuntime.refreshVisualEffectLevel
local tryLoadAssets = overviewSceneRuntime.tryLoadAssets
local getFallbackReactorVariant = overviewSceneRuntime.getFallbackReactorVariant
local getFallbackLaserModuleVariant = overviewSceneRuntime.getFallbackLaserModuleVariant
local chooseStackLayout = overviewSceneRuntime.chooseStackLayout
local chooseOverviewStackLayout = overviewSceneRuntime.chooseOverviewStackLayout

local function chooseStateColor(data)
  if data.status == "SCRAM" then return C.red end
  if data.status == "WARNING" then return C.orange end
  if data.status == "STABLE" then return C.green end
  return C.muted
end

local function drawText(x, y, text, color, size)
  return GpuSafe.drawText(
    { gpu = gpu, ui = ui, logger = appLogger, logCategory = "GPU" },
    x,
    y,
    text,
    color or C.text,
    C.blackA0,
    size or 1,
    0
  )
end

local function drawTextRight(xRight, y, text, color, size)
  return GpuSafe.drawTextRight(
    { gpu = gpu, ui = ui, logger = appLogger, logCategory = "GPU" },
    xRight,
    y,
    text,
    color or C.text,
    C.blackA0,
    size or 1,
    0
  )
end

local function drawTextCenter(x, y, w, text, color, size)
  if w <= 0 then
    return false
  end

  return GpuSafe.drawTextCenter(
    { gpu = gpu, ui = ui, logger = appLogger, logCategory = "GPU" },
    x,
    y,
    w,
    text,
    color or C.text,
    C.blackA0,
    size or 1,
    0,
    { clipX = x, clipW = w }
  )
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
  local rejectReason = screenSizeRejectReason(sw, sh)
  if rejectReason then
    displayState.invalidScreen = true
    local invalidKey = table.concat({
      tostring(sw),
      tostring(sh),
      tostring(rejectReason),
    }, "|")
    if invalidKey ~= displayState.lastInvalidScreenKey then
      appendUiRuntimeLog(
        "screen invalid: width=" .. tostring(sw)
          .. " height=" .. tostring(sh)
          .. " reason=" .. tostring(rejectReason)
          .. " action=skip_asset_reload_preserve_scene"
      )
      displayState.lastInvalidScreenKey = invalidKey
    end
    return false
  end

  displayState.invalidScreen = false
  displayState.lastInvalidScreenKey = nil
  displayState.lastInvalidRenderKey = nil
  local sizeChanged = (sw ~= displayState.lastWidth) or (sh ~= displayState.lastHeight)
  if sizeChanged then
    appendUiRuntimeLog("screen size detected: " .. tostring(sw) .. "x" .. tostring(sh))
    displayState.lastWidth = sw
    displayState.lastHeight = sh
    state.visual.screenSize = tostring(sw) .. "x" .. tostring(sh)
    state.live.cache = nil
  end

  local scale = math.min(sw / 900, sh / 1400)
  scale = clamp(scale, 0.40, 2.20)

  local screenClass = ResponsiveLayout.classifyScreen(sw, sh)
  local ultraCompact = ResponsiveLayout.isUltraCompactClass(screenClass)
  local ultraCompact4x4 = screenClass == "ultra_compact_4x4"
  local micro = ultraCompact or screenClass == "micro"
  local compact = micro
    or screenClass == "compact"
    or screenClass == "compact_6x5"
    or screenClass == "compact_5x5"
  local overviewPriority = (state.page == "OVERVIEW")

  local screenClassKey = table.concat({
    tostring(screenClass),
    tostring(sw),
    tostring(sh),
  }, "|")
  if screenClassKey ~= displayState.lastScreenClassKey then
    appendUiRuntimeLog("screen class=" .. tostring(screenClass) .. " size=" .. tostring(sw) .. "x" .. tostring(sh))
    displayState.lastScreenClassKey = screenClassKey
  end
  if ultraCompact then
    local survivalKey = table.concat({
      tostring(screenClass),
      tostring(sw),
      tostring(sh),
    }, "|")
    if survivalKey ~= displayState.lastSurvivalModeKey then
      appendUiRuntimeLog(
        "overview compact survival mode enabled"
          .. " class=" .. tostring(screenClass)
          .. " size=" .. tostring(sw) .. "x" .. tostring(sh)
      )
      displayState.lastSurvivalModeKey = survivalKey
    end
  else
    displayState.lastSurvivalModeKey = nil
  end

  local headerH = micro and math.max(24, math.floor(28 * scale + 0.5)) or math.max(56, math.floor(72 * scale + 0.5))
  local footerH = micro and 0 or math.max(52, math.floor(58 * scale + 0.5))
  if ultraCompact4x4 then
    headerH = math.max(12, math.floor(16 * scale + 0.5))
    footerH = 0
  elseif ultraCompact then
    headerH = math.max(14, math.floor(18 * scale + 0.5))
    footerH = 0
  end
  if not micro and overviewPriority then
    headerH = compact and math.max(38, math.floor(46 * scale + 0.5)) or math.max(44, math.floor(52 * scale + 0.5))
    footerH = compact and math.max(24, math.floor(28 * scale + 0.5)) or math.max(28, math.floor(34 * scale + 0.5))
  end

  ui = {
    sw = sw,
    sh = sh,
    scale = scale,
    overviewScreenClass = screenClass,
    overviewResponsiveMode = screenClass,
    ultraCompact = ultraCompact,
    ultraCompact4x4 = ultraCompact4x4,
    compact = compact,
    micro = micro,

    margin = ultraCompact4x4 and 1
      or (ultraCompact and math.max(1, math.floor(2 * scale + 0.5)))
      or (micro and math.max(2, math.floor(4 * scale + 0.5)))
      or math.max(8, math.floor(16 * scale + 0.5)),
    gap = ultraCompact4x4 and 1
      or (ultraCompact and math.max(1, math.floor(2 * scale + 0.5)))
      or (micro and math.max(2, math.floor(4 * scale + 0.5)))
      or math.max(6, math.floor(12 * scale + 0.5)),
    pad = ultraCompact4x4 and 1
      or (ultraCompact and math.max(1, math.floor(2 * scale + 0.5)))
      or (micro and math.max(3, math.floor(5 * scale + 0.5)))
      or math.max(8, math.floor(12 * scale + 0.5)),
    smallPad = ultraCompact and 1
      or (micro and math.max(1, math.floor(3 * scale + 0.5)))
      or math.max(6, math.floor(8 * scale + 0.5)),

    headerH = headerH,
    navH = micro and 0 or math.max(30, math.floor(38 * scale + 0.5)),
    footerH = footerH,
    buttonH = ultraCompact4x4 and math.max(10, math.floor(12 * scale + 0.5))
      or (ultraCompact and math.max(12, math.floor(14 * scale + 0.5)))
      or (micro and math.max(16, math.floor(20 * scale + 0.5)))
      or math.max(28, math.floor(34 * scale + 0.5)),
    gaugeH = ultraCompact and math.max(6, math.floor(8 * scale + 0.5))
      or (micro and math.max(8, math.floor(10 * scale + 0.5)))
      or math.max(14, math.floor(18 * scale + 0.5)),

    titleSize = micro and 1 or (scale >= 1.35 and 2 or 1),
    headerTitleSize = micro and 1 or (scale >= 1.20 and 2 or 1),

    titleBarY = ultraCompact4x4 and math.max(7, math.floor(8 * scale + 0.5))
      or (ultraCompact and math.max(8, math.floor(10 * scale + 0.5)))
      or (micro and math.max(10, math.floor(12 * scale + 0.5)))
      or math.max(20, math.floor(28 * scale + 0.5)),
    labelOffset = ultraCompact and math.max(6, math.floor(7 * scale + 0.5))
      or (micro and math.max(8, math.floor(10 * scale + 0.5)))
      or math.max(12, math.floor(18 * scale + 0.5)),
    tooSmall = sw < 32 or sh < 32,
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

  return sizeChanged
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
  logger = appLogger,
  logging = LOGGING_CFG,
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
  logger = appLogger,
})

local function relaySideConfigured(key)
  return actionRuntime.relaySideConfigured(key)
end

local function processPendingTimer(timerId)
  return actionRuntime.processPendingTimer(timerId)
end

local function classifyRuntimeAction(action)
  return actionRuntime.classifyAction(action)
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
local updateRuntime = UpdateRuntime.create({
  state = state,
  updateCfg = UPDATE_CFG,
  updateStatus = UPDATE_STATUS,
  integrityStatus = INTEGRITY_STATUS,
  updateVersionFile = UPDATE_VERSION_FILE,
  updateManifestFile = UPDATE_MANIFEST_FILE,
  updateLogFile = UPDATE_LOG_FILE,
  updateTempDir = UPDATE_TEMP_DIR,
  updateBackupDir = UPDATE_BACKUP_DIR,
  updateVersion = UpdateVersion,
  updateManifest = UpdateManifest,
  updateClient = UpdateClient,
  updateApply = UpdateApply,
  normalizeIntegrityMode = normalizeIntegrityMode,
  firstLine = firstLine,
  nowMs = nowMs,
  logWithLevel = logWithLevel,
  pollLiveData = pollLiveData,
})

local loadUpdateLogTail = updateRuntime.loadUpdateLogTail
local updateStatusColor = updateRuntime.updateStatusColor
local integrityStatusColor = updateRuntime.integrityStatusColor
local shortIntegrityStatus = updateRuntime.shortIntegrityStatus
local refreshLocalUpdateSnapshot = updateRuntime.refreshLocalUpdateSnapshot
local performUpdateCheck = updateRuntime.performUpdateCheck
local performUpdateDownload = updateRuntime.performUpdateDownload
local performUpdateApply = updateRuntime.performUpdateApply
local performUpdateRollback = updateRuntime.performUpdateRollback
local requestProgramRestart = updateRuntime.requestProgramRestart

-- === Rendering ===
local function drawHeader(r, data)
  drawPanel(r.x, r.y, r.w, r.h, nil)
  local titleY = r.y + math.max(1, math.floor(r.h * 0.10))
  drawTextCenter(r.x, titleY, r.w, data.unitName, C.text, ui.headerTitleSize)

  local capsuleX = r.x + ui.pad
  local capsuleW = r.w - ui.pad * 2
  local capsuleH = math.max(12, math.min(math.floor(r.h * 0.45), sv(18)))
  local capsuleY = r.y + r.h - capsuleH - math.max(1, ui.smallPad)
  local minCapsuleY = titleY + textPixelHeight(ui.headerTitleSize) + 1
  if capsuleY < minCapsuleY then
    capsuleY = minCapsuleY
  end
  local stateColor = chooseStateColor(data)

  gpu.filledRectangle(capsuleX, capsuleY, capsuleW, capsuleH, C.panel2)
  gpu.rectangle(capsuleX, capsuleY, capsuleW, capsuleH, C.border)
  drawTextCenter(
    capsuleX,
    capsuleY + math.max(0, math.floor((capsuleH - textPixelHeight(1)) / 2)),
    capsuleW,
    data.stateText,
    stateColor,
    1
  )
end

local function drawNav(r)
  Views.Navigation.draw({
    rect = r,
    ui = ui,
    pages = PAGES,
    activePage = state.page,
    drawPanel = drawPanel,
    drawButton = drawButton,
  })
end

local function drawFooter(r, data)
  local compactOverview = (state.page == "OVERVIEW")
  if compactOverview then
    drawPanel(r.x, r.y, r.w, r.h, nil)
    local leftX = r.x + ui.pad
    local rightX = r.x + r.w - ui.pad
    local y = r.y + math.max(1, math.floor((r.h - textPixelHeight(1)) / 2))
    drawText(leftX, y, "INFO", C.text, 1)
    drawTextRight(rightX, y, getDataSummary(data), data.alerts == "none" and C.green or C.orange, 1)
    return
  end

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

  local leftText = ui.ultraCompact and "FR" or "FR-U1"
  local rightText = data.status == "STABLE" and "ON" or data.status
  if ui.ultraCompact and #rightText > 4 then
    rightText = string.sub(rightText, 1, 4)
  end
  local centerText = "Lx" .. tostring(CONTROL.laserModuleCount)
  local navW = ui.ultraCompact4x4 and math.max(16, math.floor(r.w * 0.20))
    or math.max(24, math.floor(r.w * 0.24))
  local navH = ui.ultraCompact and math.max(9, r.h - 2) or math.max(12, r.h - 2)
  local navX = r.x + r.w - navW - 1
  local navY = r.y + 1
  local navId = state.page == "MAJ" and "PAGE_OVERVIEW" or "PAGE_MAJ"
  local navLabel = state.page == "MAJ" and (ui.ultraCompact and "HM" or "HOME") or "MAJ"

  local textY = ui.ultraCompact and (r.y + 1) or (r.y + 2)
  drawText(r.x + ui.pad, textY, leftText, C.text, 1)
  drawTextCenter(r.x, textY, r.w, centerText, C.yellow, 1)
  drawTextRight(navX - ui.smallPad, textY, rightText, chooseStateColor(data), 1)
  drawButton(navId, navX, navY, navW, navH, navLabel, "purple", true)
end

local function drawMicroOverview(r, data)
  drawPanel(r.x, r.y, r.w, r.h, nil)

  local statsH = math.max(18, math.floor(r.h * 0.10))
  local gap = ui.gap
  if ui.ultraCompact then
    statsH = 0
    gap = 0
    local panelCollapseKey = table.concat({
      tostring(ui.overviewScreenClass or "ultra"),
      tostring(r.w),
      tostring(r.h),
    }, "|")
    if panelCollapseKey ~= displayState.lastPanelCollapseKey then
      appendUiRuntimeLog(
        "panels collapsed for ultra compact"
          .. " class=" .. tostring(ui.overviewScreenClass or "ultra")
          .. " viewport=" .. tostring(r.w) .. "x" .. tostring(r.h)
      )
      displayState.lastPanelCollapseKey = panelCollapseKey
    end
  else
    displayState.lastPanelCollapseKey = nil
  end

  local minImageH = ui.ultraCompact and 14 or 20
  local imageH = math.max(minImageH, r.h - statsH - gap)
  if imageH + gap >= r.h then
    statsH = 0
    gap = 0
    imageH = r.h
  end

  local imageRect = {
    x = r.x,
    y = r.y,
    w = r.w,
    h = imageH,
  }

  local statsRect = {
    x = r.x,
    y = imageRect.y + imageRect.h + gap,
    w = r.w,
    h = statsH,
  }

  gpu.filledRectangle(imageRect.x, imageRect.y, imageRect.w, imageRect.h, C.white)
  drawImageStack(
    imageRect.x + 1,
    imageRect.y + 1,
    math.max(1, imageRect.w - 2),
    math.max(1, imageRect.h - 2),
    data,
    nil,
    {
      responsiveMode = ui.overviewResponsiveMode or ui.overviewScreenClass,
      sceneViewport = {
        x = imageRect.x + 1,
        y = imageRect.y + 1,
        w = math.max(1, imageRect.w - 2),
        h = math.max(1, imageRect.h - 2),
      },
      reservedRects = {},
    }
  )

  if statsH > 0 then
    gpu.filledRectangle(statsRect.x, statsRect.y, statsRect.w, statsRect.h, C.panel)
    gpu.rectangle(statsRect.x, statsRect.y, statsRect.w, statsRect.h, C.border)

    local y = statsRect.y + math.max(1, math.floor((statsRect.h - textPixelHeight(1)) / 2))
    local summary = "E " .. tostring(math.floor(data.energyPct or 0)) .. "%  DT " .. tostring(math.floor(data.dtPct or 0)) .. "%"
    drawText(statsRect.x + ui.pad, y, summary, C.text, 1)
    drawTextRight(statsRect.x + statsRect.w - ui.pad, y, data.logicMode or "UNK", C.cyan, 1)
  end
end

local function drawMicroMajPage(r, data)
  Views.Update.drawMicro({
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
  Views.Update.draw({
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

local function drawImageStack(slotX, slotY, slotW, slotH, data, forcedLayout, responsiveOptions)
  local resolvedResponsiveOptions = responsiveOptions
  if type(resolvedResponsiveOptions) ~= "table" then
    resolvedResponsiveOptions = {
      responsiveMode = ui and (ui.overviewResponsiveMode or ui.overviewScreenClass) or nil,
      sceneViewport = { x = slotX, y = slotY, w = slotW, h = slotH },
      reservedRects = {},
    }
  elseif resolvedResponsiveOptions.responsiveMode == nil and ui then
    resolvedResponsiveOptions.responsiveMode = ui.overviewResponsiveMode or ui.overviewScreenClass
  end

  local rendererSceneMode = state.visual.sceneMode
  if rendererSceneMode ~= "pair" and rendererSceneMode ~= "reactor-only" and rendererSceneMode ~= "none" then
    if images.reactor and images.laserModule then
      rendererSceneMode = "pair"
    elseif images.reactor then
      rendererSceneMode = "reactor-only"
    else
      rendererSceneMode = "none"
    end
  end

  Views.OverviewGraphics.drawImageStack({
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
    chooseOverviewStackLayout = chooseOverviewStackLayout,
    drawTextCenter = drawTextCenter,
    textPixelHeight = textPixelHeight,
    appendUiRuntimeLog = appendUiRuntimeLog,
    logger = appLogger,
    sceneMode = rendererSceneMode,
    reactorPresent = images.reactor ~= nil,
    laserPresent = images.laserModule ~= nil,
    reactorAssetName = state.visual.reactorAsset,
    laserAssetName = state.visual.moduleAsset,
    fallbackReactorVariant = getFallbackReactorVariant(),
    fallbackLaserVariant = getFallbackLaserModuleVariant(),
    responsiveOptions = resolvedResponsiveOptions,
  })
end

local function drawOverviewReactorLaserScene(slotX, slotY, slotW, slotH, data, layout, responsiveOptions)
  -- Stable wrapper kept in entrypoint to avoid breaking external expectations.
  drawImageStack(slotX, slotY, slotW, slotH, data, layout, responsiveOptions)
end

local function drawOverviewPage(r, data)
  Views.Overview.draw({
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
    appendUiRuntimeLog = appendUiRuntimeLog,
  })
end

local function drawControlPage(r, data)
  Views.Control.draw({
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
  Views.Fuel.draw({
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
  Views.System.draw({
    rect = r,
    data = data,
    ui = ui,
    colors = C,
    state = state,
    splitVertical = splitVertical,
    splitHorizontal = splitHorizontal,
    drawPanel = drawPanel,
    drawToggleRow = drawToggleRow,
    drawButton = drawButton,
    drawText = drawText,
    drawTextRight = drawTextRight,
    drawImageStack = drawImageStack,
    sv = sv,
    gpu = gpu,
    activeGpuName = ACTIVE_GPU_NAME,
    gpuMode = GPU_MODE,
  })
end

local function applyOverviewValidationScenario(baseData, scenario)
  -- Keep OVERVIEW validation simulation isolated from the runtime entrypoint.
  return OverviewValidation.applyScenario(baseData, scenario, { colors = C })
end

local lastOverviewValidationLogKey = nil
local function readFusionData(force)
  local data = pollLiveData(force)
  local source = normalizeOverviewValidationSource(VALIDATION_CFG.overviewSource)
  local scenario = normalizeOverviewValidationScenario(VALIDATION_CFG.overviewScenario)

  VALIDATION_CFG.overviewSource = source
  VALIDATION_CFG.overviewScenario = scenario

  local loggedScenario = (source == "simulate") and scenario or "n/a"
  local logKey = source .. "|" .. loggedScenario
  if logKey ~= lastOverviewValidationLogKey then
    appendUiRuntimeLog("overview validation source=" .. tostring(source) .. " scenario=" .. tostring(loggedScenario))
    lastOverviewValidationLogKey = logKey
  end

  state.visual.validationSource = source
  state.visual.validationScenario = loggedScenario

  if source == "simulate" then
    return applyOverviewValidationScenario(data, scenario)
  end

  return data
end

local appWiring = nil
local render = nil

local function setPage(pageId)
  AppRouter.setPage(appWiring.router, pageId)
end

local function handleAction(action)
  AppRouter.handleAction(appWiring.router, action)
end

local function handleResize(eventName, p1)
  local previousSize = state.visual.screenSize
  local sizeChanged = buildUI()
  if displayState.invalidScreen then
    appendUiRuntimeLog(
      "resize event: " .. tostring(eventName)
        .. " rejected (invalid screen size), keeping previous scene="
        .. tostring(state.visual.sceneMode or "none")
    )
    state.message = "resize pending: invalid screen size"
    return
  end
  if sizeChanged then
    appendUiRuntimeLog("resize event: " .. tostring(eventName) .. " (" .. tostring(p1 or "n/a") .. ") " .. tostring(previousSize) .. " -> " .. tostring(state.visual.screenSize))
    tryLoadAssets("event:" .. tostring(eventName))
    state.message = "resize: " .. tostring(state.visual.screenSize)
  else
    appendUiRuntimeLog("resize event: " .. tostring(eventName) .. " (no size change)")
  end
  render()
end

render = function()
  local sizeChanged = buildUI()
  if displayState.invalidScreen then
    local invalidKey = tostring(displayState.lastInvalidScreenKey or "invalid")
    if invalidKey ~= displayState.lastInvalidRenderKey then
      appendUiRuntimeLog("render skipped: invalid screen size state detected")
      displayState.lastInvalidRenderKey = invalidKey
    end
    return
  end
  if sizeChanged then
    tryLoadAssets("auto-resize:" .. tostring(state.visual.screenSize))
    state.message = "screen resized: " .. tostring(state.visual.screenSize)
  end
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

logWithLevel("INFO", "BOOT", "entrypoint configuration loaded", {
  entrypoint = "start.lua",
  implementation = "start_menu_pages_live_v7_impl.lua",
  gpu = tostring(ACTIVE_GPU_NAME),
  updateBranch = tostring(UPDATE_CFG.branch or "main"),
  updateChannel = tostring(UPDATE_CFG.channel or "stable"),
  validationSource = tostring(VALIDATION_CFG.overviewSource or "terrain"),
  logLevel = tostring(LOGGING_CFG.level),
  runtimeLog = tostring(UI_RUNTIME_LOG_FILE),
  updateLog = tostring(UPDATE_LOG_FILE),
})
logWithLevel("INFO", "BOOT", "modules loaded", {
  app = "core/app/bootstrap.lua,core/app/router.lua,core/app/main_loop.lua",
  runtime = "core/runtime/telemetry_runtime.lua,core/runtime/action_runtime.lua",
  overview = "ui/pages/overview_page.lua,ui/pages/overview_graphics.lua",
})

appWiring = AppBootstrap.buildWiring({
  state = state,
  updateCfg = UPDATE_CFG,
  refreshSeconds = REFRESH_SECONDS,
  loopEventDebug = LOGGING_CFG.loopEventDebug,
  logger = appLogger,
  pageExists = pageExists,
  classifyRuntimeAction = classifyRuntimeAction,
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
  handleResize = handleResize,
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
