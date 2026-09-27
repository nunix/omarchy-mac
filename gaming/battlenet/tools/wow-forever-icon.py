# /// script
# requires-python = ">=3.11"
# dependencies = ["opencv-python-headless", "fonttools", "numpy"]
# ///
"""Build the WoW Forever icons from the user's own Battle.net cache.

Blizzard's artwork isn't redistributed; Battle.net downloads the official
icon_wow_forever.svg into its cache once you've logged in. This finds it through
the product data (resource name -> content hash -> Cache/aa/bb/<hash>), then:

  * installs the SVG + PNG sizes as the "wow-forever" hicolor icon
  * traces a monochrome silhouette into a one-glyph font ("WoW Forever Icon",
    U+E000) sized like Omarchy's icon font, for the Omarchy menu row

Usage: uv run wow-forever-icon.py <battlenet-prefix>
"""

import glob
import os
import re
import subprocess
import sys
import tempfile

import cv2
import numpy as np
from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

prefix = sys.argv[1]
cache = os.path.join(prefix, "pfx/drive_c/users/steamuser/AppData/Local/Battle.net/Cache")
home = os.path.expanduser("~")

svg_path = None
pattern = re.compile(rb'"world_of_warcraft#WOW_FOREVER_ICON_SVG":\{"hash":"([0-9a-f]{32})"')
for path in glob.glob(os.path.join(cache, "*/*/*")):
    try:
        with open(path, "rb") as f:
            data = f.read()
    except OSError:
        continue
    for content_hash in pattern.findall(data):
        h = content_hash.decode()
        candidate = os.path.join(cache, h[:2], h[2:4], h)
        if os.path.exists(candidate):
            svg_path = candidate
            break
    if svg_path:
        break

if not svg_path:
    sys.exit("WoW Forever icon not found in the Battle.net cache yet. Log in to Battle.net, open WoW Forever, then re-run.")

icons = os.path.join(home, ".local/share/icons/hicolor")
os.makedirs(os.path.join(icons, "scalable/apps"), exist_ok=True)
with open(svg_path, "rb") as src, open(os.path.join(icons, "scalable/apps/wow-forever.svg"), "wb") as dst:
    dst.write(src.read())
for size in (16, 32, 48, 64, 128, 256, 512):
    out_dir = os.path.join(icons, f"{size}x{size}/apps")
    os.makedirs(out_dir, exist_ok=True)
    subprocess.run(["magick", "-background", "none", "-density", "2400", svg_path,
                    "-resize", f"{size}x{size}", os.path.join(out_dir, "wow-forever.png")], check=True)

# Menu glyph: blue disc becomes the cut-out, badge/W/ribbon become ink.
with tempfile.TemporaryDirectory() as tmp:
    png = os.path.join(tmp, "icon.png")
    subprocess.run(["magick", "-background", "none", "-density", "2400", svg_path,
                    "-resize", "1024x1024", png], check=True)
    img = cv2.imread(png, cv2.IMREAD_UNCHANGED)

bgr, alpha = img[..., :3].astype(int), img[..., 3]
blue = bgr[..., 0] > bgr[..., 2] + 40
ink = ((alpha > 128) & ~blue).astype(np.uint8) * 255
ink = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((3, 3), np.uint8))
contours, _ = cv2.findContours(ink, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)

upm = 1024  # matches /usr/share/fonts/omarchy/omarchy.ttf (1024 em, glyphs fill 0..1024)
scale = upm / 1024.0
pen = TTGlyphPen(None)
for contour in contours:
    if cv2.contourArea(contour) < 30:
        continue
    points = cv2.approxPolyDP(contour, 1.2, True)[:, 0, :]
    points = [(round(x * scale), round((1024 - y) * scale)) for x, y in points][::-1]
    pen.moveTo(points[0])
    for point in points[1:]:
        pen.lineTo(point)
    pen.closePath()

fb = FontBuilder(upm, isTTF=True)
fb.setupGlyphOrder([".notdef", "wowforever"])
fb.setupCharacterMap({0xE000: "wowforever"})
fb.setupGlyf({".notdef": TTGlyphPen(None).glyph(), "wowforever": pen.glyph()})
fb.setupHorizontalMetrics({".notdef": (upm, 0), "wowforever": (upm, 0)})
fb.setupHorizontalHeader(ascent=upm, descent=0)
fb.setupNameTable({"familyName": "WoW Forever Icon", "styleName": "Regular"})
fb.setupOS2(sTypoAscender=upm, sTypoDescender=0, usWinAscent=upm, usWinDescent=0)
fb.setupPost()
fonts = os.path.join(home, ".local/share/fonts")
os.makedirs(fonts, exist_ok=True)
fb.save(os.path.join(fonts, "wowforever-icon.ttf"))

print("Installed wow-forever icons and the 'WoW Forever Icon' menu font.")
