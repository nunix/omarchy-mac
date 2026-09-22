# Touch ID Recon Dossier — MacBookPro18,1 (M1 Pro)

Collected passively from a running macOS install via `system_profiler`, `kextstat`,
and `ioreg`. No kext binaries were extracted, no kernel debugging/tracing was used,
no physical bus probing was done. This is read-only inspection of IOKit's public
registry, equivalent to what any user-level tool can already see.

## 1. Hardware identity

```
Model Identifier : MacBookPro18,1  (14" MacBook Pro 2021)
Chip             : Apple M1 Pro (T6000), target-type J316s
Cores            : 8P + 2E
Kernel           : Darwin 27.0.0, RELEASE_ARM64_T6000
Boot policy      : Secure Boot Full Security, SIP on, SSV on, Kernel CTRR on
```
The boot policy line matters only for macOS itself — Asahi Linux boots via its own
m1n1/U-Boot chain and is unaffected by XNU's CTRR/SIP settings.

## 2. Driver/service chain (from `kextstat`)

```
AppleSEPManager            -- AP<->SEP mailbox transport
AppleSEPGenericTransfer    -- generic SEP data channel
IOBiometricFamily          -- biometric family base class
AppleBiometricSensor       -- owns the mesa SPI node, AP-side sensor driver
AppleSEPKeyStore           -- SEP-backed keybag/keystore
AppleMesaSEPDriver         -- bridges "mesa" protocol data to the SEP
AppleBiometricServices     -- userspace-facing biometric service (biometrickitd client)
AppleMultitouchDriver      -- unrelated (trackpad), listed for completeness
```

## 3. Device tree: the sensor node itself

Path: `arm-io/spi2@9B108000/mesa@0`

```
+-o mesa@0  <class AppleARMSPIDevice>
  | "compatible"                = "biosensor,mesa"
  | "device_type"                = "mesa"
  | "name"                       = "mesa"
  | "IOUserClientClass"          = "AppleARMSPIDeviceUserClient"
  | "sensor-id"                  = <52330000>      -- LE u32 = 0x3352
  | "spi-frequency"              = <00127a00>      -- LE u32 = 0x007a1200 = 8,000,000 Hz
  | "interrupts"                 = <c300000003000000>   -- irq 0xc3, type 3
  | "interrupt-parent"           = <88000000>
  | "power-on-delay"             = <07000000>      -- 7 (units unconfirmed, likely ms)
  | "power-off-delay"            = <0a000000>      -- 10
  | "time-between-scans"         = <00000200>      -- 0x200 = 512
  | "scan-timer-reset-time"      = <99990000>      -- 0x9999 = 39321
  | "max-scan-time"              = <33330100>      -- 0x00013333 = 78643
  | "function-mesa_pwr"          = <880000004f495047c400000001010000>
  | "function-hid_event_dispatch"= <4301000044747542>
  | "reg"                        = <00000000f4010000000101080000000014000000...>
```

Decoding note on `function-*` properties: Apple's Apple Silicon device trees encode
GPIO/function references as `<len32><tag4><args...>`. The tag is a reversed ASCII
FourCC. `4f 49 50 47` = "OIPG" → reversed = "GPIO". So `function-mesa_pwr` is a GPIO
handle: pin `0xc4`, flags `00 01 01 00`. This convention is already handled by
Asahi's upstream `apple,function-*` GPIO parsing code (used for backlight, panel
power, etc.), so no new parser is needed for this part.

`function-hid_event_dispatch`'s tag bytes don't resolve to a known reversed-FourCC
in this dossier — flag it for lookup against Asahi's function-ID table rather than
guessing.

## 4. What branches off the sensor

```
mesa@0 (raw SPI, AP-visible)
 ├─ AppleSandDollar → AppleMesaShim → IOHIDEventServiceUserClient
 │     AP-only path. Looks like plain HID button-press events
 │     (this Mac's Touch ID sensor is embedded in the power button).
 └─ AppleMesaSEPDriver → AppleBiometricServices → AppleBiometricServicesUserClient
       (client: biometrickitd, pid seen as consumer of AppleMesaUserClient)
       This is the path that carries actual print/ridge data to the SEP.
```

This split is the central fact for feasibility: the **transport** (SPI bus,
GPIO power line, IRQ line) is fully exposed to the Application Processor — the
same processor Linux runs on under Asahi. Nothing here is SEP-exclusive at the
wire level. But the **payload** that reaches `AppleMesaSEPDriver` is presumed
encrypted end-to-end between the sensor silicon and the SEP, per Apple's
published Touch ID / Secure Enclave pairing design (sensor and SEP share a
unique key burned in at manufacture; the AP-side kext only relays bytes it
cannot decrypt). That pairing has never been broken on any Apple Silicon SEP
(A11 checkm8 broke the AP bootrom on older chips, not the SEP; M-series SEP
has no public compromise as of this writing).

## 5. Practical implication

- Bus access: yes, achievable — spi2 is an ordinary Apple SPI peripheral, and
  Linux mainline already has `drivers/spi/spi-apple.c` for this SPI controller
  family under Asahi.
- Raw transport capture: yes, achievable — you can power the sensor via the
  GPIO pin decoded above and clock it at 8 MHz, and see what comes back.
- Turning that into a working fingerprint *auth* driver: blocked unless the
  captured payload turns out to be structured/plaintext, which is not what
  Apple's stated architecture predicts. Plan below treats this as the
  make-or-break checkpoint rather than assuming either outcome.
