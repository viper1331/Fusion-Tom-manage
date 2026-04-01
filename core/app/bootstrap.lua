local M = {}

local function logInfo(logger, category, message, context)
  if logger and type(logger.info) == "function" then
    logger.info(category, message, context, "runtime")
  end
end

function M.buildWiring(args)
  return {
    startup = {
      buildUI = args.buildUI,
      tryLoadAssets = args.tryLoadAssets,
      refreshLocalUpdateSnapshot = args.refreshLocalUpdateSnapshot,
      loadUpdateLogTail = args.loadUpdateLogTail,
      updateCfg = args.updateCfg,
      performUpdateCheck = args.performUpdateCheck,
      pollLiveData = args.pollLiveData,
      render = args.render,
      firstLine = args.firstLine,
      state = args.state,
      logger = args.logger,
    },
    router = {
      state = args.state,
      pageExists = args.pageExists,
      classifyRuntimeAction = args.classifyRuntimeAction,
      executeRuntimeCommand = args.executeRuntimeCommand,
      tryLoadAssets = args.tryLoadAssets,
      performUpdateCheck = args.performUpdateCheck,
      performUpdateDownload = args.performUpdateDownload,
      performUpdateApply = args.performUpdateApply,
      performUpdateRollback = args.performUpdateRollback,
      requestProgramRestart = args.requestProgramRestart,
      pollLiveData = args.pollLiveData,
      firstLine = args.firstLine,
      drawOverviewPage = args.drawOverviewPage,
      drawControlPage = args.drawControlPage,
      drawFuelPage = args.drawFuelPage,
      drawSystemPage = args.drawSystemPage,
      drawUpdatePage = args.drawUpdatePage,
      logger = args.logger,
    },
    loop = {
      refreshSeconds = args.refreshSeconds,
      render = args.render,
      processPendingTimer = args.processPendingTimer,
      pollLiveData = args.pollLiveData,
      invalidateWrapped = args.invalidateWrapped,
      getButtons = args.getButtons,
      hit = args.hit,
      handleAction = args.handleAction,
      handleResize = args.handleResize,
      logger = args.logger,
      loopEventDebug = args.loopEventDebug == true,
    },
  }
end

function M.initialize(ctx)
  logInfo(ctx.logger, "BOOT", "startup initialize begin")
  logInfo(ctx.logger, "BOOT", "buildUI start")
  ctx.buildUI()
  logInfo(ctx.logger, "BOOT", "buildUI done")
  logInfo(ctx.logger, "BOOT", "asset load start")
  ctx.tryLoadAssets()
  logInfo(ctx.logger, "BOOT", "asset load done")
  ctx.refreshLocalUpdateSnapshot()
  logInfo(ctx.logger, "BOOT", "update snapshot refreshed")
  ctx.loadUpdateLogTail(12)
  logInfo(ctx.logger, "BOOT", "update log tail loaded", { lines = 12 })
  if ctx.updateCfg.autoCheckOnStartup then
    logInfo(ctx.logger, "BOOT", "startup update check enabled")
    local ok, msg = ctx.performUpdateCheck("startup")
    ctx.state.message = ok and ("maj startup: " .. ctx.firstLine(msg)) or ("maj startup failed: " .. ctx.firstLine(msg))
    logInfo(ctx.logger, "BOOT", "startup update check completed", {
      ok = ok == true,
      status = tostring(ctx.state.update.remoteStatus or "n/a"),
    })
  end
  logInfo(ctx.logger, "BOOT", "first telemetry poll")
  ctx.pollLiveData(true)
  logInfo(ctx.logger, "BOOT", "first render")
  ctx.render()
  logInfo(ctx.logger, "BOOT", "startup initialize done")
end

return M
