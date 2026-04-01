local M = {}

local function logWithLevel(logger, level, category, message, context)
  if not logger then
    return
  end

  local method = string.lower(tostring(level or "info"))
  local fn = logger[method]
  if type(fn) == "function" then
    fn(category, message, context, "runtime")
    return
  end

  if type(logger.info) == "function" then
    logger.info(category, message, context, "runtime")
  end
end

local function classifyAction(ctx, action)
  if type(action) ~= "string" then
    return "other"
  end

  if string.sub(action, 1, 5) == "PAGE_" then
    return "router"
  end

  if string.sub(action, 1, 7) == "UPDATE_" then
    return "update"
  end

  if type(ctx.classifyRuntimeAction) == "function" then
    local class = ctx.classifyRuntimeAction(action)
    if type(class) == "string" and class ~= "" then
      return class
    end
  end

  return "other"
end

function M.setPage(ctx, pageId)
  if not ctx.pageExists(pageId) then
    ctx.state.message = "unknown page: " .. tostring(pageId)
    logWithLevel(ctx.logger, "warn", "ROUTER", "invalid page requested", {
      page = tostring(pageId),
    })
    return false
  end

  local previousPage = ctx.state.page
  ctx.state.page = pageId
  if pageId ~= "MAJ" then
    ctx.state.update.applyConfirmArmed = false
  end
  ctx.state.lastAction = "page:" .. pageId:lower()
  ctx.state.message = "page " .. pageId:lower()
  logWithLevel(ctx.logger, "info", "ROUTER", "page changed", {
    from = tostring(previousPage or "n/a"),
    to = tostring(pageId),
  })
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
  local classification = classifyAction(ctx, action)
  logWithLevel(ctx.logger, "info", "ROUTER", "action routed", {
    action = tostring(action),
    class = classification,
    page = tostring(ctx.state.page or "n/a"),
  })

  if string.sub(action, 1, 5) == "PAGE_" then
    M.setPage(ctx, string.sub(action, 6))
    return
  end

  ctx.state.lastAction = action

  if ctx.executeRuntimeCommand(action) then
    -- Runtime action handled in dedicated module.
    logWithLevel(ctx.logger, "info", "ROUTER", "runtime action handled", {
      action = tostring(action),
      class = classification,
    })

  elseif action == "RELOAD_ASSETS" then
    ctx.tryLoadAssets()
    ctx.state.message = "assets reloaded"
    logWithLevel(ctx.logger, "info", "ROUTER", "assets reload requested")

  elseif action == "UPDATE_CHECK" then
    local ok, msg = ctx.performUpdateCheck("manual")
    ctx.state.message = ok and ("MAJ CHECK -> " .. tostring(ctx.state.update.remoteStatus) .. " (" .. ctx.firstLine(msg) .. ")") or ("MAJ CHECK ERROR -> " .. ctx.firstLine(msg))
    logWithLevel(ctx.logger, ok and "info" or "warn", "ROUTER", "update check routed", {
      ok = ok == true,
      status = tostring(ctx.state.update.remoteStatus or "n/a"),
    })

  elseif action == "UPDATE_DOWNLOAD" then
    local ok, msg = ctx.performUpdateDownload()
    ctx.state.message = ok and ("MAJ DOWNLOAD -> " .. tostring(ctx.state.update.remoteStatus) .. " (" .. ctx.firstLine(msg) .. ")") or ("MAJ DOWNLOAD ERROR -> " .. ctx.firstLine(msg))
    logWithLevel(ctx.logger, ok and "info" or "warn", "ROUTER", "update download routed", {
      ok = ok == true,
      status = tostring(ctx.state.update.remoteStatus or "n/a"),
    })

  elseif action == "UPDATE_APPLY" then
    local ok, msg = ctx.performUpdateApply()
    ctx.state.message = ok and ("MAJ APPLY -> " .. tostring(ctx.state.update.remoteStatus) .. " (" .. ctx.firstLine(msg) .. ")") or ("MAJ APPLY ERROR -> " .. ctx.firstLine(msg))
    logWithLevel(ctx.logger, ok and "info" or "warn", "ROUTER", "update apply routed", {
      ok = ok == true,
      status = tostring(ctx.state.update.remoteStatus or "n/a"),
    })

  elseif action == "UPDATE_ROLLBACK" then
    local ok, msg = ctx.performUpdateRollback()
    ctx.state.message = ok and ("MAJ ROLLBACK -> " .. tostring(ctx.state.update.remoteStatus) .. " (" .. ctx.firstLine(msg) .. ")") or ("MAJ ROLLBACK ERROR -> " .. ctx.firstLine(msg))
    logWithLevel(ctx.logger, ok and "info" or "warn", "ROUTER", "update rollback routed", {
      ok = ok == true,
      status = tostring(ctx.state.update.remoteStatus or "n/a"),
    })

  elseif action == "UPDATE_RESTART" then
    local ok, msg = ctx.requestProgramRestart()
    ctx.state.message = ok and ctx.firstLine(msg) or ("restart failed: " .. ctx.firstLine(msg))
    logWithLevel(ctx.logger, ok and "info" or "warn", "ROUTER", "update restart routed", {
      ok = ok == true,
    })

  else
    ctx.state.message = action
    logWithLevel(ctx.logger, "debug", "ROUTER", "action forwarded as message", {
      action = tostring(action),
    })
  end

  ctx.pollLiveData(true)
end

return M
