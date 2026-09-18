#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

stub_dir="$tmpdir/bin"
log_file="$tmpdir/dispatch.log"
mkdir -p "$stub_dir"

cat >"$stub_dir/hyprctl" <<'EOF'
#!/bin/bash

case $1 in
  activeworkspace)
    printf '%s\n' "$ACTIVE_WORKSPACE_JSON"
    ;;
  workspaces)
    printf '%s\n' "$WORKSPACES_JSON"
    ;;
  dispatch)
    printf '%s\n' "$2" >>"$DISPATCH_LOG"
    ;;
  *)
    echo "unexpected hyprctl command: $*" >&2
    exit 1
    ;;
esac
EOF
chmod +x "$stub_dir/hyprctl"

workspaces_1_to_3='[
  {"id":1,"name":"1","monitor":"eDP-1","windows":1},
  {"id":2,"name":"2","monitor":"eDP-1","windows":1},
  {"id":3,"name":"3","monitor":"eDP-1","windows":1},
  {"id":5,"name":"5","monitor":"HDMI-A-1","windows":1}
]'
workspaces_1_to_5='[
  {"id":1,"name":"1","monitor":"eDP-1","windows":1},
  {"id":2,"name":"2","monitor":"eDP-1","windows":1},
  {"id":3,"name":"3","monitor":"eDP-1","windows":1},
  {"id":4,"name":"4","monitor":"eDP-1","windows":1},
  {"id":5,"name":"5","monitor":"eDP-1","windows":1}
]'

run_carousel() {
  local direction="$1"
  local current="$2"
  local workspaces="$3"

  : >"$log_file"
  ACTIVE_WORKSPACE_JSON=$(printf '{"id":%s,"name":"%s","monitor":"eDP-1"}' "$current" "$current") \
    WORKSPACES_JSON="$workspaces" \
    DISPATCH_LOG="$log_file" \
    PATH="$stub_dir:$PATH" \
    "$ROOT/bin/omarchy-hyprland-workspace-carousel" "$direction"
}

assert_target() {
  local direction="$1"
  local current="$2"
  local workspaces="$3"
  local target="$4"

  run_carousel "$direction" "$current" "$workspaces"
  grep -Fxq "hl.dsp.focus({ workspace = \"$target\", on_current_monitor = true })" "$log_file" ||
    fail "workspace carousel targets workspace $target" "$(<"$log_file")"
  pass "workspace carousel targets workspace $target"
}

assert_target next 3 "$workspaces_1_to_3" 4
assert_target previous 1 "$workspaces_1_to_3" 4
assert_target next 4 "$workspaces_1_to_3" 1
assert_target previous 1 "$workspaces_1_to_5" 5
assert_target next 5 "$workspaces_1_to_5" 1

set +e
PATH="$stub_dir:$PATH" "$ROOT/bin/omarchy-hyprland-workspace-carousel" sideways >/dev/null 2>&1
status=$?
set -e
(( status != 0 )) || fail "workspace carousel rejects invalid directions"
pass "workspace carousel rejects invalid directions"
