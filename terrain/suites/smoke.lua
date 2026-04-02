local M = {}

local function fileExists(path)
  return fs.exists(path)
end

function M.run(harness, context)
  local requiredFiles = {
    "start.lua",
    "start_menu_pages_live_v7_impl.lua",
    "fusion.version",
    "fusion.manifest.json",
    "install.lua",
    "core/update/version.lua",
    "core/update/client.lua",
    "core/update/apply.lua",
  }

  for _, path in ipairs(requiredFiles) do
    harness:assertTrue("file:" .. path, fileExists(path), fileExists(path) and "present" or "missing", {
      path = path,
    })
  end

  harness:assertTrue("http_api", type(http) == "table", type(http) == "table" and "http available" or "http unavailable")
  harness:assertTrue("peripheral_api", type(peripheral) == "table", type(peripheral) == "table" and "peripheral available" or "peripheral unavailable")
  harness:assertTrue("tm_gpu_detected", #context.tmGpuNames > 0, #context.tmGpuNames > 0 and "tm_gpu found" or "tm_gpu not found", {
    names = context.tmGpuNames,
  })
  harness:assertTrue("monitor_detected", #context.monitorNames > 0, #context.monitorNames > 0 and "monitor found" or "monitor not found", {
    names = context.monitorNames,
  })
end

return M
