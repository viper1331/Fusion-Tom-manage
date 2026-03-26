local function safeGetTypes(name)
  local ok, a, b, c, d = pcall(peripheral.getType, name)
  if not ok or a == nil then
    return {}
  end

  local out = {}
  for _, v in ipairs({a, b, c, d}) do
    if type(v) == "string" then
      table.insert(out, v)
    end
  end
  return out
end

local function methodSet(name)
  local methods = peripheral.getMethods(name) or {}
  local set = {}
  for _, m in ipairs(methods) do
    set[m] = true
  end
  return set, methods
end

local function hasAll(name, required)
  local set = methodSet(name)
  for _, m in ipairs(required) do
    if not set[m] then
      return false
    end
  end
  return true
end

local function lowerList(list)
  local out = {}
  for i, v in ipairs(list) do
    out[i] = string.lower(v)
  end
  return out
end

local function containsAny(text, needles)
  text = string.lower(text or "")
  for _, n in ipairs(needles) do
    if string.find(text, n, 1, true) then
      return true
    end
  end
  return false
end

local function printSection(title)
  print(("="):rep(60))
  print(title)
  print(("="):rep(60))
end

local function classify(name)
  local types = safeGetTypes(name)
  local _, methods = methodSet(name)
  local typesLower = lowerList(types)

  local info = {
    name = name,
    types = types,
    methods = methods,
    tags = {},
  }

  -- Tom's GPU
  if hasAll(name, {"refreshSize", "sync", "fill", "drawText"}) then
    table.insert(info.tags, "toms_gpu")
  end

  -- Tom's keyboard
  if hasAll(name, {"setFireNativeEvents"}) then
    table.insert(info.tags, "toms_keyboard")
  end

  -- Tom's redstone port
  if hasAll(name, {"setOutput", "getInput"}) then
    table.insert(info.tags, "toms_rsport")
  end

  -- Tom's watchdog
  if hasAll(name, {"isEnabled", "setTimeout", "reset"}) then
    table.insert(info.tags, "toms_wdt")
  end

  -- Mekanism reactor candidate
  local reactorScore = 0
  if containsAny(name, {"fusion", "reactor"}) then reactorScore = reactorScore + 4 end
  for _, t in ipairs(typesLower) do
    if containsAny(t, {"fusion", "reactor"}) then reactorScore = reactorScore + 4 end
  end

  for _, m in ipairs(methods) do
    local lm = string.lower(m)
    if containsAny(lm, {"plasma", "injection", "ignit", "case"}) then
      reactorScore = reactorScore + 2
    end
  end

  if reactorScore >= 4 then
    table.insert(info.tags, "mek_reactor_candidate")
  end

  -- Laser candidate
  local laserScore = 0
  if containsAny(name, {"laser", "amplifier"}) then laserScore = laserScore + 4 end
  for _, t in ipairs(typesLower) do
    if containsAny(t, {"laser", "amplifier"}) then laserScore = laserScore + 4 end
  end
  for _, m in ipairs(methods) do
    local lm = string.lower(m)
    if containsAny(lm, {"energy", "maxenergy", "needed", "stored"}) then
      laserScore = laserScore + 1
    end
  end
  if laserScore >= 4 then
    table.insert(info.tags, "mek_laser_candidate")
  end

  return info
end

local infos = {}
for _, name in ipairs(peripheral.getNames()) do
  table.insert(infos, classify(name))
end

printSection("PERIPHERIQUES DETECTES")
for _, info in ipairs(infos) do
  print("Nom   : " .. info.name)
  print("Types : " .. (#info.types > 0 and table.concat(info.types, ", ") or "(aucun)"))
  print("Tags  : " .. (#info.tags > 0 and table.concat(info.tags, ", ") or "(aucun)"))
  print("Methodes (" .. tostring(#info.methods) .. "):")
  table.sort(info.methods)
  for _, m in ipairs(info.methods) do
    print("  - " .. m)
  end
  print()
end

printSection("RESUME")
local function listByTag(tag)
  for _, info in ipairs(infos) do
    for _, t in ipairs(info.tags) do
      if t == tag then
        print(" - " .. info.name)
        break
      end
    end
  end
end

print("Tom's GPU:")
listByTag("toms_gpu")
print()

print("Tom's Keyboard:")
listByTag("toms_keyboard")
print()

print("Tom's Redstone Port:")
listByTag("toms_rsport")
print()

print("Mekanism Reactor candidates:")
listByTag("mek_reactor_candidate")
print()

print("Mekanism Laser candidates:")
listByTag("mek_laser_candidate")
print()