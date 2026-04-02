local Harness = {}
Harness.__index = Harness

local function now()
  if os.epoch then
    return os.epoch("utc")
  end
  return 0
end

local function sanitize(value, depth, seen)
  depth = depth or 0
  seen = seen or {}

  if depth > 12 then
    return "[max-depth]"
  end

  local t = type(value)
  if t == "nil" or t == "boolean" or t == "number" or t == "string" then
    return value
  end

  if t ~= "table" then
    return tostring(value)
  end

  if seen[value] then
    return "[repeated]"
  end
  seen[value] = true

  local out = {}
  local maxIndex = 0
  local array = true
  for k, _ in pairs(value) do
    if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then
      array = false
      break
    end
    if k > maxIndex then
      maxIndex = k
    end
  end

  if array then
    for i = 1, maxIndex do
      out[i] = sanitize(value[i], depth + 1, seen)
    end
  else
    for k, v in pairs(value) do
      out[tostring(k)] = sanitize(v, depth + 1, seen)
    end
  end

  seen[value] = nil
  return out
end

local function readSmallFile(path)
  if not fs.exists(path) then
    return nil
  end
  local fh = fs.open(path, "r")
  if not fh then
    return nil
  end
  local content = fh.readAll() or ""
  fh.close()
  if #content > 8000 then
    return string.sub(content, 1, 8000) .. "\n...[truncated]"
  end
  return content
end

local function safeCall(fn, ...)
  local ok, a, b, c = pcall(fn, ...)
  return ok, a, b, c
end

function Harness.new(label, project)
  local self = setmetatable({}, Harness)
  self.label = label or "terrain_smoke"
  self.project = project or "Fusion-Tom-manage"
  self.started_at = now()
  self.results = {}
  self.notes = {}
  return self
end

function Harness:addResult(ok, name, message, data)
  self.results[#self.results + 1] = {
    ok = ok == true,
    name = tostring(name or "result"),
    message = tostring(message or ""),
    data = sanitize(data),
  }
end

function Harness:pass(name, message, data)
  self:addResult(true, name, message, data)
end

function Harness:fail(name, message, data)
  self:addResult(false, name, message, data)
end

function Harness:note(message, data)
  self.notes[#self.notes + 1] = {
    message = tostring(message or ""),
    data = sanitize(data),
  }
end

function Harness:assertTrue(name, value, message, data)
  if value then
    self:pass(name, message or "ok", data)
  else
    self:fail(name, message or "expected true", data)
  end
end

function Harness:probePeripheral(name)
  local present = peripheral.isPresent(name)
  local info = {
    name = name,
    present = present,
    type = present and peripheral.getType(name) or nil,
    methods = present and peripheral.getMethods(name) or {},
  }

  if present then
    local wrapped = peripheral.wrap(name)
    if wrapped and type(wrapped.getSize) == "function" then
      local ok, w, h = safeCall(function() return wrapped.getSize() end)
      if ok then
        info.getSize = { width = w, height = h }
      end
    end
    if wrapped and type(wrapped.getTextScale) == "function" then
      local ok, scale = safeCall(function() return wrapped.getTextScale() end)
      if ok then
        info.textScale = scale
      end
    end
  end

  return info
end

function Harness:listPeripherals()
  local names = peripheral.getNames()
  table.sort(names)
  local out = {}
  for _, name in ipairs(names) do
    out[#out + 1] = self:probePeripheral(name)
  end
  return out
end

function Harness:getEnvironment()
  local width, height = term.getSize()
  local currentDir = "/"
  if type(shell) == "table" and type(shell.dir) == "function" then
    currentDir = shell.dir()
  end

  return {
    computer_id = os.getComputerID(),
    computer_label = os.getComputerLabel(),
    shell_dir = currentDir,
    term_size = { width = width, height = height },
    disk_free = fs.getFreeSpace("/"),
    fusion_version = readSmallFile("fusion.version"),
    fusion_manifest_present = fs.exists("fusion.manifest.json"),
    startup_present = fs.exists("startup") or fs.exists("startup.lua"),
  }
end

function Harness:finish(extra)
  local ended = now()
  local report = {
    label = self.label,
    suite = "cc_toms_terrain",
    project = self.project,
    started_epoch = self.started_at,
    ended_epoch = ended,
    duration_ms = math.max(0, ended - self.started_at),
    environment = sanitize(self:getEnvironment()),
    peripherals = sanitize(self:listPeripherals()),
    notes = sanitize(self.notes),
    results = sanitize(self.results),
    extra = sanitize(extra or {}),
  }
  return report
end

return Harness
