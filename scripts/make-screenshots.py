#!/usr/bin/env python3
"""Turns `ghs --render` output into the README screenshots in docs/.

Rounds the corners the way macOS draws a popover and drops a soft shadow onto
transparency, so the same image sits correctly on GitHub's light and dark page.
Requires Pillow.
"""
import pathlib
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter

ROOT = pathlib.Path(__file__).resolve().parent.parent
SCALE = 2                 # renders come out at 2x
RADIUS = 10 * SCALE       # popover corner radius, in points
PAD = 26 * SCALE
SHADOW_BLUR = 11 * SCALE
SHADOW_DROP = 5 * SCALE


def trimmed(image: Image.Image) -> Image.Image:
    """Drop uniform padding below the last row that has any content.

    The settings panes are rendered tall enough for the longest one, so the
    shorter panes come back with an expanse of empty background under them.
    """
    pixels = image.convert("RGB")
    bottom = pixels.getpixel((0, image.height - 1))
    last = image.height - 1
    while last > 0:
        row = pixels.crop((0, last, image.width, last + 1))
        if row.getextrema() != tuple((c, c) for c in bottom):
            break
        last -= 1
    return image.crop((0, 0, image.width, min(image.height, last + 1 + 24 * SCALE)))


def framed(source: pathlib.Path, destination: pathlib.Path, trim: bool = False) -> None:
    image = Image.open(source).convert("RGBA")
    if trim:
        image = trimmed(image)

    corners = Image.new("L", image.size, 0)
    ImageDraw.Draw(corners).rounded_rectangle(
        [0, 0, image.width - 1, image.height - 1], radius=RADIUS, fill=255
    )
    image.putalpha(corners)

    canvas = Image.new("RGBA", (image.width + PAD * 2, image.height + PAD * 2), (0, 0, 0, 0))

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [PAD, PAD + SHADOW_DROP, PAD + image.width, PAD + image.height + SHADOW_DROP],
        radius=RADIUS,
        fill=(0, 0, 0, 74),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR)))
    canvas.alpha_composite(image, (PAD, PAD))

    destination.parent.mkdir(parents=True, exist_ok=True)
    canvas.save(destination)
    print(f"wrote {destination.relative_to(ROOT)}  {canvas.width}x{canvas.height}")


def main() -> None:
    binary = ROOT / ".build" / "debug" / "ghs"
    if not binary.exists():
        sys.exit("build first: swift build")

    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run([str(binary), "--render", tmp], check=True, capture_output=True)
        for name in ("queue-light", "queue-dark"):
            framed(pathlib.Path(tmp) / f"{name}.png", ROOT / "docs" / f"{name}.png")

        # The settings panes, for the walkthrough in the README.
        for pane in ("repositories", "queue", "account"):
            for scheme in ("light", "dark"):
                name = f"settings-{pane}-{scheme}"
                framed(pathlib.Path(tmp) / f"{name}.png", ROOT / "docs" / f"{name}.png",
                       trim=True)

        # The status bar strip already carries its own backgrounds.
        bar = Image.open(pathlib.Path(tmp) / "statusbar.png")
        bar.save(ROOT / "docs" / "statusbar.png")
        print(f"wrote docs/statusbar.png  {bar.width}x{bar.height}")

    # The icon at a size the README can show without upscaling.
    icon = Image.open(ROOT / "Resources" / "icon-preview.png")
    icon.resize((256, 256), Image.LANCZOS).save(ROOT / "docs" / "icon.png")
    print("wrote docs/icon.png  256x256")


if __name__ == "__main__":
    main()
