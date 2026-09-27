# Battle.net + World of Warcraft on Omarchy for Apple Silicon

Run **Battle.net** and **World of Warcraft Forever** on an M-series MacBook running
[Omarchy](https://omarchy.org) on [Asahi Linux](https://asahilinux.org), with the
GPU, an FPS overlay, a Battle.net icon in the top bar and entries in the Omarchy
menu, so it feels like any other app.

> **Status (2026-09-27):** working on a MacBook Pro 16" M1 Pro (32 GB) with
> Omarchy 4.0.3rc4, kernel `linux-asahi` 7.1.13, Mesa 26.2.3, FEX 2609 + one
> unmerged patch, muvm 0.6.0 and Proton Experimental 11.0. WoW Forever logs in
> and plays at 30–40 FPS. Everything in this directory comes from that machine.
> The `install.sh` script automates the same steps. It has been checked piece by
> piece, but hasn't yet been run end-to-end on a fresh machine. Reports are welcome.

## Quick start

```bash
git clone -b gaming https://github.com/nunix/omarchy-mac.git
cd omarchy-mac/gaming/battlenet
./install.sh
```

The script tells you if Steam still needs to download Proton (a one-time login).
After Battle.net is installed and you've logged in:

```bash
./install.sh --icons              # WoW Forever icon for the menu and launcher
./install.sh --render-scale 0.75  # after the first WoW start, with WoW closed
```

Then use **Menu → Gaming → Battle.net** (or **WoW Forever**).

---

## How it works

WoW is an x86 Windows game with DirectX 12 rendering. The Mac has an ARM CPU and an
Apple GPU, and Asahi runs the kernel with 16K memory pages. Each layer below solves
one of those mismatches:

```
 Omarchy menu / app launcher / bar tray
        │
        ▼
 ~/.local/bin/battlenet, wow-forever ──► muvm-proton-run   (host, ARM64, 16K pages)
        │
        ▼
 ┌──────────── muvm microVM (libkrun/KVM, 4K pages) ────────────┐
 │  binfmt_misc ──► FEX (patched)  : x86/x86_64 → ARM64 JIT      │
 │  Proton Experimental = Wine + DXVK (D3D11) + vkd3d-proton     │
 │       (D3D12)  ──► Vulkan                                     │
 │  Mesa Honeykrisp (x86 build from the FEX rootfs overlay)      │
 │  MangoHud (x86_64 Vulkan layer)                               │
 └────────┬───────────────────────┬──────────────────────────────┘
          │ virtio-gpu native     │ X11 over the muvm bridge
          │ context (DRM)         ▼
          ▼                  Xwayland ◄──► xembed-sni-proxy ──► Omarchy bar tray
     Apple GPU (AGX)
```

### The technologies

| Piece | What it is | Why it's needed |
|---|---|---|
| **Asahi Linux** | Linux for Apple Silicon: kernel, GPU driver, firmware | The base. It uses **16K** memory pages, as the Apple chip requires. |
| **muvm** (on **libkrun**) | A tiny KVM virtual machine that shares your home directory, GPU, audio and X11 display with the host | x86 Windows software (Wine, FEX) needs **4K** pages, so it runs in a VM with a 4K-page kernel. Overhead is minimal. |
| **virtio-gpu native context** | Passes the real Asahi GPU driver interface into the VM | Games in the VM use the Apple GPU directly, not software rendering. |
| **FEX-Emu** | x86/x86_64 → ARM64 emulator (JIT), registered through `binfmt_misc` inside the VM | Runs x86 Wine, Proton and the game. It ships an x86 Arch root filesystem image (`fex-emu-rootfs-arch`) and x86 Mesa overlays. |
| **Proton Experimental** | Valve's Wine distribution with **DXVK** (D3D9–11 → Vulkan) and **vkd3d-proton** (D3D12 → Vulkan) | Runs Battle.net and WoW. WoW uses D3D12, so vkd3d-proton is what renders it. |
| **Mesa Honeykrisp** | The Vulkan 1.4 driver for Apple GPUs | What vkd3d-proton renders through. |
| **MangoHud** | Vulkan overlay (FPS, frame time, CPU, driver) | The official x86_64 build is loaded inside the VM, since the game is x86. |
| **xembed-sni-proxy** | Bridges old X11 tray icons (XEmbed) to the modern tray protocol (StatusNotifierItem) | Wine only speaks XEmbed; the Omarchy bar only speaks SNI. |
| **Omarchy menu + bar** | `omarchy-menu.jsonc` extensions, `shell.json` tray settings | Adds Menu → Gaming and pins the Battle.net icon. |

### What had to be built or patched, and why

1. **FEX with [PR #5785](https://github.com/FEX-Emu/FEX/pull/5785)** by FrontMage
   (`patches/fex-pr5785-instruction-fetch-fault-address.patch`).
   WoW's anti-tamper keeps parts of its code in locked memory pages and unlocks
   them from its fault handler. When an instruction crosses into a locked page,
   FEX 2609 reports the wrong fault address (the instruction's own, already
   unlocked page), so the handler does nothing and the game loops forever
   (log: `PartialDecode instruction in entry block: 14466EFFF`, symptom: no
   window, see [FEX #5399](https://github.com/FEX-Emu/FEX/issues/5399)).
   The PR reports the page that was actually touched. It no longer applies
   cleanly to FEX `main`; the patch here is rebased onto commit `59f85d6b7`.
   Only the Windows-side files needed conflict fixes, and they aren't used on
   Linux. It's built into `~/.local/opt/omarchy-battlenet/fex`; the system FEX
   package is left alone.

2. **muvm / FEX name mismatch.** muvm 0.6.0 looks for an executable called
   `FEXInterpreter` to register FEX inside the VM, but FEX 2609 renamed it to
   `FEX`. Without a fix, every x86 program started from a native tool fails with
   `Exec format error`. It's fixed upstream in
   [muvm PR #239](https://github.com/AsahiLinux/muvm/pull/239) (not released
   yet). The installer adds `~/.local/bin/FEXInterpreter → patched FEX`, and the
   launcher puts the patched FEX first in `PATH` so newer muvm releases (which
   look for `FEX`) also pick it up. That second part is untested until a muvm
   release with the fix is out.

3. **xembed-sni-proxy** ([BLumia's standalone build](https://github.com/BLumia/xembed-sni-proxy)
   of KDE's tool, plus `patches/xembed-sni-proxy-wine-tray.patch`), built with
   KDE's `extra-cmake-modules` into `~/.local/opt/omarchy-battlenet/`. The patch:
   - names untitled icons after their `WM_CLASS` (`steam_proton`) instead of a
     random window number, so the icon can be **pinned** in the bar
   - re-checks the click method at click time: Wine only asks for mouse events
     after the icon is embedded, and the fallback (XTest) never reaches it
   - moves the pointer over the icon before clicking, which Wine expects
   - turns a left-click on a Wine icon into two spaced double-clicks, because
     Battle.net restores its window on a double-click and ignores the first one
     after being hidden

4. **MangoHud**: the official x86_64 release (no build). It's loaded through
   `VK_ADD_IMPLICIT_LAYER_PATH` because the VM's x86 root filesystem is a
   read-only image.

5. **Launchers** (`bin/`), not upstream anywhere:
   - `muvm-proton-run` keeps the VM alive with `wineserver -w`. Otherwise the
     VM shuts down as soon as `Battle.net Launcher.exe` hands off to
     `Battle.net.exe`, which looks like an X11 crash
     (`X connection to :1 broken`).
   - Battle.net closes to the tray. If the menu entry is used while it's
     hidden, the launcher clicks the tray icon instead of starting a second
     copy, which wouldn't show anything. It resets the VM only when nothing is
     visible and there's no tray icon (leftover processes).
   - Programs launched while the VM runs attach to it, so the Play button and
     Menu → WoW Forever work alongside Battle.net.
   - Battle.net's Chromium UI runs with `--disable-gpu`. The game still uses
     the GPU.
   - It starts the tray bridge on demand and writes per-launch logs.

---

## Deployment

### Prerequisites

- An Apple Silicon Mac running Omarchy on Asahi (aarch64, 16K pages)
- About 5 GB for builds and Proton, plus the game (WoW Forever is ~65 GB)
- A Steam account, used once so Steam downloads Proton Experimental
- A Battle.net account with access to the game

### What `install.sh` does

| Step | Result |
|---|---|
| 1. Checks | aarch64, page size, Omarchy and Hyprland present |
| 2. Packages | `muvm FEX-Emu fex-emu-rootfs-arch mesa-fex-emu-overlay-{x86_64,i386} steam` plus build tools (`git cmake ninja clang lld nasm python jq curl qt6-base kwindowsystem libxtst xcb-util xcb-util-image`), via `omarchy-pkg-add` |
| 3. Proton | Checks that Steam's "Proton - Experimental" is present; otherwise tells you to run `steam`, log in, then `steam steam://install/1493710` |
| 4. FEX | Clones FEX at the pinned commit, applies the patch, builds (about 5 min on an M1 Pro) → `~/.local/opt/omarchy-battlenet/fex` |
| 5. Tray bridge | Builds ECM + xembed-sni-proxy with the patch → `~/.local/opt/omarchy-battlenet/xembed-sni-proxy` |
| 6. MangoHud | Downloads the x86_64 release → `~/.local/opt/omarchy-battlenet/mangohud`; installs `config/MangoHud.conf` if you have none |
| 7. Launchers | `~/.local/bin/{muvm-proton-run,battlenet,wow-forever}`, `~/.config/omarchy-battlenet/env`, desktop entries |
| 8. Omarchy | Menu → Gaming → Battle.net / WoW Forever; hides Omarchy's x86-only Battle.net install/remove rows; pins the tray icon and hides a duplicate Fcitx5 tray item. Backups of `omarchy-menu.jsonc` and `shell.json` are saved next to them. |
| 9. Battle.net | Downloads Blizzard's installer and runs it in the VM (skip with `--no-battlenet-setup`). If an existing Steam prefix already has Battle.net, it's reused. |
| 10. Icons | Builds the WoW Forever icons from your Battle.net cache, if you've logged in already |

Options: `--prefix DIR`, `--proton DIR`, `--rebuild`, `--no-battlenet-setup`,
`--hide-steam`, `--icons`, `--render-scale X`. See `./install.sh --help`.

### After installing

1. In Battle.net: log in, install **WoW Forever**, press Play.
   (Or use Menu → Gaming → WoW Forever and log in on WoW's own screen.)
2. `./install.sh --icons` and `omarchy restart shell` to get the WoW Forever icon.
   The icon isn't shipped here because it's Blizzard's artwork; the tool
   extracts it from your own Battle.net cache and traces a menu glyph from it.
3. After the first WoW start, with WoW closed: `./install.sh --render-scale 0.75`.

### Files and locations

| Path | Contents |
|---|---|
| `~/.local/opt/omarchy-battlenet/` | `fex/`, `xembed-sni-proxy/`, `ecm/`, `mangohud/` |
| `~/.cache/omarchy-battlenet/` | Build sources, Battle.net installer |
| `~/.config/omarchy-battlenet/env` | Prefix, Proton and install paths used by the launchers |
| `~/.local/bin/` | `muvm-proton-run`, `battlenet`, `wow-forever`, `FEXInterpreter` |
| `~/.local/state/omarchy-battlenet/` | Logs: `<exe>.vm.log` (inside the VM), `xembedsniproxy.log` |
| `~/Games/battlenet-proton/` | Default Proton prefix (Battle.net, games) |

---

## Performance and settings

WoW Forever defaults to low-ish quality on this machine. Measured at the same
spot with WoW's quality settings untouched, by rendering at different sizes:

| Rendered resolution | FPS |
|---|---|
| 3408×2122 (native, full screen) | 29 |
| 2880×1800 | 33 |
| **2560×1600** | **36** |
| 2304×1440 | 36 |
| 1920×1200 | 40 |

Cutting the pixels by 70% only adds about 38% FPS, so the game is mostly
**CPU-bound**: WoW's main thread runs through FEX. The sweet spot is a **75%
render scale** (the 3D world at about 2560×1600, upscaled with FSR 1.0) while the
interface stays at native sharpness. `--render-scale 0.75` sets `RenderScale`
and `ResampleQuality 3` in `Config.wtf`. You can fine-tune it in-game under
System → Graphics.

MangoHud: toggle with **Shift_R+F12**, reload the config with **Shift_L+F4**. It
can't show GPU load or temperatures because the VM has no sensors to read.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| WoW window never appears; `<exe>.vm.log` fills with `PartialDecode instruction in entry block` | Unpatched FEX is in use. Check that `~/.local/bin/FEXInterpreter` points to `~/.local/opt/omarchy-battlenet/fex/bin/FEX`. The VM keeps the FEX it started with, so quit Battle.net and games, then relaunch. |
| `Exec format error` in the logs | muvm didn't register FEX (see the name mismatch above). |
| Nothing happens from the menu | Battle.net is hidden in the tray: click the bar icon. If there's no icon, the launcher resets the VM on the next try. |
| WoW flashes and closes | A windowless WoW is still running in the VM (Battle.net counts 2 sessions in its log). Quit Battle.net fully (tray icon → right-click → Exit), then start again. |
| Small empty rectangle window | The tray bridge started after Battle.net. Quit Battle.net and relaunch. |
| Short stutters while Battle.net loads | Battle.net's UI and WoW share the emulated CPU. |

Logs: `~/.local/state/omarchy-battlenet/`, WoW's `_classic_beta_/Logs/` and
`Errors/`, Battle.net's `AppData/Local/Battle.net/Logs/` inside the prefix.

## Uninstall

```bash
rm -rf ~/.local/opt/omarchy-battlenet ~/.cache/omarchy-battlenet ~/.config/omarchy-battlenet ~/.local/state/omarchy-battlenet
rm -f ~/.local/bin/{muvm-proton-run,battlenet,wow-forever,FEXInterpreter}
rm -f ~/.local/share/applications/{battlenet,wow-forever}.desktop ~/.local/share/fonts/wowforever-icon.ttf
find ~/.local/share/icons/hicolor -name 'wow-forever.*' -delete
# Remove the "gaming*", "install.gaming.battlenet" and "remove.gaming.battlenet"
# lines from ~/.config/omarchy/extensions/omarchy-menu.jsonc
# The prefix (~/Games/battlenet-proton) holds Battle.net and your games.
```

## Credits

[Asahi Linux](https://asahilinux.org) (GPU driver, muvm, FEX packaging) ·
[FEX-Emu](https://fex-emu.com) and FrontMage for the anti-tamper fixes ·
[Valve Proton](https://github.com/ValveSoftware/Proton), DXVK, vkd3d-proton ·
[BLumia/xembed-sni-proxy](https://github.com/BLumia/xembed-sni-proxy) and KDE ·
[MangoHud](https://github.com/flightlessmango/MangoHud) · [Omarchy](https://omarchy.org).

Blizzard, Battle.net and World of Warcraft are trademarks of Blizzard
Entertainment. This project isn't affiliated with Blizzard. Running games under
Wine/Proton isn't officially supported by Blizzard; use at your own risk.
