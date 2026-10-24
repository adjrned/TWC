"""Regenerate assets/bg.png (920x510) for TW Companion, laid out like the TWRPG
site: a sidebar (--bg2) with the stacked Cinzel wordmark and a footer divider,
the page background (--bg), and a page-header divider. Colours are the site's
tokens (src/styles/base.css) and must match the C palette in tw-companion.ahk;
geometry must match W, H, SIDE_W and CX there.
Requires Pillow:  py -m pip install Pillow
Run from the assets/ folder:  py generate_bg.py
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 920, 510
SIDE_W = 190          # sidebar width
CX = 214              # content left edge (page header, controls)
DIVIDER_Y = 90        # line under the page header
FOOTER_Y = H - 76     # line above the sidebar footer

BG = (12, 13, 16)          # --bg
SIDE = (18, 20, 25)        # --bg2
BORDER = (35, 38, 46)      # --border
TEXT = (230, 228, 223)     # --text
ACCENT = (245, 166, 35)    # --accent
MUTED = (111, 115, 128)    # --muted


def cinzel(size):
    f = ImageFont.truetype("Cinzel.ttf", size)
    f.set_variation_by_axes([700])
    return f


def spaced_width(d, s, fnt, spacing):
    return sum(d.textlength(ch, font=fnt) + spacing for ch in s) - spacing


def spaced_text(d, x, y, s, fnt, fill, spacing):
    """Draw s letter by letter with extra spacing (CSS letter-spacing)."""
    for ch in s:
        d.text((x, y), ch, font=fnt, fill=fill)
        x += d.textlength(ch, font=fnt) + spacing
    return x


img = Image.new("RGB", (W, H), BG)
d = ImageDraw.Draw(img)

# sidebar + its right border and footer divider, like .sidebar / .sidebar-footer
d.rectangle([0, 0, SIDE_W - 1, H], fill=SIDE)
d.line([SIDE_W, 0, SIDE_W, H], fill=BORDER, width=1)
d.line([0, FOOTER_Y, SIDE_W - 1, FOOTER_Y], fill=BORDER, width=1)

# wordmark, stacked like .sidebar-logo: big "TW" in the accent, small spaced
# "COMPANION" underneath (the site's "TWRPG / COMPANION")
logo, sp = cinzel(24), 2
spaced_text(d, (SIDE_W - spaced_width(d, "TW", logo, sp)) / 2, 16, "TW", logo, ACCENT, sp)
small, sp = ImageFont.truetype("C:/Windows/Fonts/segoeui.ttf", 10), 3.5
spaced_text(d, (SIDE_W - spaced_width(d, "COMPANION", small, sp)) / 2, 52, "COMPANION", small, MUTED, sp)

# page header divider, like .page-header's border-bottom
d.line([CX, DIVIDER_Y, W - 24, DIVIDER_Y], fill=BORDER, width=1)

img.save("bg.png", "PNG")
print("wrote bg.png", img.size)
