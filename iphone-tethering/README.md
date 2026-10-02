# iPhone USB tethering on Omarchy

Omarchy did not ship everything needed to tether an iPhone over USB. This branch adds the missing pieces.

## What was missing

| Piece | Status on stock Omarchy | Role |
| --- | --- | --- |
| `ipheth` kernel module | Present (mainline kernel) | Exposes the iPhone's hotspot as a USB Ethernet interface |
| `libimobiledevice` | Present only as a side dependency | Talks the Apple lockdown/pairing protocol |
| `usbmuxd` | **Missing** | Daemon that multiplexes USB connections to Apple devices and handles the "Trust This Computer" pairing; its udev rules start it when an iPhone is plugged in |
| NetworkManager | Present | Brings up the new interface with DHCP automatically |

This branch:

- adds `libimobiledevice` and `usbmuxd` to `install/omarchy-base.packages` (fresh installs)
- adds a migration that installs both on existing installs via `omarchy update`

No service needs enabling: `usbmuxd` ships a udev rule that starts it on demand. `ipheth` loads automatically when an iPhone is detected.

## What a human must do

Software cannot do these steps for you:

1. Install the packages: `sudo pacman -S --needed libimobiledevice usbmuxd` (or run `omarchy update` on this branch).
2. Unplug the iPhone, then plug it back in with a data-capable USB cable (some charge-only cables will not work).
3. Unlock the iPhone and tap **Trust** on the "Trust This Computer?" prompt, then enter the passcode.
4. On the iPhone: **Settings > Personal Hotspot > Allow Others to Join**.
5. A new wired connection (interface like `enp…u…`) should appear in NetworkManager. Check the Omarchy network menu or run `nmcli device`.

## Verify

```bash
systemctl status usbmuxd        # active after plugging in the phone
idevicepair pair                # "SUCCESS: Paired with device ..."
ip -br link | grep -i enp       # new USB interface, state UP
nmcli device                    # shows it as "connected"
ping -c3 archlinux.org
```

## Troubleshooting

- **Trust prompt never appears**: try another cable or port, then `sudo systemctl restart usbmuxd`, replug.
- **`idevicepair` says "Please accept the trust dialog"**: unlock the phone and tap Trust, then rerun.
- **Interface exists but no IP**: toggle Personal Hotspot off and on, or `nmcli device connect <iface>`.
- **No interface at all**: check `lsmod | grep ipheth`; if missing, `sudo modprobe ipheth` and check `dmesg | tail`.
- **Pairing errors after an iOS update**: `idevicepair unpair && idevicepair pair`.
- **Reset everything**: `sudo rm -rf /var/lib/lockdown/*`, replug, and trust again.

## One-shot install

See [`INSTALL-PROMPT.md`](INSTALL-PROMPT.md) for a prompt you can hand to Claude Code to do all the automatable steps in one go.
