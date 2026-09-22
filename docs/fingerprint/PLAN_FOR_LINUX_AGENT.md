# Plan: Touch ID sensor support on Omarchy (Asahi Linux, MacBookPro18,1 / M1 Pro / T6000)

Read `RECON_DOSSIER.md` first — it has the actual device tree node, driver chain,
and decoded properties this plan references. Do not re-derive that data; verify
it against this specific machine's Linux device tree instead (Sec. 0 below).

## Ground truth going in

The Touch ID sensor (`biosensor,mesa` on `spi2@9B108000`) is on an
AP-visible SPI bus — the same bus Linux itself will enumerate under Asahi.
That part is not the blocker. The blocker is that the sensor's payload is
presumed cryptographically paired to the Secure Enclave Processor (SEP), a
coprocessor Linux never runs on and cannot get keys from. This has not been
broken on any M-series Mac. So: full biometric unlock is very likely
infeasible. Do not commit to that goal. The plan is structured so real
information (Stage 1–2) determines whether Stage 3+ is worth doing at all,
instead of assuming success.

## Stage 0 — Confirm the DT node exists identically under Linux

```
ls /sys/firmware/devicetree/base/arm-io/spi2*/mesa*/  2>/dev/null
dtc -I fs /proc/device-tree -O dts 2>/dev/null | grep -A20 'mesa@0'
```
Confirm `compatible = "biosensor,mesa"` is present and matches the dossier.
Then check whether Linux mainline or the Asahi kernel tree already claims it:
```
grep -rn "biosensor" /usr/src/linux*/drivers 2>/dev/null
grep -rn "biosensor,mesa" $(find / -maxdepth 6 -iname 'asahi*' -type d 2>/dev/null)
```
If a driver already exists (unlikely but check — Asahi moves fast), stop and
read that instead of building from scratch.

## Stage 1 — Passive protocol observation (do this before writing any driver)

You don't need a logic analyzer. Do this from the macOS side of the same
physical machine, since biometrickitd only runs there:

```
log stream --predicate 'process == "biometrickitd" or subsystem contains "Biometric"' --info --debug
```
Run that while enrolling/verifying a real fingerprint in System Settings, in a
separate terminal. Also poll the raw node state before/during/after a scan:
```
watch -n0.2 'ioreg -n mesa -r -w0 | grep -E "mesa-state|MesaSelfTest"'
```
Goal: build a timeline of state transitions and any size/length info leaked
in log messages (message *sizes* can leak even when *content* doesn't).
This costs nothing and might tell you immediately whether payload sizes look
like raw fingerprint images (tens of KB, variable) vs. small fixed-size MACs
(encrypted-blob shaped, a few hundred bytes) — that alone is a strong signal.

## Stage 2 — Raw SPI transport test (Linux side, no protocol assumptions)

Goal: prove you can power the sensor and get *any* deterministic byte pattern
back — not yet parse it.

1. Base the client on `drivers/spi/spi-apple.c` (already upstream).
2. Add a devicetree fixup / overlay binding a stub driver to
   `compatible = "biosensor,mesa"` at `spi2@9B108000`.
3. Drive the power GPIO decoded in the dossier: pin `0xc4`, using the same
   `apple,function-*` GPIO helper Asahi already uses for backlight/panel
   power (search for how `function-panel_pwren` or similar is consumed
   in the Asahi GPIO/pinctrl code — reuse that call path, don't reinvent it).
4. Clock SPI at 8 MHz (`spi-frequency` in the dossier), matching the chip-select
   and mode macOS's device tree implies (`reg` property) — do not guess mode;
   cross-check against how the existing `spi-apple.c` consumers derive mode
   from their own devicetree nodes, since Apple's SPI mode bits are usually
   encoded in `reg` rather than a separate `spi-mode` property.
5. Send a trivial read/status transaction (all-zero or a single-byte probe) and
   capture what comes back. You are looking for: does the device ACK/respond
   at all, is the response fixed or does it vary run-to-run.

Do NOT attempt an enroll/match protocol yet. This stage is purely "is the wire
alive and responsive from Linux."

## Stage 3 — Decision gate (do not skip this)

Compare Stage 1 timeline + Stage 2 raw bytes against these two outcomes:

- **Outcome A — looks structured/plaintext** (e.g. consistent frame headers,
  image-sized payloads that change meaningfully with different fingers/scans):
  proceed to Stage 4. This would be a genuinely novel finding worth writing up
  and sharing with the Asahi Linux project before going further, since it
  would contradict the documented SEP-pairing architecture.
- **Outcome B — looks opaque/encrypted** (fixed-size blobs, high entropy,
  no correlation between scans of visibly different input): stop pursuing
  fingerprint auth. This is the expected, architecturally-predicted result.
  Document findings and move on — see "Fallback" below.

Be honest with yourself here. Wanting Outcome A doesn't produce it.

## Stage 4 — Only if Outcome A: libfprint image driver

If real image-shaped data is obtainable, this becomes an ordinary (if novel)
libfprint driver problem: treat the sensor as a raw image source, do
enrollment and matching entirely on the host (independent of Apple's SEP —
this would be a new, Linux-only fingerprint identity, not a way to reuse
fingerprints enrolled in macOS, which is impossible regardless of outcome).
Follow libfprint's driver contribution guide for image-based sensors
(`libfprint/drivers/`, look at an existing SPI or non-USB sensor driver as a
template, e.g. one of the `elan`/`egis` family for structure, even though
transport differs).

## Fallback (expected outcome, and it's still useful)

Even under Outcome B, two things are worth confirming/shipping:
1. The physical button (Touch ID sensor doubles as the power button on this
   model) generating a normal HID keypress via the `AppleMesaShim` path is
   AP-only and unrelated to biometrics — verify Asahi's existing
   power-button/keyboard driver already handles this key. If it does, no
   further work needed here; if it doesn't, that's a small, real, achievable
   fix distinct from fingerprint auth.
2. Write up whatever Stage 1–2 data was gathered (even a "confirmed opaque"
   result) as an issue/discussion on the Asahi Linux project — negative
   results here are useful to the wider community and stop others from
   re-treading the same ground.

## What NOT to do

- Don't extract or redistribute Apple kext binaries or SEP firmware images.
- Don't attempt to brute-force or attack the SEP pairing — there is no
  known working method, and attempting cryptographic attacks on a live
  Secure Enclave is out of scope for a driver project.
- Don't promise a login-capable fingerprint unlock in any status update until
  Stage 3 has actually concluded Outcome A with real evidence in hand.
