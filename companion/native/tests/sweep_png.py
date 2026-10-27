# python -I sweep_png.py <sweep.txt> <out.png> [zoom]: draws tool_sweep.exe's squares over stand-in
# icons, one row per button size, one column per fraction to come; at 1080p (1 UI unit = 1800 px:
# the UI is 0.6 high), times zoom (default 3) so the steps show.
import sys
from PIL import Image, ImageDraw

src, out = sys.argv[1], sys.argv[2]
zoom = float(sys.argv[3]) if len(sys.argv) > 3 else 3
px = 1800 * zoom
cases = {}
for line in open(src):
    p = line.split()
    key = (int(p[0]), float(p[1]), float(p[2]), float(p[3]))
    cases.setdefault(key, [])
    if p[4] != 'end':
        cases[key].append(tuple(map(float, p[4:8])))
rows = sorted({k[0] for k in cases})
fracs = sorted({k[3] for k in cases}, reverse=True)
cell = int(0.045 * px)
W, H = cell * len(fracs) + 20, (cell + 24) * len(rows) + 10
img = Image.new('RGB', (W, H), (24, 24, 30))
d = ImageDraw.Draw(img)
for ri, r in enumerate(rows):
    for fi, f in enumerate(fracs):
        key = next(k for k in cases if k[0] == r and k[3] == f)
        bw, bh = key[1] * px, key[2] * px
        x0, y0 = 10 + fi * cell + (cell - bw) / 2, 10 + ri * (cell + 24)
        # a stand-in icon: a warm gradient with a lighter diagonal, so the 60% black shows as a tint
        icon = Image.new('RGB', (max(1, int(bw)), max(1, int(bh))))
        for y in range(icon.height):
            for x in range(icon.width):
                t = (x + y) / (icon.width + icon.height)
                icon.putpixel((x, y), (int(200 - 80 * t), int(120 + 60 * t), int(40 + 120 * t)))
        shade = Image.new('L', icon.size, 0)
        sd = ImageDraw.Draw(shade)
        for (x, y, w, h) in cases[key]:
            x0p, y0p = round(x * px), round(y * px)
            x1p, y1p = round((x + w) * px), round((y + h) * px)
            if x1p > x0p and y1p > y0p:     # as the game fills pixels: whole ones, by their centres
                sd.rectangle([x0p, y0p, x1p - 1, y1p - 1], fill=0x99)
        dark = Image.new('RGB', icon.size, (0, 0, 0))
        icon = Image.composite(dark, icon, shade)
        img.paste(icon, (int(x0), int(y0)))
        d.rectangle([x0 - 1, y0 - 1, x0 + bw, y0 + bh], outline=(200, 200, 200))
        d.text((x0, y0 + bh + 4), f'{f:.3g} ({len(cases[key])})', fill=(220, 220, 220))
img.save(out)
print(f'{out}: {len(rows)} sizes x {len(fracs)} fractions')
