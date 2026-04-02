local function nowText()
  local ok, value = pcall(os.date, "%Y-%m-%d %H:%M:%S")
  if ok and type(value) == "string" and value ~= "" then
    return value
  end
  return tostring(os.epoch and os.epoch("utc") or 0)
end

local function appendBootLog(message)
  local fh = fs.open("/terrain_agent.startup.log", "a")
  if fh then
    fh.writeLine("[" .. nowText() .. "] " .. tostring(message))
    fh.close()
  end
end

appendBootLog("boot: loading terrain/agent_daemon.lua")
local okAgent, agentOrErr = pcall(dofile, "terrain/agent_daemon.lua")
if not okAgent then
  appendBootLog("boot: load failed err=" .. tostring(agentOrErr))
  error(agentOrErr)
end

if type(agentOrErr) ~= "table" or type(agentOrErr.runLoop) ~= "function" then
  appendBootLog("boot: invalid daemon module")
  error("invalid terrain agent daemon module")
end

appendBootLog("boot: runLoop start")
local okRun, runErr = pcall(agentOrErr.runLoop)
if not okRun then
  appendBootLog("boot: runLoop crash err=" .. tostring(runErr))
  error(runErr)
end
