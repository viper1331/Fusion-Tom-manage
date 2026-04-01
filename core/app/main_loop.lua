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

local function logLoopEvent(ctx, event, context, force)
  if not ctx.logger then
    return
  end

  if force or ctx.loopEventDebug then
    logWithLevel(ctx.logger, "debug", "LOOP", "main loop event", {
      event = tostring(event),
      context = context,
    })
  end
end

local function onTouch(ctx, x, y)
  logWithLevel(ctx.logger, "info", "INPUT", "touch event received", {
    x = tonumber(x),
    y = tonumber(y),
  })

  for _, btn in pairs(ctx.getButtons()) do
    if ctx.hit(btn, x, y) then
      logWithLevel(ctx.logger, "info", "INPUT", "button hit", {
        id = tostring(btn.id),
        x = tonumber(x),
        y = tonumber(y),
      })
      ctx.handleAction(btn.id)
      ctx.render()
      return
    end
  end

  logWithLevel(ctx.logger, "debug", "INPUT", "touch without hit", {
    x = tonumber(x),
    y = tonumber(y),
  })
end

function M.run(ctx)
  local timer = os.startTimer(ctx.refreshSeconds)
  logWithLevel(ctx.logger, "info", "LOOP", "main loop started", {
    refreshSeconds = tostring(ctx.refreshSeconds),
    timer = tostring(timer),
  })

  while true do
    local event, p1, p2, p3 = os.pullEvent()
    logLoopEvent(ctx, event, {
      p1 = tostring(p1),
      p2 = tostring(p2),
      p3 = tostring(p3),
    }, false)

    if event == "timer" then
      if p1 == timer then
        if ctx.loopEventDebug and ctx.logger and type(ctx.logger.throttle) == "function" then
          ctx.logger.throttle("loop.timer.refresh", 10000, "DEBUG", "LOOP", "refresh timer fired", {
            timer = tostring(p1),
          }, "runtime")
        end
        ctx.render()
        timer = os.startTimer(ctx.refreshSeconds)
      elseif ctx.processPendingTimer(p1) then
        logWithLevel(ctx.logger, "info", "LOOP", "pending timer processed", {
          timer = tostring(p1),
        })
        ctx.pollLiveData(true)
        ctx.render()
      end

    elseif event == "tm_monitor_touch" then
      onTouch(ctx, p2, p3)

    elseif event == "tm_monitor_resize" or event == "monitor_resize" or event == "term_resize" then
      logWithLevel(ctx.logger, "info", "INPUT", "resize event", {
        event = tostring(event),
        p1 = tostring(p1),
        p2 = tostring(p2),
        p3 = tostring(p3),
      })
      if type(ctx.handleResize) == "function" then
        ctx.handleResize(event, p1, p2, p3)
      else
        ctx.render()
      end

    elseif event == "peripheral" or event == "peripheral_detach" then
      logWithLevel(ctx.logger, "warn", "LOOP", "peripheral topology changed", {
        event = tostring(event),
        name = tostring(p1),
      })
      ctx.invalidateWrapped(p1)
      ctx.pollLiveData(true)
      ctx.render()

    elseif event == "fusion_restart" then
      logWithLevel(ctx.logger, "info", "LOOP", "fusion restart event received")
      break

    elseif event == "key_up" and p1 == keys.t then
      logWithLevel(ctx.logger, "warn", "INPUT", "manual exit key received", {
        key = "t",
      })
      break
    end
  end

  logWithLevel(ctx.logger, "info", "LOOP", "main loop stopped")
end

return M
