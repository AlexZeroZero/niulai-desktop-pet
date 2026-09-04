from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageFilter


def isolate_character(cell: Image.Image) -> Image.Image:
    rgba = cell.convert("RGBA")
    rgb = rgba.convert("RGB")
    pixels = np.asarray(rgb)
    subject = pixels.max(axis=2) >= 18

    # A tail from the adjacent panel can cross a nominal column boundary.
    # Keep the dominant horizontal silhouette run and discard isolated slivers.
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
    if runs:
        left, right = max(runs, key=lambda run: int(subject[:, run[0] : run[1]].sum()))
        subject[:, :left] = False
        subject[:, right:] = False

    mask = Image.fromarray(subject.astype(np.uint8) * 255, mode="L")
    mask = mask.filter(ImageFilter.MaxFilter(5))
    mask = mask.filter(ImageFilter.MinFilter(5))
    mask = mask.filter(ImageFilter.GaussianBlur(0.45))
    rgba.putalpha(mask)
    return rgba


def normalized_frame(cell: Image.Image, canvas: int, height: int, baseline: int) -> Image.Image:
    character = isolate_character(cell)
    alpha = character.getchannel("A").point(lambda pixel: 255 if pixel >= 10 else 0)
    bounds = alpha.getbbox()
    if bounds is None:
        raise RuntimeError("No character found in sprite cell")

    character = character.crop(bounds)
    scale = height / character.height
    width = max(1, round(character.width * scale))
    draw_height = height
    if width > canvas - 24:
        scale = (canvas - 24) / character.width
        width = canvas - 24
        draw_height = max(1, round(character.height * scale))
    character = character.resize((width, draw_height), Image.Resampling.LANCZOS)

    frame = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    frame.alpha_composite(character, ((canvas - width) // 2, baseline - draw_height))
    return frame


def make_audit(frames: list[Image.Image], output: Path) -> None:
    thumb = 256
    audit = Image.new("RGB", (thumb * 8, thumb * 6), (12, 13, 15))
    for index, frame in enumerate(frames):
        preview = Image.new("RGBA", frame.size, (12, 13, 15, 255))
        preview.alpha_composite(frame)
        preview = preview.resize((thumb, thumb), Image.Resampling.LANCZOS).convert("RGB")
        audit.paste(preview, ((index % 8) * thumb, (index // 8) * thumb))
    audit.save(output, quality=95)


def active_row_bands(sheet: Image.Image, expected: int) -> list[tuple[int, int]]:
    pixels = np.asarray(sheet.convert("RGB"))
    mask = pixels.max(axis=2) >= 18
    active = np.flatnonzero(mask.sum(axis=1) > 20)
    runs: list[tuple[int, int]] = []
    start = previous = int(active[0])
    for value in active[1:]:
        value = int(value)
        if value != previous + 1:
            if previous - start >= 40:
                runs.append((start, previous + 1))
            start = value
        previous = value
    if previous - start >= 40:
        runs.append((start, previous + 1))
    if len(runs) != expected:
        raise RuntimeError(f"Detected {len(runs)} populated rows, expected {expected}: {runs}")
    return runs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("main_sheet", type=Path)
    parser.add_argument("bridge_sheet", type=Path)
    parser.add_argument("output_dir", type=Path)
    args = parser.parse_args()

    args.output_dir.mkdir(parents=True, exist_ok=True)
    raw_dir = args.output_dir / "frames-48-authored-raw"
    frame_dir = args.output_dir / "frames-48-authored"
    raw_dir.mkdir(exist_ok=True)
    frame_dir.mkdir(exist_ok=True)

    main_sheet = Image.open(args.main_sheet).convert("RGBA")
    bridge_sheet = Image.open(args.bridge_sheet).convert("RGBA")
    if main_sheet.width % 8 or main_sheet.height % 6:
        raise RuntimeError(f"Unexpected main sheet size: {main_sheet.size}")
    if bridge_sheet.width % 8:
        raise RuntimeError(f"Unexpected bridge sheet size: {bridge_sheet.size}")

    main_cell_w = main_sheet.width // 8
    bridge_cell_w = bridge_sheet.width // 8
    raw_cells: list[Image.Image] = []

    # The generated figures extend beyond nominal grid boundaries, so detect the
    # five populated silhouette bands rather than cutting at mechanical row lines.
    for top, bottom in active_row_bands(main_sheet, expected=5):
        for column in range(8):
            left = column * main_cell_w
            raw_cells.append(main_sheet.crop((left, top, left + main_cell_w, bottom)))

    # Eight separately authored return-to-contact micro-poses complete the 48-frame loop.
    for column in range(8):
        left = column * bridge_cell_w
        raw_cells.append(bridge_sheet.crop((left, 0, left + bridge_cell_w, bridge_sheet.height)))

    frames: list[Image.Image] = []
    for index, cell in enumerate(raw_cells):
        cell.save(raw_dir / f"frame-{index:03d}.png")
        frame = normalized_frame(cell, canvas=512, height=360, baseline=478)
        frame.save(frame_dir / f"frame-{index:03d}.png")
        frames.append(frame)

    make_audit(frames, args.output_dir / "niulai-walk-48-authored-audit-v6.png")
    print(frame_dir)


if __name__ == "__main__":
    main()
