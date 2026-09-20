# Native macOS VM artifact and handoff prompt

You are operating on the native macOS installation of an Apple Silicon Mac. Your task is to prepare the private Apple firmware and provisioned guest bundle needed by a separate Asahi Linux VM experiment, then hand those artifacts back to the Linux host. Do not modify or reinstall Omarchy, do not alter the Mac's boot configuration, and do not publish or commit any Apple firmware, restore image, VM disk, or VM identity.

## Objective

Produce these private files for the Linux checkout:

```text
/home/nunix/Work/macos-asahi-vm/artifacts/firmware/AVPBooter.vmapple2.bin
/home/nunix/Work/macos-asahi-vm/artifacts/guest/aux.img.trimmed
/home/nunix/Work/macos-asahi-vm/artifacts/guest/disk.img
/home/nunix/Work/macos-asahi-vm/artifacts/guest/vm.json
```

The Linux host is an Apple M1 Pro running Arch Linux ARM/Asahi. It has already booted the patched kernel `7.1.13-ARCH-vmapple1-ARCH`, has 16 KiB pages, has accessible `/dev/kvm`, and passes its VMApple host check. Its prepared Reims/QEMU binary is at `/home/nunix/Work/macos-asahi-vm/build/reims-linux-product/vendor/qemu/build/qemu-system-aarch64`.

The Linux checkout currently has the verified Ventura restore image at `artifacts/UniversalMac_13.6_22G120_Restore.ipsw` with these expected values:

```text
filename: UniversalMac_13.6_22G120_Restore.ipsw
size:     12893555341 bytes
SHA-1:    a1675f2c8412122a5e796981571b0269a966708e
build:    macOS 13.6 (22G120)
```

The final Linux launch is separate from this Mac session. Once the files are transferred, Linux will run `scripts/check-host.sh` and then, only after verification, `scripts/launch-gui-kvm.sh`. The first graphical output is expected in a native Reims/Vulkan window on Linux; Remmina is not needed for initial bring-up.

## Rules

1. Work from native macOS, not from an Asahi Linux shell.
2. Use a staging directory outside any Git checkout, such as `$HOME/macos-vm-staging`.
3. Keep `AVPBooter.vmapple2.bin`, the IPSW, `disk.img`, `aux.img`, `aux.img.trimmed`, and `vm.json` private. Do not paste their contents, machine identifiers, ECID, personalization data, or full hashes of the guest disk into a public issue or repository.
4. Never overwrite an existing guest disk without explicit confirmation. Prefer a new empty staging directory and leave the original source files untouched.
5. Preserve `disk.img` as a sparse file during transfer. Do not use a copy method that expands a 64 GiB sparse disk into 64 GiB of allocated storage.
6. Do not run Linux-only scripts, QEMU, `idevicerestore`, USB/IP experiments, or `scripts/launch-dfu.sh` on macOS. The Linux DFU path is a separate experimental fallback and is not required for this known-good provisioning route.
7. Do not silently download another 13–20 GiB IPSW. Reuse the verified Ventura IPSW if it is available, or stop and ask the operator before downloading a replacement.
8. Record exact command output and errors, but redact secrets and private machine identity values from the final report.
9. If a step fails, stop at that boundary and report the command, tool versions, relevant error, and whether any output files are complete. Do not repeatedly retry a restore that may have mutated its disks.

## Phase 1: inspect the native Mac and create staging

Run the following in a Bash shell on native macOS:

```bash
set -euo pipefail

printf 'macOS: '; sw_vers -productVersion
printf 'build: '; sw_vers -buildVersion
printf 'hardware: '; sysctl -n hw.model
printf 'arch: '; uname -m
printf 'macosvm: '; command -v macosvm || true
printf 'brew: '; command -v brew || true

STAGE="$HOME/macos-vm-staging"
test ! -e "$STAGE" || { echo "refusing to reuse existing staging directory: $STAGE" >&2; exit 1; }
mkdir -p "$STAGE/firmware" "$STAGE/guest"
```

If `macosvm` is not installed, install the official tool through Homebrew and verify it before proceeding:

```bash
brew install macosvm
macosvm --help
```

If Homebrew or `macosvm` cannot be installed, stop and report that instead of substituting an unverified provisioning tool.

## Phase 2: extract and identify the Apple booter

The expected native macOS source path is:

```text
/System/Library/Frameworks/Virtualization.framework/Resources/AVPBooter.vmapple2.bin
```

Copy it into staging and record its metadata without publishing the file:

```bash
BOOTER_SRC=/System/Library/Frameworks/Virtualization.framework/Resources/AVPBooter.vmapple2.bin
BOOTER="$STAGE/firmware/AVPBooter.vmapple2.bin"
test -f "$BOOTER_SRC" || { echo "missing AVP booter: $BOOTER_SRC" >&2; exit 1; }
cp -p "$BOOTER_SRC" "$BOOTER"
stat -f 'booter bytes=%z path=%N' "$BOOTER"
shasum -a 256 "$BOOTER"
file "$BOOTER"
strings "$BOOTER" | grep -E 'AVPBooter|mBoot-|VirtualMac|virt_firmware' | head -20 || true
```

The checksum and firmware build are evidence to include in the private handoff report. Do not assume that every macOS release's booter is compatible with every restore IPSW.

Compatibility warning: previous testing showed that a booter identifying as `mBoot-18000.121.3` is Tahoe-era firmware and rejects the Ventura 13.6 restore. If the copied booter reports that build, do not start a Ventura restore. Stop and report the mismatch; the known matching restore is macOS Tahoe 26.5.2 build 25F84, filename `UniversalMac_26.5.2_25F84_Restore.ipsw`, SHA-1 `a6dec8ec379533876d8ceea3d82ce482034e24ae`, and SHA-256 `065abd295a1a456a46c1155217eab92ee95816520ec9aeed83f249f074f68a04`. Do not substitute that image without operator confirmation and without updating the Linux handoff to use the matching guest version.

If the booter is a different build, record the build string and ask before pairing it with the Ventura image. Never try to make an incompatible pair work by modifying Apple files.

## Phase 3: locate and verify the IPSW

The Linux-side IPSW may need to be copied to the Mac through a shared volume, network transfer, or another user-approved method. Locate it without downloading a duplicate:

```bash
IPSW="${IPSW:-$HOME/Downloads/UniversalMac_13.6_22G120_Restore.ipsw}"
test -f "$IPSW" || {
  echo "The verified Ventura IPSW is not present at $IPSW." >&2
  echo "Transfer it from the Linux host or ask before downloading another copy." >&2
  exit 1
}

actual_size=$(stat -f %z "$IPSW")
actual_sha1=$(shasum -a 1 "$IPSW" | awk '{print $1}')
printf 'IPSW size=%s SHA-1=%s path=%s\n' "$actual_size" "$actual_sha1" "$IPSW"
test "$actual_size" = 12893555341 || { echo 'IPSW size mismatch' >&2; exit 1; }
test "$actual_sha1" = a1675f2c8412122a5e796981571b0269a966708e || { echo 'IPSW SHA-1 mismatch' >&2; exit 1; }
```

Do not proceed if the checksum does not match. If the file has a different name but the same checksum, that is acceptable; record the actual path.

## Phase 4: provision a fresh guest bundle on native macOS

Use a fresh 64 GiB sparse guest disk, four guest CPUs, 8 GiB RAM, and the same stable virtual MAC used by the Linux launcher. The restore may take a long time and may require substantial temporary space. Confirm that the Mac has enough free space before starting; do not delete unrelated files to make room.

Run:

```bash
GUEST="$STAGE/guest"

test ! -e "$GUEST/disk.img" || { echo "refusing to overwrite $GUEST/disk.img" >&2; exit 1; }
test ! -e "$GUEST/vm.json" || { echo "refusing to overwrite $GUEST/vm.json" >&2; exit 1; }

macosvm \
  --disk "$GUEST/disk.img,size=64g" \
  --aux "$GUEST/aux.img" \
  --restore "$IPSW" \
  --net nat \
  --mac 52:54:00:76:61:70 \
  -c 4 \
  -r 8g \
  "$GUEST/vm.json"
```

Do not interrupt a successful restore merely because it is slow. If `macosvm` exits nonzero, preserve its log/output and stop; do not rerun it against the same mutated disk. Verify that `vm.json`, `disk.img`, and `aux.img` exist before continuing.

The Linux VMApple launcher expects the 32 MiB payload inside the wrapped auxiliary image, so create the trimmed copy exactly as follows:

```bash
dd if="$GUEST/aux.img" of="$GUEST/aux.img.trimmed" bs=16384 skip=1

stat -f 'disk logical bytes=%z allocated blocks=%b path=%N' "$GUEST/disk.img"
stat -f 'aux bytes=%z allocated blocks=%b path=%N' "$GUEST/aux.img"
stat -f 'trimmed aux bytes=%z allocated blocks=%b path=%N' "$GUEST/aux.img.trimmed"
stat -f 'vm metadata bytes=%z path=%N' "$GUEST/vm.json"
test "$(stat -f %z "$GUEST/aux.img.trimmed")" = 33554432 || { echo 'trimmed AUX is not 32 MiB' >&2; exit 1; }
```

The logical disk size should be 64 GiB (`68719476736` bytes), while its allocated blocks should be much smaller than its logical size. Do not paste `vm.json` into chat: it contains the VM identity used to derive the guest ECID.

## Phase 5: validate staging before transfer

Run a final private inventory:

```bash
find "$STAGE" -maxdepth 3 -type f -exec stat -f '%z %N' {} \; | sort
shasum -a 256 "$BOOTER"
```

The required files are exactly:

```text
$STAGE/firmware/AVPBooter.vmapple2.bin
$STAGE/guest/aux.img.trimmed
$STAGE/guest/disk.img
$STAGE/guest/vm.json
```

It is fine for `aux.img` to remain in staging as a private backup, but only `aux.img.trimmed` is required by the Linux launcher. Do not commit any of these files to the `omarchy-mac` repository or any other Git repository.

## Phase 6: transfer to Linux without expanding the sparse disk

Ask the operator for the reachable Linux target if it is not already known. Do not guess a hostname or copy to an arbitrary machine. For an SSH transfer, set `LINUX_TARGET` to the Linux user's `user@host` and use a sparse-aware `rsync`:

```bash
: "Set this to the operator-provided Linux SSH target, for example nunix@linux-host"
LINUX_TARGET="user@linux-host"
LINUX_REPO=/home/nunix/Work/macos-asahi-vm

ssh "$LINUX_TARGET" "mkdir -p '$LINUX_REPO/artifacts/firmware' '$LINUX_REPO/artifacts/guest'"
rsync -aS --progress "$STAGE/firmware/" \
  "$LINUX_TARGET:$LINUX_REPO/artifacts/firmware/"
rsync -aS --progress "$STAGE/guest/" \
  "$LINUX_TARGET:$LINUX_REPO/artifacts/guest/"
```

If SSH is unavailable, use an operator-approved external disk or mounted share and a sparse-preserving copy method. Verify the logical and allocated sizes on Linux after transfer; a 64 GiB fully allocated copy is a failed transfer, not an acceptable result. Keep the Mac staging copy until Linux has completed its first validation and, preferably, a backup has been made.

## Phase 7: Linux-side handoff validation and launch

If the Linux host is reachable, run this remotely or give these exact commands to the operator:

```bash
cd /home/nunix/Work/macos-asahi-vm

set -euo pipefail
test "$(uname -m)" = aarch64
test "$(uname -r)" = 7.1.13-ARCH-vmapple1-ARCH
test -r /dev/kvm
test -w /dev/kvm
test -f artifacts/firmware/AVPBooter.vmapple2.bin
test -f artifacts/guest/aux.img.trimmed
test -f artifacts/guest/disk.img
test -f artifacts/guest/vm.json
stat --printf='%s %n\n' artifacts/firmware/AVPBooter.vmapple2.bin artifacts/guest/aux.img.trimmed artifacts/guest/disk.img artifacts/guest/vm.json
sha256sum artifacts/firmware/AVPBooter.vmapple2.bin
scripts/check-host.sh
```

Only after those checks pass, launch the guest on Linux:

```bash
cd /home/nunix/Work/macos-asahi-vm
AVPBOOTER="$PWD/artifacts/firmware/AVPBooter.vmapple2.bin" \
GUEST_DIR="$PWD/artifacts/guest" \
  scripts/launch-gui-kvm.sh
```

The launcher should use the Reims Vulkan window, start with the patched VMApple KVM path, and write serial/QMP logs under `logs/`. Do not expect the initial Reims display in Remmina. Remmina becomes useful only after macOS boots and Screen Sharing is deliberately enabled inside the guest.

Before launching, make a backup or filesystem snapshot of the provisioned guest if practical. The Linux launch can mutate the auxiliary and root images during boot. Do not run the launcher concurrently with any other process using the same images.

## Required final report

Report only the following non-sensitive facts:

- native macOS version and build;
- Mac hardware model;
- `macosvm` version;
- booter file size, SHA-256, and visible firmware build string;
- IPSW filename, size, and published SHA-1;
- whether provisioning completed;
- logical and approximate allocated size of `disk.img`;
- size of `aux.img.trimmed`;
- transfer method and Linux-side validation result;
- the exact failure boundary and preserved log path if anything failed.

Do not report the VM ECID, `vm.json` contents, Apple signing nonces, private keys, or any proprietary artifact bytes. A successful handoff ends when the four required files are present on Linux, sparse storage has been verified, and the Linux operator has the launch command above.
