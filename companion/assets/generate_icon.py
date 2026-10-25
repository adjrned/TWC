"""Regenerate assets/twc.ico, TW Companion's icon (tray, windows, the exe):
the TWRPG site's favicon, a gold "TW" on a dark rounded square, in the
companion's Cinzel. Every size is drawn at its own pixels (not scaled down
from the big one), and stored as PNG entries in one .ico.
Requires Pillow:  py -m pip install Pillow
Run from the assets/ folder:  py generate_icon.py
"""
import io
import struct
from PIL import Image, ImageDraw, ImageFont

BG = (12, 13, 16)          # --bg
FRAME = (48, 52, 62)       # --border2
ACCENT = (245, 166, 35)    # --accent
SIZES = [16, 20, 24, 32, 40, 48, 64, 128, 256]


def cinzel(size):
    f = ImageFont.truetype("Cinzel.ttf", size)
    f.set_variation_by_axes([700])
    return f


def draw(n):
    s = 8                                          # drawn 8x larger, then reduced: smooth edges
    big = Image.new("RGBA", (n * s, n * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(big)
    r = round(n * s * 0.19)
    d.rounded_rectangle([0, 0, n * s - 1, n * s - 1], r, fill=BG + (255,), outline=FRAME + (255,), width=max(s, n * s // 32))
    # the text as wide as fits: about 82% of the square, centred on its ink
    size = n * s
    for _ in range(40):
        f = cinzel(size)
        x0, y0, x1, y1 = d.textbbox((0, 0), "TW", font=f)
        if x1 - x0 <= n * s * (0.80 if n >= 32 else 0.88):
            break
        size = int(size * 0.95)
    d.text(((n * s - (x1 - x0)) / 2 - x0, (n * s - (y1 - y0)) / 2 - y0), "TW", font=f, fill=ACCENT + (255,))
    return big.resize((n, n), Image.LANCZOS)


def ico(images):
    pngs = []
    for im in images:
        b = io.BytesIO()
        im.save(b, "PNG")
        pngs.append(b.getvalue())
    out = struct.pack("<HHH", 0, 1, len(images))
    offset = 6 + 16 * len(images)
    for im, data in zip(images, pngs):
        w = im.width if im.width < 256 else 0
        out += struct.pack("<BBBBHHII", w, w, 0, 0, 1, 32, len(data), offset)
        offset += len(data)
    return out + b"".join(pngs)


if __name__ == "__main__":
    imgs = [draw(n) for n in SIZES]
    with open("twc.ico", "wb") as fh:
        fh.write(ico(imgs))
    print("twc.ico:", ", ".join(str(n) for n in SIZES))
