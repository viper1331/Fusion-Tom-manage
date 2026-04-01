local M = {}

local LEVEL_PRIORITY = {
  DEBUG = 10,
  INFO = 20,
  WARN = 30,
  ERROR = 40,
}

local DEFAULT_FILES = {
  runtime = "ui_runtime.log",
  update = "update.log",
  rescue = "/rescue_update.log",
}

local DEFAULT_CATEGORIES = {
  BOOT = true,
  ROUTER = true,
  LOOP = true,
  INPUT = true,
  TELEMETRY = true,
  ACTIONS = true,
  OVERVIEW = true,
  ASSETS = true,
  ANIMATIONS = true,
  GPU = true,
  UPDATE = true,
  RESCUE = true,
}

local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end

  if os.epoch then
    return tostring(os.epoch("utc"))
  end
  return tostring(math.floor((os.clock() or 0) * 1000))
end

local function nowMs()
  if os.epoch then
    return os.epoch("utc")
  end
  return math.floor((os.clock() or 0) * 1000)
end

local function normalizeLevel(value, fallback)
  local raw = tostring(value or fallback or "INFO")
  raw = string.upper(raw)
  if LEVEL_PRIORITY[raw] then
    return raw
  end
  return tostring(fallback or "INFO")
end

local function normalizeCategory(value)
  local raw = tostring(value or "BOOT")
  raw = string.upper(raw)
  if DEFAULT_CATEGORIES[raw] then
    return raw
  end
  return raw
end

local function normalizePath(path)
  if type(path) ~= "string" or path == "" then
    return nil
  end
  return path
end

local function ensureParentDir(path)
  if type(path) ~= "string" or path == "" then
    return
  end
  local dir = fs.getDir(path)
  if dir and dir ~= "" and not fs.exists(dir) then
    fs.makeDir(dir)
  end
end

local function contextValueToString(value, depth)
  local valueType = type(value)
  if valueType == "nil" then
    return "nil"
  end
  if valueType == "string" or valueType == "number" or valueType == "boolean" then
    return tostring(value)
  end
  if valueType ~= "table" then
    return "<" .. valueType .. ">"
  end

  depth = depth or 0
  if depth >= 2 then
    return "{...}"
  end

  local parts = {}
  for key, item in pairs(value) do
    parts[#parts + 1] = tostring(key) .. "=" .. contextValueToString(item, depth + 1)
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ",") .. "}"
end

local function contextToString(context)
  if type(context) ~= "table" then
    return ""
  end

  local parts = {}
  for key, value in pairs(context) do
    parts[#parts + 1] = tostring(key) .. "=" .. contextValueToString(value, 0)
  end
  table.sort(parts)
  return table.concat(parts, " ")
end

local function normalizeFiles(configFiles)
  local files = {
    runtime = DEFAULT_FILES.runtime,
    update = DEFAULT_FILES.update,
    rescue = DEFAULT_FILES.rescue,
  }

  if type(configFiles) ~= "table" then
    return files
  end

  for key, path in pairs(configFiles) do
    local normalized = normalizePath(path)
    if normalized then
      files[key] = normalized
    end
  end

  return files
end

function M.create(config)
  config = type(config) == "table" and config or {}
  local state = {
    level = normalizeLevel(config.level, "INFO"),
    defaultSink = tostring(config.defaultSink or "runtime"),
    files = normalizeFiles(config.files),
    onceKeys = {},
    throttleKeys = {},
  }

  local logger = {}

  local function shouldWrite(level)
    local threshold = LEVEL_PRIORITY[state.level] or LEVEL_PRIORITY.INFO
    local current = LEVEL_PRIORITY[level] or LEVEL_PRIORITY.INFO
    return current >= threshold
  end

  local function resolveSinkPath(sink)
    local sinkName = tostring(sink or state.defaultSink or "runtime")
    return state.files[sinkName] or state.files.runtime or DEFAULT_FILES.runtime
  end

  local function writeLine(path, line)
    ensureParentDir(path)
    local fh = fs.open(path, "a")
    if not fh then
      return false, "cannot open log file: " .. tostring(path)
    end
    fh.writeLine(line)
    fh.close()
    return true, nil
  end

  function logger.configure(newConfig)
    if type(newConfig) ~= "table" then
      return
    end

    if newConfig.level ~= nil then
      state.level = normalizeLevel(newConfig.level, state.level)
    end
    if newConfig.defaultSink ~= nil then
      state.defaultSink = tostring(newConfig.defaultSink)
    end
    if newConfig.files ~= nil then
      state.files = normalizeFiles(newConfig.files)
    end
  end

  function logger.log(level, category, message, context, sink)
    local normalizedLevel = normalizeLevel(level, "INFO")
    if not shouldWrite(normalizedLevel) then
      return false, "filtered"
    end

    local normalizedCategory = normalizeCategory(category)
    local line = "[" .. nowText() .. "] [" .. normalizedLevel .. "] [" .. normalizedCategory .. "] " .. tostring(message or "")
    local contextText = contextToString(context)
    if contextText ~= "" then
      line = line .. " | " .. contextText
    end

    local sinkPath = resolveSinkPath(sink)
    local ok, err = writeLine(sinkPath, line)
    if not ok then
      return false, err
    end
    return true, line
  end

  function logger.debug(category, message, context, sink)
    return logger.log("DEBUG", category, message, context, sink)
  end

  function logger.info(category, message, context, sink)
    return logger.log("INFO", category, message, context, sink)
  end

  function logger.warn(category, message, context, sink)
    return logger.log("WARN", category, message, context, sink)
  end

  function logger.error(category, message, context, sink)
    return logger.log("ERROR", category, message, context, sink)
  end

  function logger.once(key, level, category, message, context, sink)
    local normalizedKey = tostring(key or "")
    if normalizedKey == "" then
      return logger.log(level, category, message, context, sink)
    end
    if state.onceKeys[normalizedKey] then
      return false, "duplicate"
    end
    state.onceKeys[normalizedKey] = true
    return logger.log(level, category, message, context, sink)
  end

  function logger.throttle(key, intervalMs, level, category, message, context, sink)
    local normalizedKey = tostring(key or "")
    if normalizedKey == "" then
      return logger.log(level, category, message, context, sink)
    end

    local minInterval = math.max(0, math.floor(tonumber(intervalMs) or 0))
    local now = nowMs()
    local previous = state.throttleKeys[normalizedKey]
    if previous and (now - previous) < minInterval then
      return false, "throttled"
    end

    state.throttleKeys[normalizedKey] = now
    return logger.log(level, category, message, context, sink)
  end

  function logger.getLevel()
    return state.level
  end

  function logger.getFiles()
    local out = {}
    for key, value in pairs(state.files) do
      out[key] = value
    end
    return out
  end

  return logger
end

return M
