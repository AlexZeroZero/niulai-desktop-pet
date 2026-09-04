from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter


def isolate(cell: Image.Image) -> Image.Image:
    rgba = cell.convert("RGBA")
    pixels = np.asarray(rgba.convert("RGB"))
    subject = pixels.max(axis=2) >= 18
    active_columns = np.flatnonzero(subject.sum(axis=0) > 3)
    runs: list[tuple[int, int]] = []
    if active_columns.size:
        start = previous = int(active_columns[0])
        for value in active_columns[1:]:
            value = int(value)
            if value != previous + 1:
                runs.append((start, previous + 1))
                start = value
            previous = value
        runs.append((start, previous + 1))
    if not runs:
        raise RuntimeError("No character silhouette found")
    left, right = max(runs, key=lambda run: int(subject[:, run[0] : run[1]].sum()))
    subject[:, :left] = False
    subject[:, right:] = False
    mask = Image.fromarray(subject.astype(np.uint8) * 255, mode="L")
    mask = mask.filter(ImageFilter.MaxFilter(5))
    mask = mask.filter(ImageFilter.MinFilter(5))
    mask = mask.filter(ImageFilter.GaussianBlur(0.45))
    rgba.putalpha(mask)
    return rgba


def normalize(cell: Image.Image) -> Image.Image:
    character = isolate(cell)
    bounds = character.getchannel("A").point(lambda value: 255 if value >= 10 else 0).getbbox()
    if bounds is None:
        raise RuntimeError("Empty authored frame")
    character = character.crop(bounds)
    target_height = 360
    canvas = 512
    baseline = 478
    scale = target_height / character.height
    width = max(1, round(character.width * scale))
    height = target_height
    if width > canvas - 24:
        scale = (canvas - 24) / character.width
        width = canvas - 24
        height = max(1, round(character.height * scale))
    character = character.resize((width, height), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    frame.alpha_composite(character, ((canvas - width) // 2, baseline - height))
    return frame


def make_audit(frames: list[Image.Image], path: Path) -> None:
    size = 256
    sheet = Image.new("RGB", (size * 8, size * 6), (12, 13, 15))
    for index, frame in enumerate(frames):
        preview = Image.new("RGBA", frame.size, (12, 13, 15, 255))
        preview.alpha_composite(frame)
        preview = preview.resize((size, size), Image.Resampling.LANCZOS).convert("RGB")
        sheet.paste(preview, ((index % 8) * size, (index // 8) * size))
    sheet.save(path)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("keyframes", type=Path)
    parser.add_argument("inbetweens", type=Path)
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    raw_dir = args.output / "frames-48-2d-raw"
    frame_dir = args.output / "frames-48-2d"
    raw_dir.mkdir(exist_ok=True)
    frame_dir.mkdir(exist_ok=True)

    frames: list[Image.Image] = []
    for key_index in range(12):
        key = Image.open(args.keyframes / f"frame-{key_index:03d}.png").convert("RGBA")
        frames.append(normalize(key))

        strip = Image.open(args.inbetweens / f"between-{key_index:02d}.png").convert("RGBA")
        for panel in range(3):
            left = round(panel * strip.width / 3)
            right = round((panel + 1) * strip.width / 3)
            cell = strip.crop((left, 0, right, strip.height))
            cell.save(raw_dir / f"interval-{key_index:02d}-panel-{panel}.png")
            frames.append(normalize(cell))

    if len(frames) != 48:
        raise RuntimeError(f"Expected 48 frames, got {len(frames)}")
    for index, frame in enumerate(frames):
        frame.save(frame_dir / f"frame-{index:03d}.png")
    make_audit(frames, args.output / "niulai-walk-48-2d-audit-v9.png")
    print(frame_dir)


if __name__ == "__main__":
    main()
