local M = {}

function M.setPage(ctx, pageId)
  if not ctx.pageExists(pageId) then
    ctx.state.message = "unknown page: " .. tostring(pageId)
    return false
  end

  ctx.state.page = pageId
  if pageId ~= "MAJ" then
    ctx.state.update.applyConfirmArmed = false
  end
  ctx.state.lastAction = "page:" .. pageId:lower()
  ctx.state.message = "page " .. pageId:lower()
  return true
end

function M.drawCurrentPage(ctx, bodyRect, data)
  if ctx.state.page == "OVERVIEW" then
    ctx.drawOverviewPage(bodyRect, data)
  elseif ctx.state.page == "CONTROL" then
    ctx.drawControlPage(bodyRect, data)
  elseif ctx.state.page == "FUEL" then
    ctx.drawFuelPage(bodyRect, data)
  elseif ctx.state.page == "SYSTEM" then
    ctx.drawSystemPage(bodyRect, data)
  else
    ctx.drawUpdatePage(bodyRect)
  end
end

function M.handleAction(ctx, action)
  if string.sub(action, 1, 5) == "PAGE_" then
    M.setPage(ctx, string.sub(action, 6))
    return
  end

  ctx.state.lastAction = action

  if ctx.executeRuntimeCommand(action) then
    -- Runtime action handled in dedicated module.

  elseif action == "RELOAD_ASSETS" then
    ctx.tryLoadAssets()
    ctx.state.message = "assets reloaded"

  elseif action == "UPDATE_CHECK" then
    local ok, msg = ctx.performUpdateCheck("manual")
    ctx.state.message = ok and ("MAJ CHECK -> " .. tostring(ctx.state.update.remoteStatus) .. " (" .. ctx.firstLine(msg) .. ")") or ("MAJ CHECK ERROR -> " .. ctx.firstLine(msg))

  elseif action == "UPDATE_DOWNLOAD" then
    local ok, msg = ctx.performUpdateDownload()
    ctx.state.message = ok and ("MAJ DOWNLOAD -> " .. tostring(ctx.state.update.remoteStatus) .. " (" .. ctx.firstLine(msg) .. ")") or ("MAJ DOWNLOAD ERROR -> " .. ctx.firstLine(msg))

  elseif action == "UPDATE_APPLY" then
    local ok, msg = ctx.performUpdateApply()
    ctx.state.message = ok and ("MAJ APPLY -> " .. tostring(ctx.state.update.remoteStatus) .. " (" .. ctx.firstLine(msg) .. ")") or ("MAJ APPLY ERROR -> " .. ctx.firstLine(msg))

  elseif action == "UPDATE_ROLLBACK" then
    local ok, msg = ctx.performUpdateRollback()
    ctx.state.message = ok and ("MAJ ROLLBACK -> " .. tostring(ctx.state.update.remoteStatus) .. " (" .. ctx.firstLine(msg) .. ")") or ("MAJ ROLLBACK ERROR -> " .. ctx.firstLine(msg))

  elseif action == "UPDATE_RESTART" then
    local ok, msg = ctx.requestProgramRestart()
    ctx.state.message = ok and ctx.firstLine(msg) or ("restart failed: " .. ctx.firstLine(msg))

  else
    ctx.state.message = action
  end

  ctx.pollLiveData(true)
end

return M
