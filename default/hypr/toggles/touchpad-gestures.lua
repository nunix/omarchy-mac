-- Swipe horizontally with three fingers through the workspace carousel, like
-- swiping between full-screen apps on macOS. Keep one empty workspace after
-- the last occupied workspace, cap the carousel at 5, and wrap back to 1.
local swipe_direction
hl.gesture({
  fingers = 3,
  direction = "horizontal",
  action = {
    start = function(event)
      swipe_direction = ({ LEFT = "next", RIGHT = "previous" })[event.direction]
    end,
    finish = function(event)
      if event.cancelled or not swipe_direction then
        swipe_direction = nil
        return
      end

      local direction = swipe_direction
      swipe_direction = nil
      hl.dispatch(hl.dsp.exec_cmd("omarchy-hyprland-workspace-carousel " .. direction))
    end,
  },
})
