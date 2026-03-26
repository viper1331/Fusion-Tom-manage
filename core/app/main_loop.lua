local M = {}

local function onTouch(ctx, x, y)
  for _, btn in pairs(ctx.getButtons()) do
    if ctx.hit(btn, x, y) then
      ctx.handleAction(btn.id)
      ctx.render()
      return
    end
  end
end

function M.run(ctx)
  local timer = os.startTimer(ctx.refreshSeconds)

  while true do
    local event, p1, p2, p3 = os.pullEvent()

    if event == "timer" then
      if p1 == timer then
        ctx.render()
        timer = os.startTimer(ctx.refreshSeconds)
      elseif ctx.processPendingTimer(p1) then
        ctx.pollLiveData(true)
        ctx.render()
      end

    elseif event == "tm_monitor_touch" then
      onTouch(ctx, p2, p3)

    elseif event == "tm_monitor_resize" or event == "monitor_resize" or event == "term_resize" then
      if type(ctx.handleResize) == "function" then
        ctx.handleResize(event, p1, p2, p3)
      else
        ctx.render()
      end

    elseif event == "peripheral" or event == "peripheral_detach" then
      ctx.invalidateWrapped(p1)
      ctx.pollLiveData(true)
      ctx.render()

    elseif event == "fusion_restart" then
      break

    elseif event == "key_up" and p1 == keys.t then
      break
    end
  end
end

return M
