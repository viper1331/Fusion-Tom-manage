local Orchestrator = assert(dofile("core/update/orchestrator.lua"))

local function appendLog(message)
  local path = "/update_orchestrator.log"
  local fh = fs.open(path, "a")
  if fh then
    fh.writeLine("[" .. os.date("%Y-%m-%d %H:%M:%S") .. "] " .. tostring(message))
    fh.close()
  end
end

local ok, cfg = pcall(dofile, "fusion_config.lua")
if not ok or type(cfg) ~= "table" then
  cfg = {}
end

local result = Orchestrator.apply(cfg, appendLog)
print(textutils.serialize(result))
if not result.ok then
  error(result.detail or "apply failed")
end
