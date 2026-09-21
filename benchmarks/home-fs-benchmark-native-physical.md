# `$HOME` filesystem benchmark — native physical partition

This report records the follow-up benchmark requested after the initial Linux
loopback comparison. The filesystems were tested sequentially on the same
physical NVMe partition, rather than inside loopback images.

## Executive conclusion

For an Omarchy installation, keep the complete `$HOME` on the existing Btrfs
COW layout with `compress=zstd:1`. It is slower than ext4 and XFS for this
specific direct synchronous workload, but it preserves the Btrfs subvolume,
checksum, compression, snapshot, and rollback model used by Omarchy.

The practical optimization is selective Btrfs NOCOW for large mutable data
where snapshot semantics are not needed, such as VM images, build trees,
container storage, model stores, and disposable caches. NOCOW substantially
improved Btrfs performance while retaining the surrounding Btrfs filesystem.

A separate ext4 or XFS filesystem is justified only for data where raw I/O
performance is more important than Btrfs integration. Ext4 is the conservative
choice; XFS had the highest balanced sequential-write mean but higher variance
and no Omarchy snapshot integration.

## Test method

- Date: 2026-09-21
- Host: Apple M1 Pro running Arch Linux ARM/Asahi
- Kernel: `7.1.13-3-1-ARCH`
- Device: temporary physical partition `/dev/nvme0n1p7`
- Device size: 10 GiB
- Tool: `fio 3.42`
- Test file: 4 GiB
- I/O per run: 4 GiB
- Block size: 1 MiB
- I/O mode: direct synchronous I/O, `ioengine=sync`, `iodepth=1`
- Repetitions: 3 for each filesystem/profile/workload combination
- Workloads: sequential read, sequential write, random read
- Profiles: `power-saver`, `balanced`, `performance`

Each filesystem was freshly created on the same partition before testing:

- Btrfs COW with `compress=zstd:1`
- Btrfs COW with compression disabled
- Btrfs NOCOW, using `chattr +C` on the test directory before creating files
- XFS with `reflink=0`
- ext4

The macOS comparison was the previously committed APFS run. It is a useful
directional baseline, but not a strictly equivalent test: it used a different
OS/filesystem environment and macOS `F_NOCACHE` semantics rather than Linux
`O_DIRECT`.

## Results

All values are mean throughput in MiB/s. Each triplet is:

```text
sequential read / sequential write / random read
```

| Filesystem | Power-saver | Balanced | Performance |
|---|---:|---:|---:|
| Btrfs COW + zstd | 1,047 / 792 / 1,080 | 1,063 / 785 / 1,071 | 2,273 / 1,368 / 2,218 |
| Btrfs COW, no compression | 1,037 / 784 / 1,037 | 1,055 / 777 / 1,079 | 2,232 / 1,407 / 2,163 |
| Btrfs NOCOW | 1,857 / 1,158 / 1,827 | 1,820 / 1,149 / 1,777 | 2,728 / 1,869 / 2,709 |
| XFS | 2,425 / 1,356 / 2,389 | 2,399 / 1,369 / 2,559 | 2,666 / 1,438 / 2,548 |
| ext4 | 2,543 / 1,271 / 2,567 | 2,579 / 1,220 / 2,534 | 2,554 / 1,258 / 2,549 |

The complete per-run data, including standard deviations, governors, frequency
limits, TuneD profile, and mount options, is in
[`home-fs-benchmark-native-physical.csv`](home-fs-benchmark-native-physical.csv).

## Balanced-profile comparison with APFS

The earlier macOS APFS reference means were:

| Filesystem | Sequential read | Sequential write | Random read |
|---|---:|---:|---:|
| APFS reference | 2,585 | 4,538 | 2,601 |
| Btrfs COW + zstd | 1,063 | 785 | 1,071 |
| Btrfs COW, no compression | 1,055 | 777 | 1,079 |
| Btrfs NOCOW | 1,820 | 1,149 | 1,777 |
| XFS | 2,399 | 1,369 | 2,559 |
| ext4 | 2,579 | 1,220 | 2,534 |

Relative to the APFS reference at balanced:

- ext4 reached approximately 100% of APFS sequential-read throughput and 97% of
  random-read throughput.
- XFS reached approximately 93% of sequential-read throughput and 98% of
  random-read throughput.
- Btrfs NOCOW reached approximately 70% of sequential-read throughput and 68%
  of random-read throughput.
- Normal Btrfs COW reached approximately 41% of APFS read throughput.
- No Linux filesystem approached the APFS sequential-write result. The write
  gap should not be attributed solely to filesystem choice because the
  operating systems and I/O stacks differ.

## Findings

### Btrfs compression

Removing compression made almost no difference:

- Balanced sequential read: 1,063 MiB/s with zstd versus 1,055 MiB/s without.
- Balanced sequential write: 785 MiB/s with zstd versus 777 MiB/s without.
- Balanced random read: 1,071 MiB/s with zstd versus 1,079 MiB/s without.

The test deliberately refilled buffers with incompressible data, so it does
not measure the benefit compression can provide for compressible user data.
There is no performance-based reason to disable the existing `compress=zstd:1`
setting for the complete home filesystem.

### Btrfs NOCOW

At balanced, NOCOW improved over normal Btrfs COW by approximately:

- 71% for sequential reads
- 46% for sequential writes
- 66% for random reads

This makes NOCOW the best compromise when retaining Btrfs management matters,
but NOCOW files do not have the same copy-on-write, snapshot, compression, and
data-checksum behavior as ordinary Btrfs files. It should be applied only to
purpose-specific directories and before their files are created.

### XFS and ext4

XFS delivered the highest balanced sequential-write mean at 1,369 MiB/s.
However, its sequential-write variance was higher than ext4's, and it provides
none of Omarchy's Btrfs subvolume/snapshot integration.

Ext4 delivered the highest balanced sequential-read mean at 2,579 MiB/s and
was very stable for reads and random reads. It is the conservative raw-
performance choice for a separate scratch/data filesystem.

Neither result justifies converting the complete Omarchy `$HOME` away from
Btrfs.

## Power-profile findings

Power-saver and balanced were generally close for all filesystems. The observed
performance profile significantly improved Btrfs results:

- Btrfs COW reads increased by roughly 100–114%; writes increased by roughly
  74–81%.
- Btrfs NOCOW improved by roughly 50–63%.
- XFS and ext4 changed much less.

There is a qualification: the `performance` CPU governor was observed during
the Btrfs performance runs, but later XFS and ext4 runs observed `schedutil`
for part or all of the run. Therefore the performance rows are useful observed
behavior, but not a perfectly controlled cross-filesystem comparison. The
balanced rows are the cleanest basis for choosing a filesystem. The governor
propagation issue should be investigated separately if predictable performance
mode behavior is required.

## Recommendation for Omarchy

| Use case | Recommendation |
|---|---|
| Complete Omarchy `$HOME` | Btrfs COW with existing `compress=zstd:1` |
| VM disks, build trees, caches, model stores | Dedicated Btrfs NOCOW directories |
| Separate raw-performance scratch/data partition | ext4 as the conservative choice; XFS when sequential writes are the priority |
| Complete `$HOME` converted to ext4 or XFS | Not recommended |

The final 10 GiB test partition was removed after testing. The original GPT
layout and Btrfs partition size were restored, Btrfs was grown back to the
partition maximum, and the system rebooted successfully.
