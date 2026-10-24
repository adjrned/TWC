"""Regenerate assets/bg.png (904x500) for TW Companion, laid out like the TWRPG
site: a sidebar (--bg2) with the Cinzel wordmark, a content surface, and a
page-header divider. Colours are the site's tokens (src/styles/base.css) and
must match the C palette in tw-companion.ahk; geometry must match W, H, SIDE_W
and CX there.
Requires Pillow:  py -m pip install Pillow
Run from the assets/ folder:  py generate_bg.py
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 904, 500
SIDE_W = 176          # sidebar width
CX = 200              # content left edge (page header, controls)
DIVIDER_Y = 84        # line under the page header

SIDE = (18, 20, 25)        # --bg2
PANEL = (22, 24, 29)       # content surface (C.panel)
BORDER = (35, 38, 46)      # --border
TEXT = (230, 228, 223)     # --text
ACCENT = (245, 166, 35)    # --accent


def cinzel(size):
    f = ImageFont.truetype("Cinzel.ttf", size)
    f.set_variation_by_axes([700])
    return f


def spaced_text(d, x, y, s, fnt, fill, spacing):
    """Draw s letter by letter with extra spacing (CSS letter-spacing)."""
    for ch in s:
        d.text((x, y), ch, font=fnt, fill=fill)
        x += d.textlength(ch, font=fnt) + spacing
    return x


img = Image.new("RGB", (W, H), PANEL)
d = ImageDraw.Draw(img)

# sidebar + its right border, like .sidebar
d.rectangle([0, 0, SIDE_W - 1, H], fill=SIDE)
d.line([SIDE_W, 0, SIDE_W, H], fill=BORDER, width=1)

# wordmark: "TW" in the accent, "Companion" in text colour (site logo style)
logo = cinzel(16)
x = spaced_text(d, 22, 28, "TW", logo, ACCENT, 0.5)
spaced_text(d, x, 28, "Companion", logo, TEXT, 0.5)
d.line([12, 66, SIDE_W - 13, 66], fill=BORDER, width=1)

# page header divider, like .page-header's border-bottom
d.line([CX, DIVIDER_Y, W - 24, DIVIDER_Y], fill=BORDER, width=1)

img.save("bg.png", "PNG")
print("wrote bg.png", img.size)
