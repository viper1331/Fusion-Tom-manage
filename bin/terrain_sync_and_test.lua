local Orchestrator = assert(dofile("core/update/orchestrator.lua"))
local ReportRunner = assert(dofile("terrain/report_runner.lua"))

local function appendLog(message)
  local path = "/terrain_sync_and_test.log"
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

local syncResult = Orchestrator.sync(cfg, appendLog)
print("SYNC RESULT")
print(textutils.serialize(syncResult))
if not syncResult.ok then
  error(syncResult.detail or "sync failed")
end

local expectedVersion = syncResult.localVersionAfter or syncResult.remoteVersion or syncResult.localVersionBefore
local report = ReportRunner.runAll({
  expectedVersion = expectedVersion,
})
print("REPORT")
print(textutils.serialize(report))

local fh = fs.open("/terrain_sync_and_test.report.json", "w")
if fh then
  fh.write(textutils.serializeJSON(report))
  fh.close()
end
