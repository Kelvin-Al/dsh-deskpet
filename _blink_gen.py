"""给 idle 和 busy 合闭眼差分：眼部取肤色填充 + 闭眼弧线 + 睫毛。"""
import os

import numpy as np
from PIL import Image, ImageDraw

PET = r"C:\Users\admin\Documents\deepseek-harness\default-workspace\ds-pet\assets\pet"
KEYS = {"idle": (130, 130), "busy": (158, 148)}  # 眼区中心 (x,y)，按 360px 画布实测


def closed_eyes_on(im, ex, ey):
    im = im.copy()
    draw = ImageDraw.Draw(im)
    W, H = im.size

    off_y = -6
    sx = max(0, ex - 28)
    ex2 = min(W - 1, ex + 28)
    sy = max(0, ey + off_y - 16)
    ey2 = min(H - 1, ey + off_y + 16)

    region = np.array(im.crop((sx, sy, ex2, ey2)))
    a = region[..., 3]
    rgb = region[..., :3]
    mask = (a > 180) & ~((rgb > 230).all(axis=-1))
    if mask.sum() > 20:
        skin = tuple(rgb[mask].mean(axis=0).astype(np.uint8))
    else:
        skin = (253, 234, 224)

    draw.rounded_rectangle(
        [ex - 16, ey + off_y - 12, ex + 16, ey + off_y + 12],
        radius=10,
        fill=(int(skin[0]), int(skin[1]), int(skin[2]), 255),
    )

    pts = []
    for t in range(31):
        tt = t / 30 * 2.0 - 1.0
        xx = ex + tt * 14
        yy = ey + off_y + 1 - (1 - tt * tt) * 8
        pts.append((xx, yy))
    draw.line(pts, fill=(29, 40, 90, 255), width=4, joint="curve")

    lx, ly = pts[0]
    rx, ry = pts[-1]
    draw.line([(lx, ly), (lx - 5, ly - 6)], fill=(29, 40, 90, 255), width=3)
    draw.line([(rx, ry), (rx + 5, ry - 6)], fill=(29, 40, 90, 255), width=3)

    return im


for k, (ex, ey) in KEYS.items():
    src = os.path.join(PET, f"{k}.png")
    im = Image.open(src).convert("RGBA")
    out = closed_eyes_on(im, ex, ey)
    dst = os.path.join(PET, f"{k}_close.png")
    out.save(dst)
    print(k, "->", dst)

print("done")