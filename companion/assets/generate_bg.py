"""Regenerate assets/bg.png (880x510) and its sharper copies for display
scaling (bg@125.png ... bg@200.png) for TW Companion, laid out like the TWRPG
site: a sidebar (--bg2) with the Cinzel "TWC" wordmark and a footer divider,
the page background (--bg), and a page-header divider. Colours are the site's
tokens (src/styles/base.css) and must match the C palette in tw-companion.ahk;
geometry must match W, H, SIDE_W and CX there. The window picks the copy for
the screen's scale, so the wordmark and lines are drawn at real pixels rather
than stretched from the 100% image.
Requires Pillow:  py -m pip install Pillow
Run from the assets/ folder:  py generate_bg.py
"""
from PIL import Image, ImageDraw, ImageFont

W, H = 880, 510
SIDE_W = 150          # sidebar width
CX = 174              # content left edge (page header, controls)
DIVIDER_Y = 62        # line under the toolbar row (page title + controls)
FOOTER_Y = H - 76     # line above the sidebar footer

BG = (12, 13, 16)          # --bg
SIDE = (18, 20, 25)        # --bg2
BORDER = (35, 38, 46)      # --border
TEXT = (230, 228, 223)     # --text
ACCENT = (245, 166, 35)    # --accent


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


SCALES = [100, 125, 150, 175, 200]


def render(pct):
    k = pct / 100
    px = lambda v: round(v * k)
    lw = max(1, round(k))                   # 1px lines stay crisp
    img = Image.new("RGB", (px(W), px(H)), BG)
    d = ImageDraw.Draw(img)

    # sidebar + its right border and footer divider, like .sidebar / .sidebar-footer
    d.rectangle([0, 0, px(SIDE_W) - 1, px(H)], fill=SIDE)
    d.rectangle([px(SIDE_W), 0, px(SIDE_W) + lw - 1, px(H)], fill=BORDER)
    d.rectangle([0, px(FOOTER_Y), px(SIDE_W) - 1, px(FOOTER_Y) + lw - 1], fill=BORDER)

    # wordmark "TWC", styled like the site's logo (<span>TW</span>RPG): "TW" in
    # the accent, the rest in text colour
    logo, sp = cinzel(26 * k), 3 * k
    x = (px(SIDE_W) - spaced_width(d, "TWC", logo, sp)) / 2
    x = spaced_text(d, x, px(24), "TW", logo, ACCENT, sp)
    spaced_text(d, x, px(24), "C", logo, TEXT, sp)

    # toolbar divider, like .page-header's border-bottom
    d.rectangle([px(CX), px(DIVIDER_Y), px(W - 24), px(DIVIDER_Y) + lw - 1], fill=BORDER)

    name = "bg.png" if pct == 100 else f"bg@{pct}.png"
    img.save(name, "PNG")
    print("wrote", name, img.size)


for pct in SCALES:
    render(pct)
