#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command lua

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
home_dir="$tmpdir/home"
log_file="$tmpdir/hyprctl.log"
mkdir -p "$stub_dir" "$home_dir"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash

if [[ $1 == reload ]]; then
  printf 'reload\n' >>"$HYPRCTL_LOG"
  if [[ ${HYPRCTL_RELOAD_FAIL:-0} == 1 ]]; then
    exit 1
  fi
fi
EOF
chmod +x "$stub_dir/hyprctl"

cat >"$stub_dir/omarchy-notification-send" <<'EOF'
#!/bin/bash
:
EOF
chmod +x "$stub_dir/omarchy-notification-send"

run_toggle() {
  HOME="$home_dir" \
    OMARCHY_PATH="$ROOT" \
    HYPRCTL_LOG="$log_file" \
    PATH="$stub_dir:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-toggle-touchpad-gestures" "$@"
}

flag="$home_dir/.local/state/omarchy/toggles/hypr/touchpad-gestures.lua"

run_toggle on
[[ -f $flag ]] || fail "touchpad gesture toggle enables the flag"
grep -Fq 'fingers = 3' "$flag" || fail "enabled gesture flag contains the three-finger gesture"
pass "touchpad gesture toggle enables the flag"

run_toggle on
[[ -f $flag ]] || fail "touchpad gesture toggle on is idempotent"
pass "touchpad gesture toggle on is idempotent"

run_toggle off
[[ ! -e $flag ]] || fail "touchpad gesture toggle disables the flag"
pass "touchpad gesture toggle disables the flag"

run_toggle toggle
[[ -f $flag ]] || fail "touchpad gesture toggle creates the flag"
run_toggle toggle
[[ ! -e $flag ]] || fail "touchpad gesture toggle removes the flag"
pass "touchpad gesture toggle persists on/off state"

set +e
run_toggle invalid >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "touchpad gesture toggle rejects invalid actions"
[[ ! -e $flag ]] || fail "invalid touchpad gesture action does not enable the flag"
pass "touchpad gesture toggle rejects invalid actions"

set +e
HYPRCTL_RELOAD_FAIL=1 run_toggle on >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "touchpad gesture toggle reports a reload failure"
[[ -f $flag ]] || fail "touchpad gesture toggle keeps the requested flag when reload fails"
pass "touchpad gesture toggle reports a reload failure"

HOME="$home_dir" OMARCHY_PATH="$ROOT" lua - <<'LUA'
local gestures = {}
local dispatches = {}

hl = {
  gesture = function(options)
    table.insert(gestures, options)
  end,
  dispatch = function(dispatcher)
    table.insert(dispatches, dispatcher)
  end,
  dsp = {
    exec_cmd = function(command)
      return command
    end,
  },
}

dofile(os.getenv("OMARCHY_PATH") .. "/default/hypr/toggles/touchpad-gestures.lua")
assert(#gestures == 1, "the toggle registers one gesture")
assert(gestures[1].fingers == 3, "the toggle registers a three-finger gesture")
assert(gestures[1].direction == "horizontal", "the toggle registers a horizontal gesture")
assert(type(gestures[1].action.start) == "function", "the gesture records its direction at start")
assert(type(gestures[1].action.finish) == "function", "the gesture dispatches at finish")

gestures[1].action.start({ direction = "LEFT" })
gestures[1].action.finish({ cancelled = false })
assert(dispatches[1] == "omarchy-hyprland-workspace-carousel next", "a left swipe moves to the next carousel workspace")

gestures[1].action.start({ direction = "RIGHT" })
gestures[1].action.finish({ cancelled = true })
assert(#dispatches == 1, "a cancelled swipe does not switch workspaces")
LUA
pass "touchpad gesture direction and cancellation handling are correct"
