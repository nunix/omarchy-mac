# Customize the early Asahi/m1n1 boot logo on Apple Silicon Macs.
#
# The package-owned m1n1 binary is never modified. We install root-owned copies
# of the payload, updater, and pacman hook so a user-writable checkout cannot be
# executed as root during a future package transaction.

if [[ -f /usr/lib/asahi-boot/m1n1.bin && -x /usr/bin/update-m1n1 ]]; then
  payload="$OMARCHY_PATH/default/m1n1/m1n1-logo.payload"
  updater="$OMARCHY_PATH/install/config/hardware/omarchy-m1n1-logo-update"
  hook="$OMARCHY_PATH/default/m1n1/99-omarchy-m1n1-logo.hook"

  if [[ ! -f "$payload" || ! -f "$updater" || ! -f "$hook" ]]; then
    echo "Omarchy m1n1 logo files are missing from $OMARCHY_PATH" >&2
    return 1
  fi

  echo "Installing persistent Omarchy m1n1 boot logo"
  sudo install -d -o root -g root -m 0755 \
    /usr/local/libexec \
    /usr/local/share/omarchy \
    /etc/pacman.d/hooks
  sudo install -o root -g root -m 0755 \
    "$updater" /usr/local/libexec/omarchy-m1n1-logo-update
  sudo install -o root -g root -m 0644 \
    "$payload" /usr/local/share/omarchy/m1n1-logo.payload
  sudo install -o root -g root -m 0644 \
    "$hook" /etc/pacman.d/hooks/99-omarchy-m1n1-logo.hook

  sudo /usr/local/libexec/omarchy-m1n1-logo-update
else
  echo "Skipping m1n1 boot logo: Asahi m1n1 is not installed"
fi
