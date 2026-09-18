#!/bin/bash
# Activate and verify the system's power-profiles-daemon performance profile.
# This intentionally uses the profile API instead of writing CPUFreq sysfs files.
set -Eeuo pipefail
export LC_ALL=C

if ! command -v powerprofilesctl >/dev/null 2>&1; then
  echo "error: powerprofilesctl is not installed" >&2
  exit 1
fi

if ! powerprofilesctl list 2>/dev/null | grep -Eq '^[[:space:]*]*performance:'; then
  echo "error: the performance profile is not advertised by the active backend" >&2
  echo >&2
  powerprofilesctl list >&2 || true
  echo >&2
  echo "Install/configure a backend that supports performance (for example tuned-ppd)," >&2
  echo "then run this script again." >&2
  exit 2
fi

echo "Setting the active power profile to performance..."
powerprofilesctl set performance

# Give a backend such as tuned-ppd time to apply the CPU policy.
for _ in {1..20}; do
  [[ "$(powerprofilesctl get)" == "performance" ]] && break
  sleep 0.25
done

if [[ "$(powerprofilesctl get)" != "performance" ]]; then
  echo "error: the backend did not activate performance" >&2
  exit 3
fi

echo "Active profile: $(powerprofilesctl get)"
if command -v tuned-adm >/dev/null 2>&1; then
  tuned-adm active || true
fi

echo "CPUFreq governors:"
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
  printf '  %s: %s\n' "$(basename "$policy")" "$(<"$policy/scaling_governor")"
done
