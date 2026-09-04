from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image


def consecutive_runs(values: list[int]) -> list[tuple[int, int]]:
    if not values:
        return []
    runs: list[tuple[int, int]] = []
    start = previous = values[0]
    for value in values[1:]:
        if value != previous + 1:
            runs.append((start, previous))
            start = value
        previous = value
    runs.append((start, previous))
    return runs


def content_intervals(gutters: list[tuple[int, int]]) -> list[tuple[int, int]]:
    return [
        (left_end + 1, right_start - 1)
        for (_, left_end), (right_start, _) in zip(gutters, gutters[1:])
        if right_start > left_end + 1
    ]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--columns", type=int, required=True)
    parser.add_argument("--rows", type=int, required=True)
    args = parser.parse_args()

    source = Image.open(args.input).convert("RGB")
    width, height = source.size
    pixels = source.load()

    dark_columns = [
        x
        for x in range(width)
        if sum(max(pixels[x, y]) < 35 for y in range(0, height, 4))
        >= int((height + 3) // 4 * 0.8)
    ]
    dark_rows = [
        y
        for y in range(height)
        if sum(max(pixels[x, y]) < 35 for x in range(0, width, 4))
        >= int((width + 3) // 4 * 0.8)
    ]

    x_intervals = content_intervals(consecutive_runs(dark_columns))
    y_intervals = content_intervals(consecutive_runs(dark_rows))
    if len(x_intervals) != args.columns or len(y_intervals) != args.rows:
        raise RuntimeError(
            f"Detected {len(x_intervals)} columns and {len(y_intervals)} rows; "
            f"expected {args.columns}x{args.rows}."
        )

    cell_width = max(end - start + 1 for start, end in x_intervals)
    cell_height = max(end - start + 1 for start, end in y_intervals)
    output = Image.new(
        "RGB", (cell_width * args.columns, cell_height * args.rows), (0, 255, 0)
    )

    for row, (top, bottom) in enumerate(y_intervals):
        for column, (left, right) in enumerate(x_intervals):
            cell = source.crop((left, top, right + 1, bottom + 1))
            offset_x = column * cell_width + (cell_width - cell.width) // 2
            offset_y = row * cell_height + (cell_height - cell.height)
            output.paste(cell, (offset_x, offset_y))

    args.output.parent.mkdir(parents=True, exist_ok=True)
    output.save(args.output)
    print(args.output)


if __name__ == "__main__":
    main()
