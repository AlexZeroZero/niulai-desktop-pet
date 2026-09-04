from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(r"D:\牛来桌面宠物")
OUT = ROOT / "assets" / "animation-video" / "walk-v10" / "pose-guides"
OUT.mkdir(parents=True, exist_ok=True)


def point_on_bent_limb(start, end, bend_x, bend_y):
    return (
        (start[0] + end[0]) / 2 + bend_x,
        (start[1] + end[1]) / 2 + bend_y,
    )


def draw_limb(draw, points, colors, width=13):
    for index in range(len(points) - 1):
        draw.line((points[index], points[index + 1]), fill=colors[index], width=width)
    for point in points:
        x, y = point
        draw.ellipse((x - 8, y - 8, x + 8, y + 8), fill=(250, 250, 250))


for index in range(12):
    phase = index / 12 * math.tau
    image = Image.new("RGB", (512, 512), (0, 0, 0))
    draw = ImageDraw.Draw(image)

    bob = 3 * (1 - math.cos(phase * 2))
    shoulder_y = 170 + bob
    hip_y = 290 + bob
    head = (256, 105 + bob)
    neck = (256, 155 + bob)
    pelvis = (256, hip_y)
    left_shoulder = (218, shoulder_y)
    right_shoulder = (294, shoulder_y)
    left_hip = (236, hip_y)
    right_hip = (276, hip_y)

    draw.ellipse((head[0] - 37, head[1] - 42, head[0] + 37, head[1] + 42), outline=(255, 225, 80), width=12)
    draw.line((neck, pelvis), fill=(255, 225, 80), width=15)
    draw.line((left_shoulder, right_shoulder), fill=(255, 225, 80), width=15)
    draw.line((left_hip, right_hip), fill=(255, 225, 80), width=15)

    for side, shoulder, hip, offset, side_sign in (
        ("left", left_shoulder, left_hip, 0.0, -1),
        ("right", right_shoulder, right_hip, math.pi, 1),
    ):
        p = (phase + offset) % math.tau
        forward = math.cos(p)
        swing_lift = max(0.0, -math.sin(p))
        foot = (
            hip[0] + side_sign * (18 + 10 * forward),
            426 + bob - 30 * swing_lift,
        )
        knee = point_on_bent_limb(
            hip,
            foot,
            side_sign * (6 + 7 * swing_lift),
            -8 - 14 * swing_lift,
        )
        leg_colors = ((40, 160, 255), (70, 220, 255)) if side == "left" else ((255, 75, 85), (255, 145, 70))
        draw_limb(draw, (hip, knee, foot), leg_colors, width=15)

        # Arms are exactly half a cycle opposite their matching legs.
        arm_forward = -forward
        hand = (
            shoulder[0] + side_sign * (19 - 6 * arm_forward),
            275 + bob - 20 * arm_forward,
        )
        elbow = point_on_bent_limb(
            shoulder,
            hand,
            -side_sign * (7 + 3 * max(0.0, arm_forward)),
            4,
        )
        arm_colors = ((125, 80, 255), (190, 100, 255)) if side == "left" else ((75, 245, 135), (70, 210, 100))
        draw_limb(draw, (shoulder, elbow, hand), arm_colors, width=13)

    image.save(OUT / f"pose-{index:02d}.png")

print(OUT)
