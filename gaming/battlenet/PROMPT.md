# Prompt: install Battle.net + WoW Forever on Omarchy for Apple Silicon

Paste the prompt below into a coding agent (Claude Code, etc.) running on the
target machine. It reproduces exactly the setup described in `README.md`, using
the files in this directory.

---

```text
You are setting up Battle.net and World of Warcraft Forever on this machine: an
Apple Silicon Mac running Omarchy on Asahi Linux (aarch64, 16K pages, Hyprland).
Follow the reference setup in gaming/battlenet/ of
https://github.com/nunix/omarchy-mac (branch "gaming"). Read its README.md
first; it explains every component and why it exists. Clone the repo if it
isn't present.

Goal: Battle.net and WoW Forever start from Menu > Gaming and the app launcher,
render on the Apple GPU through muvm + FEX + Proton, show a MangoHud overlay,
and Battle.net has a pinned, clickable icon in the Omarchy bar.

Do it with gaming/battlenet/install.sh, stopping to check results after each
phase rather than running it blind:

1. Preflight: confirm `uname -m` is aarch64, `getconf PAGESIZE` is 16384,
   `omarchy` and `hyprctl` exist. Show `pacman -Q muvm FEX-Emu mesa` and
   `vulkaninfo --summary | grep -E "deviceName|driverName"` (expect Apple M*
   / Honeykrisp).
2. Proton: Steam's "Proton - Experimental" must exist under
   ~/.local/share/Steam/steamapps/common/. If it doesn't, ask me to run `steam`,
   log in, then run `steam steam://install/1493710`, and wait for me to
   confirm. Never log in on my behalf.
3. Run `./install.sh` (add `--prefix DIR` if I tell you where Battle.net
   lives; the script auto-detects an existing Steam prefix that has Battle.net).
   It builds FEX at a pinned commit with patches/fex-pr5785-*.patch (about 5
   minutes) and xembed-sni-proxy with its patch, installs x86_64 MangoHud, the
   launchers, desktop entries, menu rows and the tray pin. Use `sudo` only for
   packages; everything else goes in ~/.local and ~/.config.
4. Verify inside the VM that the patched FEX is what muvm registered:
     muvm -- bash -c 'cat /proc/sys/fs/binfmt_misc/FEX-x86_64 > /tmp/binfmt.txt'
     (read it via a file in $HOME, since muvm doesn't forward guest output)
   The interpreter must be ~/.local/opt/omarchy-battlenet/fex/bin/FEX. If muvm
   is newer than 0.6.0 and registers /usr/bin/FEX, report it; don't patch
   system files.
5. Battle.net: if the installer ran, let me click through the setup and log
   in. Then start Menu > Gaming > Battle.net and confirm a "Battle.net" window
   appears (`hyprctl clients -j`, class steam_proton). Close it, confirm it
   hides in the tray and that the bar icon (SNI item Id "steam_proton")
   restores it.
6. I install WoW Forever from Battle.net. Then start Menu > Gaming > WoW
   Forever and confirm the "World of Warcraft" window and the MangoHud overlay.
   The first start takes a minute or two.
7. Run `./install.sh --icons` after my Battle.net login, then
   `omarchy restart shell`. Confirm the menu shows the WoW Forever glyph.
8. After I've quit WoW once: `./install.sh --render-scale 0.75` (75% render
   scale + FSR 1.0). Don't change any other WoW setting.

Rules:
- Never close my games or Battle.net without asking. If you need a fresh VM
  (for example after changing FEX), ask me to quit them first.
- Don't edit anything under /usr/share/omarchy; use ~/.config overrides.
- Logs: ~/.local/state/omarchy-battlenet/<exe>.vm.log (inside the VM), WoW's
  _classic_beta_/Logs and Errors, Battle.net's AppData/Local/Battle.net/Logs.
- Known pitfalls (see README troubleshooting): "PartialDecode ... entry block"
  means unpatched FEX; "Exec format error" means muvm didn't register FEX;
  "X connection to :1 broken" right after Battle.net starts means the VM
  exited (the launcher's `wineserver -w` handles this); a WoW window that
  flashes and closes usually means a leftover windowless WoW in the VM.

Finish with a short report: what was installed where, what you verified, and
anything that didn't match this description.
```
