# Mac-like Touchpad Gestures on Omarchy

Omarchy uses Hyprland and libinput. These personal overrides provide Mac-like scrolling, workspace swipes, typing lockout, and palm rejection without editing the packaged files.

## Natural two-finger scrolling

In `~/.config/hypr/input.lua`, set:

```lua
hl.config({
  input = {
    touchpad = {
      natural_scroll = true,
      disable_while_typing = true,
    },
  },
})
```

`natural_scroll = true` makes content follow the fingers, as on macOS.

## Mac-like three-finger workspace swipes

Hyprland's basic gesture is:

```lua
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

For a wrapping carousel that includes enabled workspaces plus one empty workspace, use directional callbacks instead:

```lua
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
```

The directions are intentionally reversed: swiping left moves to the next workspace, matching macOS. The script cycles through workspaces containing windows and one additional empty workspace, capped at workspace 5. It wraps at both ends and skips empty gaps. The callback must run asynchronously because invoking `hyprctl` synchronously from a Hyprland gesture callback blocks Hyprland's event loop and can temporarily freeze input.

Reload and validate:

```sh
hyprctl reload
hyprctl configerrors
```

## Typing lockout and palm rejection

`disable_while_typing = true` prevents touchpad pointer motion while keyboard input is being entered. This is the most useful protection against palm movement while typing.

Palm rejection itself is provided by libinput, not by a separate Hyprland gesture setting. Supported Apple USB trackpads are covered by libinput's installed Apple quirk, which applies palm-size filtering automatically:

```sh
udevadm info --query=property --name=/dev/input/event7 \
  | grep -E 'ID_INPUT_TOUCHPAD|ID_VENDOR|ID_MODEL'
```

Do not edit `/usr/share/libinput/` or `/usr/share/omarchy/`; package updates overwrite those files. If palm filtering remains inadequate, investigate a device-specific libinput quirk rather than adding another gesture daemon.

These settings do not change pointer sensitivity, so they remain suitable for high-DPI/Retina displays.
