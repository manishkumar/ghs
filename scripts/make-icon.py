#!/usr/bin/env python3
"""Draws the ghs app icon and packs it into Resources/AppIcon.icns.

The mark is the product's signature element in miniature: the oxidation rail —
rust at the top where the queue is stale, patina at the bottom where it's fresh
— standing beside the rows it grades. Requires Pillow; the generated .icns is
committed so a normal build doesn't need it.
"""
from PIL import Image, ImageChops, ImageDraw
import subprocess, pathlib, shutil

S = 1024
SS = 4                      # supersample factor for clean curves
W = S * SS
ROOT = pathlib.Path(__file__).resolve().parent.parent

# Same stops as Theme.swift's oxidation ramp.
STOPS = [
    (0.00, (63, 143, 124)),   # patina
    (0.35, (185, 155, 46)),   # brass
    (0.70, (194, 94, 42)),    # oxide
    (1.00, (158, 43, 28)),    # rust
]


def ramp(t):
    t = min(max(t, 0.0), 1.0)
    for (p0, c0), (p1, c1) in zip(STOPS, STOPS[1:]):
        if p0 <= t <= p1:
            f = 0 if p1 == p0 else (t - p0) / (p1 - p0)
            return tuple(int(a + (b - a) * f) for a, b in zip(c0, c1))
    return STOPS[-1][1]


def rounded_mask(size, radius):
    m = Image.new("L", size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return m


def build():
    # Deep graphite body, cool and quiet, so the rail is the only colour in the
    # mark. Blue-tinted rather than neutral so it doesn't read as flat black.
    body = Image.new("RGB", (W, W))
    px = body.load()
    for y in range(W):
        f = y / (W - 1)
        top, bot = (54, 60, 68), (18, 20, 23)
        row = tuple(int(a + (b - a) * f) for a, b in zip(top, bot))
        for x in range(W):
            px[x, y] = row

    radius = int(W * 0.205)
    mask = rounded_mask((W, W), radius)

    icon = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    icon.paste(body, (0, 0), mask)

    # A hairline along the top edge only — the way light catches a bevel. Far
    # subtler than a gloss sweep, which reads as a smudge at icon sizes.
    edge = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle(
        [0, 0, W - 1, W - 1], radius=radius, outline=(255, 255, 255, 46), width=int(W * 0.004)
    )
    # Fade the highlight out down the face; a hard cutoff leaves a seam across
    # the icon.
    fade = Image.new("L", (1, W))
    fp = fade.load()
    for y in range(W):
        # Squared falloff so the highlight reaches zero with zero slope —
        # a linear fade leaves a visible crease where it ends.
        t = min(1.0, y / (W * 0.55))
        fp[0, y] = int(255 * (1.0 - t) ** 2)
    edge.putalpha(ImageChops.multiply(edge.getchannel("A"), fade.resize((W, W))))
    icon.alpha_composite(edge)

    # Content block, centred: rail on the left, the rows it grades on the right.
    top_y, bot_y = W * 0.265, W * 0.735

    # The rail oxidises top (stale) to bottom (fresh), matching the popover,
    # where the queue sorts oldest first.
    rail_w = int(W * 0.072)
    rx0 = int(W * 0.243)
    ry0, ry1 = int(top_y), int(bot_y)
    rail = Image.new("RGBA", (rail_w, ry1 - ry0))
    rp = rail.load()
    for y in range(rail.height):
        colour = ramp(1.0 - y / (rail.height - 1)) + (255,)
        for x in range(rail.width):
            rp[x, y] = colour
    icon.paste(rail, (rx0, ry0), rounded_mask((rail.width, rail.height), rail_w // 2))

    # Three rows, receding — nearest the top is the one that matters.
    bar_x0 = int(W * 0.383)
    bar_h = int(W * 0.050)
    widths = [0.374, 0.300, 0.214]
    alphas = [255, 140, 72]
    gap = (bot_y - top_y - bar_h) / 2
    # Drawn on their own layer and composited: ImageDraw *replaces* alpha rather
    # than blending, so drawing straight onto the icon punches holes instead of
    # fading the rows back.
    rows = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    rd = ImageDraw.Draw(rows)
    for i, (wf, a) in enumerate(zip(widths, alphas)):
        y0 = int(top_y + i * gap)
        rd.rounded_rectangle(
            [bar_x0, y0, bar_x0 + int(W * wf), y0 + bar_h],
            radius=bar_h // 2,
            fill=(255, 255, 255, a),
        )
    icon.alpha_composite(rows)

    return icon.resize((S, S), Image.LANCZOS)


def main():
    icon = build()
    iconset = ROOT / "build" / "AppIcon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir(parents=True)

    for size in (16, 32, 128, 256, 512):
        icon.resize((size, size), Image.LANCZOS).save(iconset / f"icon_{size}x{size}.png")
        icon.resize((size * 2, size * 2), Image.LANCZOS).save(iconset / f"icon_{size}x{size}@2x.png")

    (ROOT / "Resources").mkdir(exist_ok=True)
    out = ROOT / "Resources" / "AppIcon.icns"
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(out)], check=True)
    icon.save(ROOT / "Resources" / "icon-preview.png")
    print(f"wrote {out}")


if __name__ == "__main__":
    main()
