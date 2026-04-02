local M = {}

local function readVersion(path)
  if not fs.exists(path) then
    return nil
  end
  local fh = fs.open(path, "r")
  if not fh then
    return nil
  end
  local value = fh.readAll() or ""
  fh.close()
  return tostring(value):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.run(harness, context)
  local localVersion = readVersion("fusion.version")
  harness:assertTrue("version_file_present", localVersion ~= nil and localVersion ~= "", localVersion and "version read" or "version missing", {
    localVersion = localVersion,
  })

  if context.expectedVersion and context.expectedVersion ~= "" then
    harness:assertTrue(
      "version_matches_expected",
      localVersion == context.expectedVersion,
      localVersion == context.expectedVersion and "version synced" or "terrain version mismatch",
      {
        localVersion = localVersion,
        expectedVersion = context.expectedVersion,
      }
    )
  else
    harness:note("expectedVersion missing from context", {
      localVersion = localVersion,
    })
  end

  harness:assertTrue("manifest_present", fs.exists("fusion.manifest.json"), fs.exists("fusion.manifest.json") and "manifest present" or "manifest missing")
  harness:assertTrue("backup_dir_known", fs.exists("/.backup_last") or fs.exists("/backup_rescue"), "backup directory snapshot captured", {
    backupMain = fs.exists("/.backup_last"),
    backupRescue = fs.exists("/backup_rescue"),
  })
end

return M
