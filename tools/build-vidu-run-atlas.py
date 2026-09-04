from __future__ import annotations

import argparse
import json
import subprocess
from collections import deque
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


CELL = 256
COLUMNS = 24


def video_info(path: Path) -> tuple[int, int, int]:
    command = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-show_entries", "stream=width,height,nb_frames", "-of", "json", str(path),
    ]
    data = json.loads(subprocess.check_output(command, text=True))
    stream = data["streams"][0]
    return int(stream["width"]), int(stream["height"]), int(stream["nb_frames"])


def keep_character_silhouette(rgb: Image.Image) -> Image.Image:
    array = np.asarray(rgb)
    brightness = array.max(axis=2)

    # Identify the exterior dark field from the image border. Dark details
    # inside the character (eyes, horns and hooves) are therefore preserved.
    # Copy detaches the Pillow image from NumPy's read-only buffer so floodfill
    # can mutate it. Without this, the matte silently remains opaque.
    dark = Image.fromarray(np.where(brightness <= 18, 255, 0).astype(np.uint8), "L").copy()
    ImageDraw.floodfill(dark, (0, 0), 128, thresh=0)
    exterior = np.asarray(dark) == 128
    silhouette = Image.fromarray(np.where(exterior, 0, 255).astype(np.uint8), "L")

    # Keep only the connected subject containing the centre of the frame;
    # this discards isolated H.264 noise in the black background.
    connected = silhouette.copy()
    ImageDraw.floodfill(connected, (CELL // 2, CELL // 2), 128, thresh=0)
    selected = np.asarray(connected) == 128
    hard_alpha = Image.fromarray(np.where(selected, 255, 0).astype(np.uint8), "L")

    # Contract a fraction of a pixel and feather once. This prevents a black
    # or coloured matte without producing a hard, flickering cut-out edge.
    hard_alpha = hard_alpha.filter(ImageFilter.MinFilter(3))
    return hard_alpha.filter(ImageFilter.GaussianBlur(0.65))


def propagate_edge_colours(rgb: Image.Image, alpha: Image.Image) -> Image.Image:
    colours = np.asarray(rgb).copy()
    alpha_array = np.asarray(alpha)
    height, width = alpha_array.shape
    nearest = np.full(height * width, -1, dtype=np.int32)
    queue: deque[int] = deque()

    seeds = np.flatnonzero(alpha_array.reshape(-1) >= 250)
    for index in seeds.tolist():
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

    flat_colours = colours.reshape(-1, 3)
    soft_edge = np.flatnonzero((alpha_array.reshape(-1) > 0) & (alpha_array.reshape(-1) < 250))
    valid = soft_edge[nearest[soft_edge] >= 0]
    flat_colours[valid] = flat_colours[nearest[valid]]
    flat_colours[alpha_array.reshape(-1) == 0] = 0

    rgba = np.dstack((colours, alpha_array))
    return Image.fromarray(rgba.astype(np.uint8), "RGBA")


def build(video: Path, destination: Path) -> int:
    width, height, expected_frames = video_info(video)
    command = [
        "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(video),
        "-map", "0:v:0", "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1",
    ]
    process = subprocess.Popen(command, stdout=subprocess.PIPE)
    assert process.stdout is not None
    frame_bytes = width * height * 3
    frames: list[Image.Image] = []

    while True:
        raw = process.stdout.read(frame_bytes)
        if not raw:
            break
        if len(raw) != frame_bytes:
            process.kill()
            raise RuntimeError("ffmpeg returned a partial video frame")
        frame = Image.frombytes("RGB", (width, height), raw)
        frame = frame.resize((CELL, CELL), Image.Resampling.LANCZOS)
        alpha = keep_character_silhouette(frame)
        frames.append(propagate_edge_colours(frame, alpha))

    return_code = process.wait()
    if return_code != 0:
        raise RuntimeError(f"ffmpeg exited with code {return_code}")
    if len(frames) != expected_frames:
        raise RuntimeError(f"expected {expected_frames} frames, decoded {len(frames)}")

    rows = (len(frames) + COLUMNS - 1) // COLUMNS
    atlas = Image.new("RGBA", (CELL * COLUMNS, CELL * rows), (0, 0, 0, 0))
    for index, frame in enumerate(frames):
        atlas.alpha_composite(frame, ((index % COLUMNS) * CELL, (index // COLUMNS) * CELL))

    destination.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(destination, "WEBP", quality=84, method=6, exact=True)
    return len(frames)


def main() -> None:
    parser = argparse.ArgumentParser(description="Build a transparent WebP sprite atlas from a Vidu video.")
    parser.add_argument("video", type=Path)
    parser.add_argument("destination", type=Path)
    args = parser.parse_args()
    count = build(args.video, args.destination)
    print(f"FRAMES={count}")
    print(f"OUTPUT={args.destination.resolve()}")


if __name__ == "__main__":
    main()
