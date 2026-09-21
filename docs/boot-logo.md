# Early Apple Silicon boot logo

On Asahi systems, the logo visible immediately after power-on is drawn by
**m1n1**, before U-Boot, the Linux kernel, or Plymouth starts. Changing the
Plymouth theme therefore does not change this first logo.

## Options considered

- **Change Plymouth**: safe and already supported by Omarchy, but it appears
  later in the boot sequence and cannot affect the m1n1 screen.
- **Configure U-Boot**: would require enabling and maintaining a separate
  U-Boot splash path. U-Boot is not the component currently drawing the logo.
- **Patch `/boot/efi/m1n1/boot.bin` directly**: simple and effective, but the
  next m1n1, U-Boot, kernel, or device-tree update regenerates the file and
  removes the logo.
- **Rebuild or replace the m1n1 package**: persistent, but modifies a
  package-owned component and makes normal Asahi package updates harder to
  consume.
- **Run a pacman hook after the official m1n1 update**: keeps the vendor
  packages intact while reapplying the customization whenever the boot image
  is rebuilt.

We chose the last option. It is the smallest update-safe integration and it
keeps the official Asahi update path as the source of the current boot
components.

## Implementation

`default/m1n1/m1n1-logo.payload` contains m1n1's documented custom-logo payload:

a 16-byte `m1n1_logo_256128` header followed by the Omarchy icon as opaque RGBA
images at 256×256 and 128×128 pixels. The square `icon.png` is used instead of
the rectangular wordmark so it fits both framebuffer slots without stretching.

On Apple Silicon systems with Asahi m1n1 installed, the installer or migration:

1. Copies the payload, updater, and hook to root-owned paths under `/usr/local`
   and `/etc/pacman.d/hooks`.
2. Runs the official `/usr/bin/update-m1n1` with a root-owned copy of the
   packaged m1n1 plus the custom payload.
3. Installs a `99-omarchy-m1n1-logo.hook`, which runs after Asahi's official
   m1n1 hook and repeats the process when m1n1, U-Boot, the Asahi kernel/device
   trees, or the update helper changes.
4. Verifies that the generated boot image starts with the expected custom
   payload and keeps a one-time pre-customization backup in
   `/var/lib/omarchy/m1n1-logo/`.

The package-owned `/usr/lib/asahi-boot/m1n1.bin` and the official Asahi hook are
not modified. On non-Asahi systems the hardware install step is a no-op.
