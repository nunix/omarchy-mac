# Agent request: power-profile filesystem benchmarks

You are working on my fork of Omarchy Mac:

```text
https://github.com/nunix/omarchy-mac
```

Create or use the branch:

```text
profile-perf
```

Implement and commit these two maintainer-facing benchmark scripts:

```text
benchmarks/activate-performance.sh
benchmarks/run-filesystem-profile-tests.sh
```

Do not modify Omarchy runtime configuration, `/usr/share/omarchy`, `/home` globally, or existing unrelated work.

## Script 1: `benchmarks/activate-performance.sh`

Create a small executable Bash script that:

1. Requires `powerprofilesctl`.
2. Checks that the active backend advertises the `performance` profile.
3. Activates it with:

   ```bash
   powerprofilesctl set performance
   ```

4. Waits briefly for the backend to apply the change.
5. Verifies that the active profile is actually `performance`.
6. Prints the active power profile, the TuneD profile if `tuned-adm` is available, and the CPUFreq governor for every CPU policy.
7. Exits nonzero with a useful diagnostic if performance is unavailable or cannot be activated.
8. Uses the profile API only. Do not write directly to CPUFreq sysfs files.
9. Uses `#!/bin/bash`, `set -Eeuo pipefail`, and is executable.

Expected invocation:

```bash
./benchmarks/activate-performance.sh
```

## Script 2: `benchmarks/run-filesystem-profile-tests.sh`

Create an executable script that compares the three profiles across these filesystem layouts:

1. Normal Btrfs COW directory.
2. Fresh Btrfs NOCOW directory created with `chattr +C`.
3. Temporary XFS filesystem mounted from a loopback image.

The output directory must be on Btrfs. Fail clearly if it is not.

The script must:

1. Require `powerprofilesctl`, `sysbench`, `mkfs.xfs`, `xfs_info`, `fallocate`, `chattr`, `findmnt`, `mountpoint`, `python3`, and `sudo` when not run as root.
2. Verify that all three profiles are available: `power-saver`, `balanced`, and `performance`.
3. Save the currently active profile and restore it on every exit path.
4. Create temporary work areas under the selected output directory:

   ```text
   work/btrfs-cow
   work/btrfs-nocow
   work/xfs-container
   work/xfs
   ```

5. For Btrfs NOCOW, apply `chattr +C` before creating the test file. Do not change `/home` or any existing user files.
6. For XFS:
   - Allocate a temporary 4 GiB image with `fallocate`.
   - Store the image in a NOCOW backing directory.
   - Format it with `mkfs.xfs -f -m reflink=0`.
   - Mount it with `noatime,nosuid,nodev`.
   - Record `findmnt` and `xfs_info` output.
   - Use `sudo` only for formatting, mounting, ownership changes, and unmounting.
   - Unmount and delete the image during cleanup.
7. Run these sysbench file-I/O workloads on every filesystem:
   - sequential read: `seqrd`
   - sequential write: `seqwr`
   - random read: `rndrd`
8. Use one 1 GiB test file, 1 MiB blocks, synchronous I/O, direct I/O, `--file-fsync-freq=0`, 4 seconds per run, and three repetitions by default.
9. Run every workload under `power-saver`, `balanced`, and `performance`.
10. Rotate profile order between repetitions to reduce ordering and thermal bias.
11. Capture the actual state for every result: filesystem, profile, test, repetition, throughput in MiB/s, CPU governors, boost flag, and TuneD profile if available.
12. Write `results.csv`, `summary.md`, and raw logs under `raw/`.
13. Use traps so interrupted runs remove sysbench test files, unmount XFS, remove temporary filesystems/images, and restore the original power profile.
14. Never recursively delete an XFS mount while it is still mounted. Check with `mountpoint` before removing the work directory.
15. Support these optional environment variables:

   ```text
   RUNS
   IO_TIME
   TEST_FILE_SIZE
   XFS_IMAGE_SIZE
   ```

Expected invocation:

```bash
./benchmarks/run-filesystem-profile-tests.sh \
  "$HOME/profile-io-results-$(date +%Y%m%d-%H%M%S)"
```

## Validation

Run:

```bash
bash -n benchmarks/activate-performance.sh
bash -n benchmarks/run-filesystem-profile-tests.sh
git diff --check
```

Run a short smoke test using reduced values:

```bash
smoke_dir="$HOME/profile-script-smoke-$$"

RUNS=1 \
IO_TIME=1 \
TEST_FILE_SIZE=128M \
XFS_IMAGE_SIZE=1G \
./benchmarks/run-filesystem-profile-tests.sh "$smoke_dir"

rm -rf "$smoke_dir"
```

Verify that the original power profile is restored, no XFS mount remains, no temporary loopback image remains, and only the requested scripts are included in the implementation commit.

## Git requirements

Before editing, inspect the repository status and preserve unrelated changes.

Create an atomic implementation commit containing only:

```text
benchmarks/activate-performance.sh
benchmarks/run-filesystem-profile-tests.sh
```

Use this commit message:

```text
Add power profile filesystem benchmark scripts
```

Push the branch to my fork:

```bash
git push -u fork profile-perf
```

Report the commit SHA, branch name, changed files, test commands and results, and the remote branch URL.
