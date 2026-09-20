# $HOME filesystem benchmark — macOS

Adapted run of the filesystem I/O benchmark from `run-filesystem-profile-tests.sh`
for a macOS host, where the original tooling does not apply:

- `powerprofilesctl` / TuneD / CPUFreq governors are Linux-only. macOS exposes only
  a single system-wide toggle, Low Power Mode (`pmset -a lowpowermode`), and setting
  it requires an interactive root password. That toggle could not be scripted
  non-interactively in this environment, so the power-profile comparison
  (power-saver / balanced / performance) was skipped by request. Low Power Mode
  was **off** for this run (see Environment below).
- Btrfs COW/NOCOW and a loopback XFS filesystem do not exist on macOS. `$HOME`
  is on APFS, so only that single filesystem was benchmarked, per request.
- `sysbench` is not available on macOS; `fio` (installed via Homebrew) was used
  instead with equivalent parameters.

## Method

- Tool: `fio`, `--ioengine=sync --direct=1 --sync=1 --iodepth=1`
- Block size: 1 MiB, test file size: 1 GiB
- Runtime: 4 seconds per run, time-based
- Repetitions: 3 per workload
- Workloads: sequential read, sequential write, random read
- Test directory: temporary subdirectory under `$HOME`, removed after the run

## Environment

| Item | Value |
|---|---|
| Host | Marauder (MacBook Pro, Apple M1 Pro, 32 GB) |
| macOS | 27.0 (build 26A428) |
| `$HOME` filesystem | APFS (`/dev/disk4s1`) |
| Low Power Mode | 0 (off) |
| Power source | AC Power |

## Results

| Test | Mean MiB/s | Stdev | Min | Max | Runs |
|---|---:|---:|---:|---:|---:|
| Sequential read | 2584.84 | 191.00 | 2364.90 | 2708.99 | 3 |
| Sequential write | 4537.54 | 214.35 | 4413.79 | 4785.05 | 3 |
| Random read | 2601.29 | 269.51 | 2290.83 | 2775.07 | 3 |

### Raw per-run values (MiB/s)

| Test | Run 1 | Run 2 | Run 3 |
|---|---:|---:|---:|
| Sequential read | 2364.90 | 2708.99 | 2680.63 |
| Sequential write | 4413.79 | 4413.79 | 4785.05 |
| Random read | 2290.83 | 2737.97 | 2775.07 |

## Caveats

- No power-profile comparison: only one power state (Low Power Mode off, AC
  power) was measured. The multi-profile / multi-filesystem comparison the
  original script performs is Linux-specific (Btrfs/XFS + power-profiles-daemon)
  and does not have a macOS equivalent for the profile dimension.
- APFS write-back and unified-memory caching behavior differs from Linux
  Btrfs/XFS; `direct=1`/`sync=1` on macOS map to `F_NOCACHE`, which is
  advisory rather than a hard bypass, so absolute numbers are not directly
  comparable to the Linux results produced by `run-filesystem-profile-tests.sh`.
