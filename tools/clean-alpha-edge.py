from __future__ import annotations

import argparse
from collections import deque
from pathlib import Path

from PIL import Image, ImageFilter


def clean_alpha_edge(source: Path, destination: Path) -> None:
    image = Image.open(source).convert("RGBA")
    width, height = image.size
    pixels = list(image.getdata())

    # Propagate trustworthy interior colours outwards.  This removes coloured
    # matte pixels without flattening the original anti-aliased alpha edge.
    nearest = [-1] * (width * height)
    queue: deque[int] = deque()
    for index, (red, green, blue, alpha) in enumerate(pixels):
        contaminated_red = red > 220 and green < 24 and blue < 24
        if alpha >= 240 and not contaminated_red:
            nearest[index] = index
            queue.append(index)

    while queue:
        index = queue.popleft()
        x = index % width
        y = index // width
        for neighbour in (
            index - 1 if x else -1,
            index + 1 if x + 1 < width else -1,
            index - width if y else -1,
            index + width if y + 1 < height else -1,
        ):
            if neighbour >= 0 and nearest[neighbour] < 0:
                nearest[neighbour] = nearest[index]
                queue.append(neighbour)

    alpha = image.getchannel("A").filter(ImageFilter.MinFilter(3))
    alpha_data = list(alpha.getdata())
    output = []
    for index, (red, green, blue, _old_alpha) in enumerate(pixels):
        clean_alpha = alpha_data[index]
        if clean_alpha < 8:
            output.append((0, 0, 0, 0))
            continue
        if clean_alpha < 240 or (red > 220 and green < 24 and blue < 24):
            source_index = nearest[index]
            if source_index >= 0:
                red, green, blue, _ = pixels[source_index]
        output.append((red, green, blue, clean_alpha))

    cleaned = Image.new("RGBA", image.size)
    cleaned.putdata(output)
    destination.parent.mkdir(parents=True, exist_ok=True)
    cleaned.save(destination, optimize=True)


def main() -> None:
    parser = argparse.ArgumentParser(description="Remove coloured matte spill from an RGBA image.")
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    clean_alpha_edge(args.source, args.destination)


if __name__ == "__main__":
    main()
