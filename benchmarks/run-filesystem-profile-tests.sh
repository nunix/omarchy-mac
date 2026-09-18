#!/bin/bash
# Run the same low-queue-depth file-I/O tests on Btrfs COW, Btrfs NOCOW,
# and a temporary XFS filesystem under all three power profiles.
#
# Usage:
#   ./run-filesystem-profile-tests.sh [output-directory]
#
# The output directory must be on Btrfs because the NOCOW and XFS-backed-image
# comparisons are part of this test. The temporary filesystems are removed
# automatically; CSV, raw logs, and summary.md are retained.
set -Eeuo pipefail
export LC_ALL=C

OUTPUT_DIR="${1:-$PWD/profile-io-results-$(date +%Y%m%d-%H%M%S)}"
OUTPUT_DIR=$(realpath -m "$OUTPUT_DIR")
WORK_DIR="$OUTPUT_DIR/work"
RAW_DIR="$OUTPUT_DIR/raw"
CSV="$OUTPUT_DIR/results.csv"
SUMMARY="$OUTPUT_DIR/summary.md"

RUNS="${RUNS:-3}"
IO_TIME="${IO_TIME:-4}"
TEST_FILE_SIZE="${TEST_FILE_SIZE:-1G}"
XFS_IMAGE_SIZE="${XFS_IMAGE_SIZE:-4G}"

PROFILES=(power-saver balanced performance)
ORDERS=(
  "power-saver balanced performance"
  "performance balanced power-saver"
  "balanced power-saver performance"
)
TESTS=(
  "seq_read seqrd read, MiB/s"
  "seq_write seqwr written, MiB/s"
  "random_read rndrd read, MiB/s"
)

# Refuse dangerous cleanup paths.
case "$WORK_DIR" in
  ""|/|"$HOME"|"$HOME/")
    echo "error: refusing to use a dangerous work path: $WORK_DIR" >&2
    exit 1
    ;;
esac

need_command() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command is missing: $1" >&2
    exit 1
  }
}

for command in powerprofilesctl sysbench findmnt mountpoint realpath chattr fallocate mkfs.xfs xfs_info python3; do
  need_command "$command"
done

if (( EUID == 0 )); then
  SUDO=()
else
  SUDO=(sudo)
fi

as_root() {
  "${SUDO[@]}" "$@"
}

mkdir -p "$OUTPUT_DIR" "$RAW_DIR" "$WORK_DIR"

if [[ "$(findmnt -no FSTYPE -T "$OUTPUT_DIR")" != btrfs ]]; then
  echo "error: $OUTPUT_DIR is not on Btrfs; choose an output directory under a Btrfs mount" >&2
  exit 1
fi

for profile in "${PROFILES[@]}"; do
  if ! powerprofilesctl list 2>/dev/null | grep -Eq "^[[:space:]*]*${profile}:"; then
    echo "error: profile is unavailable: $profile" >&2
    powerprofilesctl list >&2 || true
    exit 2
  fi
done

ORIGINAL_PROFILE=$(powerprofilesctl get)
MOUNTED=0

COW_DIR="$WORK_DIR/btrfs-cow"
NOCOW_DIR="$WORK_DIR/btrfs-nocow"
XFS_CONTAINER="$WORK_DIR/xfs-container"
XFS_IMAGE="$XFS_CONTAINER/xfs-test.img"
XFS_DIR="$WORK_DIR/xfs"

cleanup() {
  set +e
  # Remove sysbench's test files while each filesystem is still accessible.
  for directory in "$COW_DIR" "$NOCOW_DIR" "$XFS_DIR"; do
    if [[ -d "$directory" ]]; then
      (
        cd "$directory"
        sysbench fileio \
          --file-total-size="$TEST_FILE_SIZE" --file-num=1 --file-block-size=1M \
          --file-io-mode=sync --file-extra-flags=direct --file-fsync-freq=0 \
          cleanup
      ) >"$RAW_DIR/cleanup-$(basename "$directory").log" 2>&1 || true
    fi
  done

  if (( MOUNTED )); then
    as_root umount "$XFS_DIR" >/dev/null 2>&1 || as_root umount -l "$XFS_DIR" >/dev/null 2>&1 || true
  fi

  if mountpoint -q "$XFS_DIR" 2>/dev/null; then
    echo "warning: XFS is still mounted; leaving work directory in place: $WORK_DIR" >&2
  else
    rm -rf "$WORK_DIR"
  fi
  powerprofilesctl set "$ORIGINAL_PROFILE" >/dev/null 2>&1 || true
}
trap cleanup EXIT INT TERM

profile_state() {
  local governors tuned_profile
  governors=$(for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    printf '%s:%s;' "$(basename "$policy")" "$(<"$policy/scaling_governor")"
  done)
  if command -v tuned-adm >/dev/null 2>&1; then
    tuned_profile=$(tuned-adm active 2>/dev/null | sed -n 's/^Current active profile: //p')
  else
    tuned_profile=""
  fi
  printf '%s\t%s\t%s\n' \
    "$governors" \
    "$(< /sys/devices/system/cpu/cpufreq/boost)" \
    "$tuned_profile"
}

activate_profile() {
  local requested="$1"
  powerprofilesctl set "$requested" >/dev/null
  for _ in {1..20}; do
    [[ "$(powerprofilesctl get)" == "$requested" ]] && break
    sleep 0.25
  done
  [[ "$(powerprofilesctl get)" == "$requested" ]] || {
    echo "error: could not activate profile $requested" >&2
    return 1
  }
  # Allow the backend to finish applying its governor/policy changes.
  sleep 1
}

prepare_directory() {
  local name="$1" directory="$2"
  mkdir -p "$directory"
  if [[ "$name" == btrfs-nocow ]]; then
    chattr +C "$directory"
    lsattr -d "$directory" >"$RAW_DIR/${name}-attributes.txt"
  fi
  (
    cd "$directory"
    sysbench fileio \
      --file-total-size="$TEST_FILE_SIZE" --file-num=1 --file-block-size=1M \
      --file-io-mode=sync --file-extra-flags=direct --file-fsync-freq=0 prepare
  ) >"$RAW_DIR/prepare-${name}.log" 2>&1
}

# Prepare the normal and NOCOW Btrfs directories.
prepare_directory btrfs-cow "$COW_DIR"
prepare_directory btrfs-nocow "$NOCOW_DIR"

# Create and mount a temporary XFS filesystem. The backing image is NOCOW so
# host-Btrfs compression/COW is not part of the XFS comparison.
mkdir -p "$XFS_CONTAINER" "$XFS_DIR"
chattr +C "$XFS_CONTAINER"
lsattr -d "$XFS_CONTAINER" >"$RAW_DIR/xfs-backing-attributes.txt"
fallocate -l "$XFS_IMAGE_SIZE" "$XFS_IMAGE"
as_root mkfs.xfs -f -m reflink=0 "$XFS_IMAGE" >"$RAW_DIR/xfs-mkfs.log" 2>&1
as_root mount -o loop,noatime,nosuid,nodev "$XFS_IMAGE" "$XFS_DIR"
MOUNTED=1
as_root chown "$(id -u):$(id -g)" "$XFS_DIR"
findmnt -T "$XFS_DIR" >"$RAW_DIR/xfs-mount.txt"
as_root xfs_info "$XFS_DIR" >"$RAW_DIR/xfs-info.txt" 2>&1
(
  cd "$XFS_DIR"
  sysbench fileio \
    --file-total-size="$TEST_FILE_SIZE" --file-num=1 --file-block-size=1M \
    --file-io-mode=sync --file-extra-flags=direct --file-fsync-freq=0 prepare
) >"$RAW_DIR/prepare-xfs.log" 2>&1

printf 'filesystem,profile,test,run,value_mib_s,governors,boost,tuned_profile\n' >"$CSV"

declare -A DIRECTORY=(
  [btrfs-cow]="$COW_DIR"
  [btrfs-nocow]="$NOCOW_DIR"
  [xfs]="$XFS_DIR"
)

run_test() {
  local filesystem="$1" profile="$2" test="$3" run="$4" mode="$5" metric="$6"
  local directory="${DIRECTORY[$filesystem]}"
  local log="$RAW_DIR/run${run}_${filesystem}_${profile}_${test}.log"
  local value governors boost tuned_profile

  (
    cd "$directory"
    sysbench fileio \
      --file-total-size="$TEST_FILE_SIZE" --file-num=1 --file-block-size=1M \
      --file-io-mode=sync --file-extra-flags=direct --file-fsync-freq=0 \
      --file-test-mode="$mode" --time="$IO_TIME" run
  ) >"$log" 2>&1

  value=$(awk -F: -v metric="$metric" '$1 ~ metric {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$log")
  [[ -n "$value" ]] || {
    echo "error: could not parse $log" >&2
    return 1
  }

  IFS=$'\t' read -r governors boost tuned_profile < <(profile_state)
  printf '%s,%s,%s,%s,%s,"%s",%s,%s\n' \
    "$filesystem" "$profile" "$test" "$run" "$value" \
    "$governors" "$boost" "$tuned_profile" >>"$CSV"
  printf '  %-11s %-12s %-18s run %d: %s MiB/s\n' \
    "$filesystem" "$profile" "$test" "$run" "$value"
}

printf 'Running %d repetitions per filesystem/profile/test...\n' "$RUNS"
for ((run=1; run<=RUNS; run++)); do
  read -r -a order <<<"${ORDERS[$(( (run - 1) % ${#ORDERS[@]} ))]}"
  printf '\n=== repetition %d; profile order: %s ===\n' "$run" "${order[*]}"
  for filesystem in btrfs-cow btrfs-nocow xfs; do
    for spec in "${TESTS[@]}"; do
      read -r test mode metric <<<"$spec"
      for profile in "${order[@]}"; do
        activate_profile "$profile"
        run_test "$filesystem" "$profile" "$test" "$run" "$mode" "$metric"
      done
    done
  done
done

# Produce a small Markdown summary in addition to the raw CSV.
python3 - "$CSV" "$SUMMARY" <<'PY'
import csv
import statistics
import sys
from collections import defaultdict

source, output = sys.argv[1:]
values = defaultdict(list)
with open(source, newline="") as f:
    for row in csv.DictReader(f):
        values[(row["filesystem"], row["test"], row["profile"])].append(float(row["value_mib_s"]))

filesystems = ["btrfs-cow", "btrfs-nocow", "xfs"]
profiles = ["power-saver", "balanced", "performance"]
tests = ["seq_read", "seq_write", "random_read"]
labels = {"btrfs-cow": "Btrfs COW", "btrfs-nocow": "Btrfs NOCOW", "xfs": "XFS"}
with open(output, "w") as out:
    out.write("# Filesystem/profile I/O summary\n\n")
    out.write("Means are MiB/s from the configured repetitions; `±` is one standard deviation.\n\n")
    out.write("| Filesystem | Test | Power-saver | Balanced | Performance | Performance vs balanced |\n")
    out.write("|---|---|---:|---:|---:|---:|\n")
    for fs in filesystems:
        for test in tests:
            means = {}
            for profile in profiles:
                vals = values[(fs, test, profile)]
                means[profile] = (statistics.mean(vals), statistics.stdev(vals) if len(vals) > 1 else 0.0)
            delta = 100 * means["performance"][0] / means["balanced"][0] - 100
            out.write(
                f"| {labels[fs]} | {test.replace('_', ' ')} | "
                f"{means['power-saver'][0]:,.2f} ± {means['power-saver'][1]:,.2f} | "
                f"{means['balanced'][0]:,.2f} ± {means['balanced'][1]:,.2f} | "
                f"{means['performance'][0]:,.2f} ± {means['performance'][1]:,.2f} | "
                f"{'+' if delta >= 0 else ''}{delta:.2f}% |\n"
            )
PY

printf '\nCSV: %s\nSummary: %s\n' "$CSV" "$SUMMARY"
