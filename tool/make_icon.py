"""Renders the app icon (python3 tool/make_icon.py, needs Pillow).

Writes assets/icon/icon.png (full icon, iOS + legacy Android) and
assets/icon/foreground.png / background.png (Android adaptive icon).
"""
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont

S = 4096  # supersampled, scaled down to 1024 at the end
OUT = 1024
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'


def background():
    img = Image.new('RGB', (S, S))
    top, bottom = (92, 107, 192), (26, 35, 126)
    # Diagonal gradient via a small image that is scaled up.
    small = Image.new('RGB', (64, 64))
    sp = small.load()
    for y in range(64):
        for x in range(64):
            t = (x + y) / 126
            sp[x, y] = tuple(int(a + (b - a) * t) for a, b in zip(top, bottom))
    return small.resize((S, S), Image.BICUBIC)


def rotated_rect(cx, cy, w, h, r, angle):
    """Rounded square drawn on its own layer and rotated."""
    layer = Image.new('L', (S, S), 0)
    d = ImageDraw.Draw(layer)
    d.rounded_rectangle((cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2), r, fill=255)
    return layer.rotate(angle, center=(cx, cy), resample=Image.BICUBIC)


def foreground(scale):
    """Die + 8-ball, [scale] = size relative to the canvas."""
    fg = Image.new('RGBA', (S, S), (0, 0, 0, 0))
    k = S * scale
    c = S / 2

    # Die
    dcx, dcy, dw, ang = c - 0.13 * k, c - 0.10 * k, 0.56 * k, 14
    shadow = rotated_rect(dcx + 0.025 * k, dcy + 0.04 * k, dw, dw, 0.12 * k, ang)
    shadow = shadow.filter(ImageFilter.GaussianBlur(0.03 * k))
    fg.paste((0, 0, 0, 110), (0, 0), shadow)
    die = rotated_rect(dcx, dcy, dw, dw, 0.12 * k, ang)
    fg.paste((255, 255, 255, 255), (0, 0), die)
    pips = Image.new('L', (S, S), 0)
    pd = ImageDraw.Draw(pips)
    pr = 0.055 * k
    for fx, fy in [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)]:
        x, y = dcx + fx * 0.27 * dw, dcy + fy * 0.27 * dw
        pd.ellipse((x - pr, y - pr, x + pr, y + pr), fill=255)
    pips = pips.rotate(ang, center=(dcx, dcy), resample=Image.BICUBIC)
    fg.paste((40, 53, 147, 255), (0, 0), pips)

    # 8-ball
    bx, by, br = c + 0.21 * k, c + 0.20 * k, 0.24 * k
    sh = Image.new('L', (S, S), 0)
    ImageDraw.Draw(sh).ellipse(
        (bx - br + 0.02 * k, by - br + 0.04 * k, bx + br + 0.02 * k, by + br + 0.04 * k),
        fill=255,
    )
    fg.paste((0, 0, 0, 110), (0, 0), sh.filter(ImageFilter.GaussianBlur(0.03 * k)))
    d = ImageDraw.Draw(fg)
    d.ellipse((bx - br, by - br, bx + br, by + br), fill=(20, 20, 24, 255))
    # Shine
    hl = Image.new('L', (S, S), 0)
    ImageDraw.Draw(hl).ellipse(
        (bx - 0.75 * br, by - 0.85 * br, bx - 0.05 * br, by - 0.35 * br), fill=90
    )
    fg.paste((255, 255, 255, 255), (0, 0), hl.filter(ImageFilter.GaussianBlur(0.04 * k)))
    d = ImageDraw.Draw(fg)
    wr = 0.48 * br
    wx, wy = bx + 0.12 * br, by - 0.05 * br
    d.ellipse((wx - wr, wy - wr, wx + wr, wy + wr), fill=(255, 255, 255, 255))
    font = ImageFont.truetype(FONT, int(wr * 1.35))
    d.text((wx, wy), '8', font=font, fill=(20, 20, 24, 255), anchor='mm')
    return fg


def save(img, name, mode):
    img.resize((OUT, OUT), Image.LANCZOS).convert(mode).save(f'assets/icon/{name}')


bg = background()
full = bg.convert('RGBA')
full.alpha_composite(foreground(0.8))
save(full, 'icon.png', 'RGB')
save(bg, 'background.png', 'RGB')
# Adaptive icons: flutter_launcher_icons insets this layer by 16 % per side.
save(foreground(0.8), 'foreground.png', 'RGBA')
