-- install.lua
-- Assistant de configuration Fusion Reactor UI
-- Cree fusion_config.lua pour start.lua

local CONFIG_FILE = "fusion_config.lua"
local MAIN_SCRIPT = "start.lua"

local defaults = {
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
  ui = {
    startPage = "OVERVIEW",
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

local cfg = textutils.unserialize(textutils.serialize(defaults))

local SIDE_OPTIONS = { "", "top", "bottom", "left", "right", "front", "back" }
local PAGE_OPTIONS = { "OVERVIEW", "CONTROL", "FUEL", "SYSTEM", "MAJ" }

local function cls()
  term.setBackgroundColor(colors.black)
  term.setTextColor(colors.white)
  term.clear()
  term.setCursorPos(1, 1)
end

local function title(text)
  cls()
  print("=== Fusion Reactor UI Installer ===")
  print(text)
  print(string.rep("-", 36))
end

local function pause(msg)
  print("")
  print(msg or "Appuie sur une touche pour continuer...")
  os.pullEvent("key")
end

local function prompt(default, label)
  write(label .. " [" .. tostring(default) .. "] : ")
  local v = read()
  if v == "" then
    return default
  end
  return v
end

local function promptNumber(default, label, minv, maxv)
  while true do
    local v = tonumber(prompt(default, label))
    if v and (not minv or v >= minv) and (not maxv or v <= maxv) then
      return v
    end
    print("Valeur invalide.")
  end
end

local function promptBool(default, label)
  local def = default and "o" or "n"
  while true do
    write(label .. " [o/n, defaut=" .. def .. "] : ")
    local v = string.lower(read() or "")
    if v == "" then
      return default == true
    end
    if v == "o" or v == "y" then
      return true
    end
    if v == "n" then
      return false
    end
    print("Reponse invalide, utiliser o ou n.")
  end
end

local function choose(label, options, defaultIndex)
  local index = defaultIndex or 1
  while true do
    title(label)
    for i, option in ipairs(options) do
      local mark = (i == index) and ">" or " "
      print(mark .. " " .. i .. ". " .. tostring(option))
    end
    print("")
    print("Entrer = valider / n° = choisir")
    local raw = read()
    if raw == "" then
      return options[index], index
    end
    local n = tonumber(raw)
    if n and options[n] ~= nil then
      index = n
    end
  end
end

local function detectList(filter)
  local out = {}
  local names = peripheral.getNames()
  table.sort(names)
  for _, name in ipairs(names) do
    if not filter or string.find(name, filter, 1, true) then
      out[#out + 1] = name
    end
  end
  return out
end

local function detectRemoteList(modemSide)
  local remote = {}
  if modemSide and peripheral.isPresent(modemSide) then
    local modem = peripheral.wrap(modemSide)
    if modem and type(modem.getNamesRemote) == "function" then
      local ok, names = pcall(modem.getNamesRemote)
      if ok and type(names) == "table" then
        table.sort(names)
        for _, name in ipairs(names) do
          remote[#remote + 1] = name
        end
      end
    end
  end
  return remote
end

local function printDetected(titleText, list)
  print(titleText)
  if #list == 0 then
    print("  aucun")
    return
  end
  for _, item in ipairs(list) do
    print("  - " .. item)
  end
end

local function stepDetection()
  title("Etape 1 - Detection")
  local localNames = detectList()
  local remoteNames = detectRemoteList(cfg.devices.modem)
  printDetected("Peripheriques locaux :", localNames)
  print("")
  printDetected("Peripheriques distants :", remoteNames)
  pause()
end

local function stepDisplay()
  title("Etape 2 - Affichage")
  cfg.devices.modem = prompt(cfg.devices.modem, "Cote du modem")
  cfg.devices.gpu = prompt(cfg.devices.gpu, "Nom du tm_gpu")
  cfg.ui.startPage = select(1, choose("Page de demarrage", PAGE_OPTIONS, 1))
end

local function stepCoreDevices()
  title("Etape 3 - Devices coeur reacteur")
  cfg.devices.logic = prompt(cfg.devices.logic, "Logic adapter")
  cfg.devices.induction = prompt(cfg.devices.induction, "Induction port")
  cfg.devices.laserAmplifier = prompt(cfg.devices.laserAmplifier, "Laser amplifier")
  cfg.devices.laser = prompt(cfg.devices.laser, "Laser")
  cfg.devices.fusionController = prompt(cfg.devices.fusionController, "Fusion controller")
end

local function stepReaders()
  title("Etape 4 - Block readers")
  cfg.devices.readers.deuterium = prompt(cfg.devices.readers.deuterium, "Reader Deuterium")
  cfg.devices.readers.tritium = prompt(cfg.devices.readers.tritium, "Reader Tritium")
  cfg.devices.readers.dtFuel = prompt(cfg.devices.readers.dtFuel, "Reader DT Fuel")
  cfg.devices.readers.active = prompt(cfg.devices.readers.active, "Reader Active")
end

local function stepRelays()
  title("Etape 5 - Relais")
  cfg.devices.relays.laserCharge = prompt(cfg.devices.relays.laserCharge, "Relay laser charge")
  cfg.devices.relays.deuteriumTank = prompt(cfg.devices.relays.deuteriumTank, "Relay tank deuterium")
  cfg.devices.relays.tritiumTank = prompt(cfg.devices.relays.tritiumTank, "Relay tank tritium")
  cfg.devices.relays.aux = prompt(cfg.devices.relays.aux, "Relay auxiliaire")
end

local function chooseSide(current, label)
  local index = 1
  for i, side in ipairs(SIDE_OPTIONS) do
    if side == current then
      index = i
      break
    end
  end
  return select(1, choose(label, SIDE_OPTIONS, index))
end

local function stepRelaySides()
  title("Etape 6 - Sides relais")
  cfg.control.relaySides.laserCharge = chooseSide(cfg.control.relaySides.laserCharge, "Side laser charge")
  cfg.control.relaySides.deuteriumTank = chooseSide(cfg.control.relaySides.deuteriumTank, "Side tank deuterium")
  cfg.control.relaySides.tritiumTank = chooseSide(cfg.control.relaySides.tritiumTank, "Side tank tritium")
  cfg.control.relaySides.aux = chooseSide(cfg.control.relaySides.aux, "Side auxiliaire")
end

local function stepControl()
  title("Etape 7 - Gestion reacteur")
  cfg.control.telemetryPollMs = promptNumber(cfg.control.telemetryPollMs, "Polling telemetry ms", 100, 5000)
  cfg.control.laserPulseSeconds = promptNumber(cfg.control.laserPulseSeconds, "Pulse laser secondes", 0.05, 5)
  cfg.control.relayAnalogStrength = promptNumber(cfg.control.relayAnalogStrength, "Force analogique relais", 0, 15)
  cfg.control.laserModuleCount = promptNumber(cfg.control.laserModuleCount, "Nombre de modules laser terrain", 1, 64)
end

local function stepUpdate()
  title("Etape 8 - Mise a jour (MAJ)")
  cfg.update.channel = prompt(cfg.update.channel, "Canal de mise a jour (stable)")
  cfg.update.owner = prompt(cfg.update.owner, "GitHub owner")
  cfg.update.repo = prompt(cfg.update.repo, "GitHub repository")
  cfg.update.branch = prompt(cfg.update.branch, "Branche distante")
  cfg.update.manifestPath = prompt(cfg.update.manifestPath, "Chemin manifest distant")
  cfg.update.rawBaseUrl = prompt(cfg.update.rawBaseUrl, "Raw base URL optionnelle (laisser vide pour GitHub raw)")
  cfg.update.requireConfirmApply = promptBool(cfg.update.requireConfirmApply, "Confirmer avant APPLY")
  cfg.update.autoCheckOnStartup = promptBool(cfg.update.autoCheckOnStartup, "Auto CHECK au demarrage")
end

local function writeConfig(path, data)
  local fh = assert(fs.open(path, "w"))
  fh.write("return ")
  fh.write(textutils.serialize(data))
  fh.close()
end

local function summary()
  title("Resume configuration")
  print("GPU: " .. cfg.devices.gpu)
  print("Logic: " .. cfg.devices.logic)
  print("Induction: " .. cfg.devices.induction)
  print("Laser amplifier: " .. cfg.devices.laserAmplifier)
  print("Laser modules: " .. tostring(cfg.control.laserModuleCount))
  print("Polling: " .. tostring(cfg.control.telemetryPollMs) .. " ms")
  print("Page start: " .. tostring(cfg.ui.startPage))
  print("Update channel: " .. tostring(cfg.update.channel))
  print("Update branch: " .. tostring(cfg.update.branch))
  print("Auto-check: " .. tostring(cfg.update.autoCheckOnStartup))
  print("")
  print("Sauvegarder ? (o/n)")
  local a = read()
  if a == "o" or a == "O" or a == "y" or a == "Y" then
    writeConfig(CONFIG_FILE, cfg)
    print("")
    print("Configuration ecrite dans " .. CONFIG_FILE)
    print("Lancer ensuite: lua " .. MAIN_SCRIPT)
  else
    print("")
    print("Annule.")
  end
end

stepDetection()
stepDisplay()
stepCoreDevices()
stepReaders()
stepRelays()
stepRelaySides()
stepControl()
stepUpdate()
summary()
