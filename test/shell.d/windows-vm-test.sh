#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

windows_vm_command="$ROOT/bin/omarchy-windows-vm"
windows_vm_rules="$ROOT/default/hypr/apps/windows-vm.lua"

rg -q 'IMAGE=docker.io/dockurr/windows-arm:latest' "$windows_vm_command" ||
  fail "Windows VM selects the tagged ARM64 Dockurr image"
rg -q 'WINDOWS_VERSION=11e' "$windows_vm_command" ||
  fail "Windows VM selects the ARM64 Enterprise Evaluation edition"
rg -q 'QEMU_COMMAND=qemu-system-aarch64' "$windows_vm_command" ||
  fail "Windows VM checks for the ARM64 QEMU binary"
rg -q 'omarchy-pkg-add qemu-base docker docker-compose.*remmina' "$windows_vm_command" ||
  fail "Windows VM installs the QEMU/KVM, Docker, and Remmina prerequisites"
rg -q 'REMMINA_PROFILE=' "$windows_vm_command" ||
  fail "Windows VM defines a Remmina connection profile"
rg -q -- '--remmina' "$windows_vm_command" ||
  fail "Windows VM exposes a Remmina launch option"
pass "Windows VM uses the tagged ARM64 Enterprise Evaluation image and Remmina"

rg -q '^    restart: "no"$' "$windows_vm_command" ||
  fail "Windows VM uses manual startup by default"
pass "Windows VM uses manual startup by default"

if rg -q '^    restart: unless-stopped$' "$windows_vm_command"; then
  fail "Windows VM does not restart automatically at boot"
fi
pass "Windows VM does not restart automatically at boot"

# Tolerate either shell quoting of the argument -- what must not drift is the
# title itself, since the Hyprland rule below matches on it.
rg -q 'title:"?Windows VM - Omarchy"' "$windows_vm_command" ||
  fail "Windows VM launches FreeRDP with its expected title"
rg -q 'class = "\^xfreerdp\$", title = "\^Windows VM - Omarchy\$"' "$windows_vm_rules" ||
  fail "Windows VM opacity rule targets its FreeRDP window"
rg -q 'tag = "-default-opacity"' "$windows_vm_rules" ||
  fail "Windows VM opts out of default opacity"
rg -q 'opacity = "1 1"' "$windows_vm_rules" ||
  fail "Windows VM stays fully opaque"
pass "Windows VM stays fully opaque"
