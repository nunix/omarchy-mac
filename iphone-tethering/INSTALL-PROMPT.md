# One-shot install prompt

Paste the block below into Claude Code on the target Omarchy machine.

````text
Set up iPhone USB tethering on this Omarchy machine, end to end. Do the following without asking questions, and stop only if a step fails:

1. Check current state: `pacman -Q libimobiledevice usbmuxd`, `modinfo ipheth`, and `systemctl is-active NetworkManager`.
2. Install anything missing: `sudo pacman -S --needed --noconfirm libimobiledevice usbmuxd`. Do not install AUR packages. `ipheth` is already in the kernel, so do not install `ipheth-utils`.
3. Load the driver now: `sudo modprobe ipheth`, and confirm with `lsmod | grep ipheth`.
4. Reload udev so usbmuxd's rules apply without a reboot: `sudo udevadm control --reload-rules && sudo udevadm trigger`.
5. Check whether an iPhone is attached: `lsusb | grep -i apple`. If none, tell me to plug it in with a data cable and wait for my reply.
6. If it is attached, run `idevicepair pair`. If it asks me to accept the trust dialog, tell me to unlock the phone and tap Trust, then retry up to 3 times, 10 seconds apart.
7. Run `nmcli device` and `ip -br link` and report whether a new USB Ethernet interface is UP and connected. Then run `ping -c3 archlinux.org`.
8. Finish with a short report: what was installed, what passed, and the manual steps left for me (unplug/replug, tap Trust, enable Settings > Personal Hotspot > Allow Others to Join).

Do not modify any other system configuration.
````
