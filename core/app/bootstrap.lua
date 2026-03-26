local M = {}

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
    },
    router = {
      state = args.state,
      pageExists = args.pageExists,
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
    },
  }
end

function M.initialize(ctx)
  ctx.buildUI()
  ctx.tryLoadAssets()
  ctx.refreshLocalUpdateSnapshot()
  ctx.loadUpdateLogTail(12)
  if ctx.updateCfg.autoCheckOnStartup then
    local ok, msg = ctx.performUpdateCheck("startup")
    ctx.state.message = ok and ("maj startup: " .. ctx.firstLine(msg)) or ("maj startup failed: " .. ctx.firstLine(msg))
  end
  ctx.pollLiveData(true)
  ctx.render()
end

return M
