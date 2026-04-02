local ReportRunner = assert(dofile("terrain/report_runner.lua"))

local expectedVersion = nil
if fs.exists("fusion.version") then
  local fh = fs.open("fusion.version", "r")
  if fh then
    expectedVersion = (fh.readAll() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    fh.close()
  end
end

local report = ReportRunner.runAll({
  expectedVersion = expectedVersion,
})
print(textutils.serialize(report))

local fh = fs.open("/terrain_test_only.report.json", "w")
if fh then
  fh.write(textutils.serializeJSON(report))
  fh.close()
end
