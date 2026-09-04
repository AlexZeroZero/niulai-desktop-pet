from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input_dir", type=Path)
    parser.add_argument("output_dir", type=Path)
    parser.add_argument("--count", type=int, default=32)
    parser.add_argument("--canvas", type=int, default=512)
    parser.add_argument("--height", type=int, default=360)
    parser.add_argument("--baseline", type=int, default=478)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    for index in range(args.count):
        raw = args.input_dir / f"frame-{index:03d}-raw.png"
        source = raw if raw.exists() else args.input_dir / f"frame-{index:03d}.png"
        if not source.exists():
            raise FileNotFoundError(source)

        image = Image.open(source).convert("RGBA")
        if raw.exists():
            # Some generated "transparent" frames contain a baked gray checkerboard.
            # The character is strongly saturated orange/brown while that checker is
            # neutral, so rebuild alpha from saturation and close only small interior
            # holes (eyes, mouth details) without merging separate limbs.
            saturation = image.convert("HSV").getchannel("S")
            subject_mask = saturation.point(lambda value: 255 if value >= 60 else 0)
            subject_mask = subject_mask.filter(ImageFilter.MaxFilter(7))
            subject_mask = subject_mask.filter(ImageFilter.MinFilter(7))
            subject_mask = subject_mask.filter(ImageFilter.GaussianBlur(0.55))
            image.putalpha(ImageChops.multiply(image.getchannel("A"), subject_mask))
        alpha = image.getchannel("A")
        threshold = alpha.point(lambda value: 255 if value >= 12 else 0)
        bounds = threshold.getbbox()
        if bounds is None:
            raise RuntimeError(f"No visible character in {source}")

        character = image.crop(bounds)
        scale = args.height / character.height
        width = max(1, round(character.width * scale))
        height = args.height
        if width > args.canvas - 24:
            scale = (args.canvas - 24) / character.width
            width = args.canvas - 24
            height = max(1, round(character.height * scale))
        character = character.resize((width, height), Image.Resampling.LANCZOS)

        frame = Image.new("RGBA", (args.canvas, args.canvas), (0, 0, 0, 0))
        x = (args.canvas - width) // 2
        y = args.baseline - height
        frame.alpha_composite(character, (x, y))
        frame.save(args.output_dir / f"frame-{index:03d}.png")

    print(args.output_dir)


if __name__ == "__main__":
    main()
