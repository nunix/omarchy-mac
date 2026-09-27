#!/bin/bash
# Battle.net + WoW Forever on Omarchy for Apple Silicon (Asahi Linux).
#
# Installs and wires up: patched FEX (x86 emulation), an XEmbed->SNI tray bridge,
# x86_64 MangoHud, the muvm/Proton launchers, desktop entries, Omarchy menu rows
# and the bar tray pin. Everything user-level lands in ~/.local and ~/.config;
# only distro packages need sudo. Safe to re-run.
#
# See README.md next to this script for what each piece does and why.

set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Pinned sources (tested together on an M1 Pro, 2026-09-27)
FEX_REPO=https://github.com/FEX-Emu/FEX.git
FEX_COMMIT=59f85d6b7df4eb053d2cc1b9d33411b4f31bfbaa # main after FEX-2609
XSP_REPO=https://github.com/BLumia/xembed-sni-proxy.git
XSP_COMMIT=c3afbd4c1d26a19622cd7c2cae3db3d35fdd0d33
ECM_REPO=https://invent.kde.org/frameworks/extra-cmake-modules.git
ECM_TAG=v6.30.0
MANGOHUD_VERSION=0.8.4
MANGOHUD_TARBALL=MangoHud-0.8.4.r0.g992103e.tar.gz
BATTLENET_INSTALLER_URL="https://downloader.battle.net/download/getInstallerForGame?os=win&gameProgram=BATTLENET_APP&version=Live"
PROTON_EXPERIMENTAL_APPID=1493710

OPT="$HOME/.local/opt/omarchy-battlenet"
SRC="$HOME/.cache/omarchy-battlenet/src"
CONFIG_DIR="$HOME/.config/omarchy-battlenet"
STEAM_ROOT="$HOME/.local/share/Steam"

prefix=""
proton_dir="$STEAM_ROOT/steamapps/common/Proton - Experimental"
rebuild=0
run_setup=1
hide_steam=0
only_icons=0
render_scale=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Options:
  --prefix DIR          Proton prefix for Battle.net (STEAM_COMPAT_DATA_PATH, contains pfx/).
                        Default: an existing Steam prefix that has Battle.net, else
                        ~/Games/battlenet-proton
  --proton DIR          Proton to use (default: Steam's "Proton - Experimental")
  --rebuild             Rebuild FEX and the tray bridge even if already installed
  --no-battlenet-setup  Don't download/run the Battle.net installer
  --hide-steam          Hide Steam from the app launcher (it stays installed)
  --icons               Only (re)build the WoW Forever icons from the Battle.net cache
  --render-scale X      Only set WoW Forever's render scale (e.g. 0.75) with FSR 1.0
                        upscaling. WoW must be closed.
  -h, --help            Show this help
EOF
}

while (($#)); do
  case $1 in
    --prefix) prefix=$2; shift ;;
    --proton) proton_dir=$2; shift ;;
    --rebuild) rebuild=1 ;;
    --no-battlenet-setup) run_setup=0 ;;
    --hide-steam) hide_steam=1 ;;
    --icons) only_icons=1 ;;
    --render-scale) render_scale=$2; shift ;;
    -h | --help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
  shift
done

step() { printf '\n\033[1;32m==> %s\033[0m\n' "$*"; }
note() { printf '    %s\n' "$*"; }
die() { printf '\033[1;31mError:\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Prefix detection / config
# ---------------------------------------------------------------------------

detect_prefix() {
  local found
  found=$(find "$STEAM_ROOT/steamapps/compatdata" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
    [[ -e "$dir/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe" ]] && echo "$dir" && break
  done || true)
  echo "${found:-$HOME/Games/battlenet-proton}"
}

write_config() {
  mkdir -p "$CONFIG_DIR"
  cat > "$CONFIG_DIR/env" <<EOF
# Written by gaming/battlenet/install.sh
BATTLENET_PREFIX="$prefix"
PROTON_DIR="$proton_dir"
OMARCHY_BATTLENET_OPT="$OPT"
EOF
}

if [[ -z $prefix && -f $CONFIG_DIR/env ]]; then
  prefix=$(source "$CONFIG_DIR/env" && echo "$BATTLENET_PREFIX")
fi
[[ -n $prefix ]] || prefix=$(detect_prefix)

# ---------------------------------------------------------------------------
# Sub-commands
# ---------------------------------------------------------------------------

build_icons() {
  step "Building WoW Forever icons from your Battle.net cache"
  if ! command -v uv >/dev/null; then
    note "uv not found (install it with: omarchy pkg add uv). Skipping; the menu uses a generic glyph."
    return 0
  fi
  if uv run --quiet "$HERE/tools/wow-forever-icon.py" "$prefix"; then
    fc-cache -f "$HOME/.local/share/fonts" >/dev/null
    gtk-update-icon-cache -q -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
    set_menu_wow_glyph
    note "Restart the shell to load the new menu font: omarchy restart shell"
  else
    note "Not available yet. Re-run with --icons after logging in to Battle.net."
  fi
}

set_render_scale() {
  local cfg="$prefix/pfx/drive_c/Program Files (x86)/World of Warcraft/_classic_beta_/WTF/Config.wtf"
  step "Setting WoW Forever render scale to $render_scale (FSR 1.0 upscaling)"
  [[ -f $cfg ]] || die "$cfg not found. Start WoW Forever once first."
  if hyprctl clients -j | jq -e '.[] | select(.class == "steam_proton" and .title == "World of Warcraft")' >/dev/null; then
    die "WoW is running; quit it first (it rewrites Config.wtf on exit)."
  fi
  cp "$cfg" "$cfg.bak-$(date +%Y%m%d-%H%M%S)"
  local kv key value
  for kv in "RenderScale $render_scale" "ResampleQuality 3"; do
    key=${kv% *}
    value=${kv#* }
    if grep -qi "^SET $key " "$cfg"; then
      sed -i "s/^SET $key .*$/SET $key \"$value\"\r/I" "$cfg" # Config.wtf uses CRLF
    else
      printf 'SET %s "%s"\r\n' "$key" "$value" >> "$cfg"
    fi
  done
  note "Done. Takes effect on the next WoW launch."
}

# ---------------------------------------------------------------------------
# Omarchy integration helpers
# ---------------------------------------------------------------------------

menu_file="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"

# Default glyph for a stock Omarchy menu row (keeps the exact Nerd Font codepoint).
stock_glyph() {
  python3 - "$1" <<'EOF'
import re, sys
text = open("/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc", encoding="utf-8").read()
m = re.search(r'"%s":\s*\{"icon":"([^"]*)"' % re.escape(sys.argv[1]), text)
print(m.group(1) if m else "")
EOF
}

# Insert or replace a top-level entry in the user's menu extension (JSONC).
menu_set() {
  python3 - "$menu_file" "$1" "$2" <<'EOF'
import os, re, sys
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3]
if os.path.exists(path):
    text = open(path, encoding="utf-8").read()
else:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    text = "{\n}\n"
line = '  "%s": %s,' % (key, value)
pattern = re.compile(r'^\s*"%s":.*$' % re.escape(key), re.M)
if pattern.search(text):
    text = pattern.sub(lambda _: line, text, count=1)
else:
    end = text.rstrip().rfind("}")
    text = text[:end].rstrip("\n") + "\n" + line + "\n}\n"
open(path, "w", encoding="utf-8").write(text)
EOF
}

set_menu_wow_glyph() {
  if fc-list | grep -q "WoW Forever Icon"; then
    menu_set "gaming.wow-forever" "{\"icon\":\"$(printf '\ue000')\",\"iconFont\":\"WoW Forever Icon\",\"label\":\"WoW Forever\",\"description\":\"World of Warcraft Forever via muvm + FEX + Proton\",\"action\":\"setsid -f ~/.local/bin/wow-forever\"}"
  fi
}

if ((only_icons)); then
  build_icons
  exit 0
fi
if [[ -n $render_scale ]]; then
  set_render_scale
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Preflight
# ---------------------------------------------------------------------------

step "Checking the machine"
[[ $(uname -m) == aarch64 ]] || die "This is for Apple Silicon (aarch64) running Asahi Linux."
page_size=$(getconf PAGESIZE)
[[ $page_size == 16384 ]] || note "Page size is $page_size (expected 16K on Apple Silicon); continuing anyway."
command -v omarchy >/dev/null || die "Omarchy not found."
command -v hyprctl >/dev/null || die "Hyprland not found."
note "Prefix: $prefix"
note "Proton: $proton_dir"

# ---------------------------------------------------------------------------
# 2. Packages
# ---------------------------------------------------------------------------

step "Installing packages"
packages=(
  muvm FEX-Emu fex-emu-rootfs-arch mesa-fex-emu-overlay-x86_64 mesa-fex-emu-overlay-i386 steam
  git cmake ninja clang lld nasm python jq curl
  qt6-base kwindowsystem libxtst xcb-util xcb-util-image
)
missing=()
for pkg in "${packages[@]}"; do
  pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if ((${#missing[@]})); then
  note "Installing: ${missing[*]}"
  if command -v omarchy-pkg-add >/dev/null; then
    omarchy-pkg-add "${missing[@]}"
  else
    sudo pacman -S --needed --noconfirm "${missing[@]}"
  fi
else
  note "All present."
fi

# ---------------------------------------------------------------------------
# 3. Proton (comes from Steam)
# ---------------------------------------------------------------------------

step "Checking Proton"
if [[ ! -x "$proton_dir/proton" ]]; then
  cat <<EOF
    Proton Experimental isn't installed yet. It's downloaded by Steam:
      1. Run: steam        (Asahi's Steam runs in muvm; log in once)
      2. Run: steam steam://install/$PROTON_EXPERIMENTAL_APPID
      3. Wait for the download, then re-run this script.
EOF
  exit 1
fi
note "Found $(cat "$proton_dir/version" 2>/dev/null || echo "$proton_dir")"

# ---------------------------------------------------------------------------
# 4. Patched FEX
# ---------------------------------------------------------------------------

step "Building FEX $FEX_COMMIT + PR #5785 (instruction fetch fault address)"
if [[ -x $OPT/fex/bin/FEX && $rebuild == 0 ]]; then
  note "Already installed in $OPT/fex (use --rebuild to force)."
else
  rm -rf "$SRC/FEX"
  mkdir -p "$SRC/FEX"
  git -C "$SRC/FEX" init -q
  git -C "$SRC/FEX" remote add origin "$FEX_REPO"
  git -C "$SRC/FEX" fetch -q --depth 1 origin "$FEX_COMMIT"
  git -C "$SRC/FEX" checkout -q FETCH_HEAD
  git -C "$SRC/FEX" submodule update -q --init --recursive --depth 1
  git -C "$SRC/FEX" apply "$HERE/patches/fex-pr5785-instruction-fetch-fault-address.patch"
  CC=clang CXX=clang++ cmake -S "$SRC/FEX" -B "$SRC/FEX/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DUSE_LINKER=lld -DENABLE_LTO=True \
    -DBUILD_TESTING=False -DBUILD_THUNKS=False -DBUILD_FEXCONFIG=False \
    -DCMAKE_INSTALL_PREFIX="$OPT/fex" >/dev/null
  cmake --build "$SRC/FEX/build"
  cmake --install "$SRC/FEX/build" >/dev/null
fi
# muvm 0.6.0 looks up "FEXInterpreter", later releases "FEX" (the launcher also
# puts $OPT/fex/bin first in PATH for those).
ln -sfn FEX "$OPT/fex/bin/FEXInterpreter"
mkdir -p "$HOME/.local/bin"
ln -sfn "$OPT/fex/bin/FEX" "$HOME/.local/bin/FEXInterpreter"

# ---------------------------------------------------------------------------
# 5. XEmbed -> StatusNotifierItem tray bridge
# ---------------------------------------------------------------------------

step "Building xembed-sni-proxy (Wine tray icon -> Omarchy bar)"
if [[ -x $OPT/xembed-sni-proxy/bin/xembedsniproxy && $rebuild == 0 ]]; then
  note "Already installed in $OPT/xembed-sni-proxy (use --rebuild to force)."
else
  rm -rf "$SRC/extra-cmake-modules" "$SRC/xembed-sni-proxy"
  git clone -q --depth 1 --branch "$ECM_TAG" "$ECM_REPO" "$SRC/extra-cmake-modules" 2>/dev/null
  cmake -S "$SRC/extra-cmake-modules" -B "$SRC/extra-cmake-modules/build" \
    -DCMAKE_INSTALL_PREFIX="$OPT/ecm" -DBUILD_TESTING=OFF -DBUILD_DOC=OFF \
    -DBUILD_HTML_DOCS=OFF -DBUILD_MAN_DOCS=OFF -DBUILD_QTHELP_DOCS=OFF >/dev/null
  cmake --install "$SRC/extra-cmake-modules/build" >/dev/null

  git clone -q "$XSP_REPO" "$SRC/xembed-sni-proxy"
  git -C "$SRC/xembed-sni-proxy" checkout -q "$XSP_COMMIT"
  git -C "$SRC/xembed-sni-proxy" apply "$HERE/patches/xembed-sni-proxy-wine-tray.patch"
  cmake -S "$SRC/xembed-sni-proxy" -B "$SRC/xembed-sni-proxy/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="$OPT/ecm" \
    -DCMAKE_INSTALL_PREFIX="$OPT/xembed-sni-proxy" >/dev/null
  cmake --build "$SRC/xembed-sni-proxy/build"
  cmake --install "$SRC/xembed-sni-proxy/build" >/dev/null
fi

# ---------------------------------------------------------------------------
# 6. MangoHud (x86_64 build, loaded inside the VM)
# ---------------------------------------------------------------------------

step "Installing MangoHud $MANGOHUD_VERSION (x86_64)"
if [[ -f $OPT/mangohud/lib64/libMangoHud.so && $rebuild == 0 ]]; then
  note "Already installed in $OPT/mangohud."
else
  tmp=$(mktemp -d)
  curl -fsSL -o "$tmp/mh.tar.gz" \
    "https://github.com/flightlessmango/MangoHud/releases/download/v$MANGOHUD_VERSION/$MANGOHUD_TARBALL"
  tar -xzf "$tmp/mh.tar.gz" -C "$tmp"
  mkdir -p "$tmp/pkg"
  tar -xf "$tmp/MangoHud/MangoHud-package.tar" -C "$tmp/pkg"
  rm -rf "$OPT/mangohud"
  mkdir -p "$OPT/mangohud/layers"
  cp -a "$tmp/pkg/usr/lib/mangohud/lib64" "$tmp/pkg/usr/lib/mangohud/lib32" "$OPT/mangohud/"
  for arch in x86_64:lib64 x86:lib32; do
    sed "s#/usr/lib/mangohud/${arch#*:}/#$OPT/mangohud/${arch#*:}/#" \
      "$tmp/pkg/usr/share/vulkan/implicit_layer.d/MangoHud.${arch%%:*}.json" \
      > "$OPT/mangohud/layers/MangoHud.${arch%%:*}.json"
  done
  rm -rf "$tmp"
fi
mkdir -p "$HOME/.config/MangoHud"
if [[ ! -f $HOME/.config/MangoHud/MangoHud.conf ]]; then
  cp "$HERE/config/MangoHud.conf" "$HOME/.config/MangoHud/MangoHud.conf"
else
  note "Keeping your existing ~/.config/MangoHud/MangoHud.conf"
fi

# ---------------------------------------------------------------------------
# 7. Launchers, desktop entries
# ---------------------------------------------------------------------------

step "Installing launchers and desktop entries"
write_config
install -m 755 "$HERE/bin/muvm-proton-run" "$HERE/bin/battlenet" "$HERE/bin/wow-forever" "$HOME/.local/bin/"
mkdir -p "$HOME/.local/share/applications"
for app in battlenet wow-forever; do
  sed "s#@HOME@#$HOME#g" "$HERE/applications/$app.desktop" > "$HOME/.local/share/applications/$app.desktop"
done
if ((hide_steam)) && [[ -f /usr/share/applications/steam.desktop ]]; then
  sed '/^\[Desktop Entry\]/a NoDisplay=true' /usr/share/applications/steam.desktop > "$HOME/.local/share/applications/steam.desktop"
  note "Steam hidden from the launcher (delete ~/.local/share/applications/steam.desktop to undo)."
fi
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true

# ---------------------------------------------------------------------------
# 8. Omarchy menu + bar tray
# ---------------------------------------------------------------------------

step "Adding Menu > Gaming entries"
[[ -f $menu_file ]] && cp "$menu_file" "$menu_file.bak.$(date +%s)"
gaming_glyph=$(stock_glyph install.gaming)
battlenet_glyph=$(stock_glyph install.gaming.battlenet)
# Omarchy's own Battle.net installer is x86-only; hide its rows on this machine.
menu_set "install.gaming.battlenet" '{"when":"false"}'
menu_set "remove.gaming.battlenet" '{"when":"false"}'
menu_set "gaming" "{\"icon\":\"$gaming_glyph\",\"label\":\"Gaming\"}"
menu_set "gaming.battlenet" "{\"icon\":\"$battlenet_glyph\",\"label\":\"Battle.net\",\"description\":\"Updates, news and Play via muvm + FEX + Proton\",\"action\":\"setsid -f ~/.local/bin/battlenet\"}"
menu_set "gaming.wow-forever" "{\"icon\":\"$battlenet_glyph\",\"label\":\"WoW Forever\",\"description\":\"World of Warcraft Forever via muvm + FEX + Proton\",\"action\":\"setsid -f ~/.local/bin/wow-forever\"}"
set_menu_wow_glyph

step "Pinning the Battle.net tray icon in the bar"
shell_json="$HOME/.config/omarchy/shell.json"
if [[ -f $shell_json ]] && jq -e '.bar.layout | .. | objects | select(.id? == "omarchy.tray")' "$shell_json" >/dev/null 2>&1; then
  cp "$shell_json" "$shell_json.bak.$(date +%s)"
  # Wine icons are named after their WM_CLASS (steam_proton) by the patched bridge.
  # Fcitx5 also has an XEmbed icon the bridge would surface; hide it.
  jq '(.bar.layout[][] | select(.id? == "omarchy.tray")) |=
        (.pinned = (((.pinned // []) + ["steam_proton"]) | unique)
         | .hidden = (((.hidden // []) + ["Fcitx5 Tray Window"]) | unique))' \
    "$shell_json" > "$shell_json.tmp" && mv "$shell_json.tmp" "$shell_json"
else
  note "No omarchy.tray widget in $shell_json; skipping (the icon still works in the tray drawer)."
fi

# ---------------------------------------------------------------------------
# 9. Battle.net
# ---------------------------------------------------------------------------

battlenet_exe="$prefix/pfx/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
if [[ -e $battlenet_exe ]]; then
  step "Battle.net already installed in $prefix"
elif ((run_setup)); then
  step "Installing Battle.net into $prefix"
  mkdir -p "$prefix" "$HOME/.cache/omarchy-battlenet"
  installer="$HOME/.cache/omarchy-battlenet/Battle.net-Setup.exe"
  curl -fL --retry 3 -o "$installer" "$BATTLENET_INSTALLER_URL"
  note "The Battle.net setup window opens in the VM (first start takes a minute)."
  note "Click through it; when it finishes, log in and install WoW Forever from Battle.net."
  "$HOME/.local/bin/muvm-proton-run" --no-mangohud "$installer" &
fi

# ---------------------------------------------------------------------------
# 10. Icons (needs a Battle.net login first)
# ---------------------------------------------------------------------------

build_icons

step "Done"
cat <<EOF
    Launch from Menu > Gaming (Battle.net / WoW Forever) or run: battlenet, wow-forever
    Logs: ~/.local/state/omarchy-battlenet/
    Once logged in to Battle.net, run '$0 --icons' for the WoW Forever icon.
    Suggested after the first WoW start: '$0 --render-scale 0.75'
EOF
