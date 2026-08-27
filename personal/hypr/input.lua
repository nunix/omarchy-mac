-- Personal MacBook touchpad overrides for Omarchy.

-- Mac-style scrolling and typing lockout.
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
      disable_while_typing = true,
    },
  },
})

-- Mac-style workspace direction with a wrapping carousel.
hl.gesture({
  fingers = 3,
  direction = "left",
  action = function()
    os.execute("~/.config/hypr/scripts/workspace-carousel right >/dev/null 2>&1 &")
  end,
})
hl.gesture({
  fingers = 3,
  direction = "right",
  action = function()
    os.execute("~/.config/hypr/scripts/workspace-carousel left >/dev/null 2>&1 &")
  end,
})
