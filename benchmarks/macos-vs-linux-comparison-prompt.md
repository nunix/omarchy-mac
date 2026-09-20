# Cross-agent comparison request: macOS $HOME fio benchmark vs Linux profile-perf results

## Context

Branch `profile-perf` in https://github.com/nunix/omarchy-mac already contains
the Linux implementation:

- `benchmarks/activate-performance.sh`
- `benchmarks/run-filesystem-profile-tests.sh`
- `benchmarks/profile-perf-agent-prompt.md`

The `$HOME` filesystem I/O test was also run on macOS (Marauder, Apple M1 Pro,
32 GB, macOS 27.0 build 26A428), since the Linux scripts are Linux-only
(`powerprofilesctl`, Btrfs/XFS, `chattr`, `mkfs.xfs`). Results are committed at:

- commit `fe6e83c2`, branch `profile-perf`
- `benchmarks/home-fs-benchmark-macos.md`

## What was actually run

1. **Tool substitution**: `sysbench` is not packaged for macOS. Installed fio
   3.42 via `brew install fio` and used it instead, matching the sysbench
   parameters as closely as fio allows.

2. **Power-profile substitution**: `powerprofilesctl` / TuneD / CPUFreq
   governors do not exist on macOS. The only analogous system-wide toggle is
   Low Power Mode (`pmset -a lowpowermode 0|1`), and setting it requires an
   interactive root password — no non-interactive/passwordless sudo path was
   available in the execution environment, and sudo tickets don't carry
   across tty/process boundaries in the tool used to run commands. Per
   explicit instruction from the operator (nunix), the power-profile
   comparison dimension was skipped entirely rather than mocked. Low Power
   Mode was OFF for the whole run (`pmset -g custom` → `lowpowermode 0`), on
   AC power.

3. **Filesystem scope**: Btrfs COW/NOCOW and loopback XFS don't exist on
   macOS. `$HOME` here is a single APFS volume (`/dev/disk4s1`). Per operator
   instruction, only that one filesystem was benchmarked — no multi-fs
   matrix.

4. **Exact fio invocation per workload/repetition**:

   ```bash
   fio --name="$test" --directory="$WORK_DIR" --rw="$rw" --bs=1m \
       --size=1G --io_size=1G \
       --direct=1 --sync=1 --ioengine=sync --iodepth=1 \
       --runtime=4 --time_based=0 --group_reporting \
       --output-format=json --output="$log"
   ```

   where `$rw` was `read`, `write`, `randread` for the three workloads
   (`seq_read`, `seq_write`, `random_read`). Same block size (1 MiB), file
   size (1 GiB), and per-run duration (4s) as the sysbench spec. 3
   repetitions per workload, same as the script's default `RUNS=3`.

   Note: on macOS, fio's `--direct=1`/`--sync=1` map to `F_NOCACHE`, which is
   advisory (unlike Linux `O_DIRECT`). Throughput numbers are therefore not
   strictly apples-to-apples with the Linux `O_DIRECT` results — flag this in
   any comparison rather than treating deltas as pure hardware/profile
   effects.

5. **Test directory**: temporary subdir under `$HOME`
   (`$HOME/.profile-io-bench-$$`), removed via trap on exit — never touched
   real user files, matching the Linux script's safety pattern.

6. **Metrics captured per run**: MiB/s throughput (parsed from fio's JSON
   output, `jobs[0][read|write].bw` converted from KiB/s to MiB/s), plus
   environment metadata (fstype, device node, lowpowermode value, power
   source, chip).

## Results (means over 3 runs, MiB/s)

| Test              | Mean    | Stdev  | Min     | Max     |
|-------------------|--------:|-------:|--------:|--------:|
| Sequential read   | 2584.84 | 191.00 | 2364.90 | 2708.99 |
| Sequential write  | 4537.54 | 214.35 | 4413.79 | 4785.05 |
| Random read       | 2601.29 | 269.51 | 2290.83 | 2775.07 |

Full raw per-run values and environment table are in
`benchmarks/home-fs-benchmark-macos.md` on `profile-perf`.

## Ask

Compare against the Btrfs/XFS results at each power profile. Since there's no
macOS "performance"/"balanced"/"power-saver" axis, treat the macOS numbers as
a single reference point (Low Power Mode off, AC power) rather than a third
profile column. Flag if the `O_DIRECT` vs `F_NOCACHE` semantic gap makes the
comparison not worth drawing conclusions from.
