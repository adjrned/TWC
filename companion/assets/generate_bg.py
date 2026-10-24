"""Regenerate assets/bg.png (760x600) for TW Companion.
Requires Pillow:  py -m pip install Pillow
Run from the assets/ folder:  py generate_bg.py
Geometry (panel rect) must match the layout in tw-companion.ahk.
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 760, 600
PX, PY, PW, PH = 20, 86, 720, 470   # central panel


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def glow(cx, cy, r, color, alpha):
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color + (alpha,))
    return layer.filter(ImageFilter.GaussianBlur(r * 0.5))


def font(name, size):
    try:
        return ImageFont.truetype("C:/Windows/Fonts/" + name, size)
    except Exception:
        return ImageFont.load_default()


def spaced(s, n=2):
    return (" " * n).join(list(s))


# gradient base
top, bot = (23, 29, 78), (8, 11, 34)
base = Image.new("RGB", (W, H))
px = base.load()
for y in range(H):
    c = lerp(top, bot, y / (H - 1))
    for x in range(W):
        px[x, y] = c
img = base.convert("RGBA")

# glows
img = Image.alpha_composite(img, glow(110, 40, 300, (232, 201, 119), 60))
img = Image.alpha_composite(img, glow(710, 560, 340, (96, 110, 255), 55))
img = Image.alpha_composite(img, glow(400, 300, 420, (60, 74, 150), 24))

# panel
panel = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(panel).rounded_rectangle(
    [PX, PY, PX + PW, PY + PH], radius=18, fill=(19, 26, 70, 235))
img = Image.alpha_composite(img, panel)
d = ImageDraw.Draw(img)
d.rounded_rectangle([PX, PY, PX + PW, PY + PH], radius=18,
                    outline=(185, 146, 68, 255), width=1)
d.line([PX + 14, PY + 1, PX + PW - 14, PY + 1], fill=(255, 235, 190, 55), width=1)

# brand: gold diamond + wordmark + tagline
cx, cy, r = 38, 34, 7
d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=(236, 208, 138))
d.polygon([(cx, cy - r + 3), (cx + r - 3, cy), (cx, cy + r - 3), (cx - r + 3, cy)], fill=(20, 26, 66))
d.text((54, 21), spaced("TW COMPANION", 2), font=font("seguisb.ttf", 23), fill=(236, 208, 138))
d.text((56, 54), "T W R P G   \u00b7   S A V E   L O A D E R", font=font("segoeui.ttf", 11), fill=(138, 144, 192))

img.convert("RGB").save("bg.png", "PNG")
print("wrote bg.png", img.size)
