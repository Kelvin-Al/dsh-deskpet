"""DSH 桌宠 · 鲸鱼娘位图生成器 (v4)
思路：大头 Q 版 + 圆头 + 尖刘海，固定 300x300 画布，同基线。
"""
import math
import os
import sys

from PIL import Image, ImageDraw

S = 4
W = H = 300
CW, CH = W * S, H * S

HAIR_HI = (152, 184, 255)
HAIR_MID = (79, 110, 255)
HAIR_DARK = (40, 58, 174)
SKIN = (255, 233, 222)
DRESS = (34, 43, 98)
DRESS_HI = (48, 60, 130)
WHITE = (253, 254, 255)
WHITE_SH = (221, 229, 247)
IRIS_TOP = (126, 166, 255)
IRIS_BOT = (26, 42, 100)
BLUSH = (255, 148, 186)
TAIL = (62, 90, 230)
TAIL_HI = (142, 178, 255)
SHOE = (30, 40, 92)
MOUTH = (172, 82, 90)
LASH = (26, 38, 90)

HEAD_CX, HEAD_CY, HEAD_R = 150, 108, 58
HAIR_R = 74


def sc(pts):
    return [(x * S, y * S) for x, y in pts]


def catmull(points, samples=14, closed=True):
    p = list(points)
    n = len(p)
    out = []
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        p0, p1 = p[(i - 1) % n], p[i % n]
        p2, p3 = p[(i + 1) % n], p[(i + 2) % n]
        for j in range(samples):
            t = j / samples
            t2, t3 = t * t, t * t * t
            x = 0.5 * ((2 * p1[0]) + (-p0[0] + p2[0]) * t +
                       (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2 +
                       (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * ((2 * p1[1]) + (-p0[1] + p2[1]) * t +
                       (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2 +
                       (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    return out


def vgrad(size, top, bottom):
    im = Image.new('RGB', (1, size[1]))
    d = ImageDraw.Draw(im)
    for y in range(size[1]):
        t = y / max(1, size[1] - 1)
        d.point((0, y), tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)))
    return im.resize(size, Image.BILINEAR)


def grad_shape(base, pts, top, bottom):
    mask = Image.new('L', (CW, CH), 0)
    ImageDraw.Draw(mask).polygon(sc(pts), fill=255)
    layer = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
    layer.paste(vgrad((CW, CH), top, bottom), (0, 0), mask)
    return Image.alpha_composite(base, layer)


def blob(d, pts, fill):
    d.polygon(sc(pts), fill=fill)


def ell(d, box, fill):
    x0, y0, x1, y1 = box
    d.ellipse([x0 * S, y0 * S, x1 * S, y1 * S], fill=fill)


def circle(d, cx, cy, r, fill):
    ell(d, (cx - r, cy - r, cx + r, cy + r), fill)


def stroke(d, pts, fill, width):
    d.line(sc(pts), fill=fill, width=max(1, int(width * S)), joint='curve')


def arc_pts(cx, cy, r, a0, a1, n=20):
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n),
             cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


# ---------------- 部件 ----------------
def tail(base, dy=0):
    pts = [(186, 214 + dy), (220, 200 + dy), (248, 172 + dy), (258, 146 + dy),
           (272, 166 + dy), (258, 202 + dy), (220, 230 + dy), (190, 226 + dy)]
    return grad_shape(base, catmull(pts, 16), TAIL_HI, TAIL)


def body(base, dy=0):
    d = ImageDraw.Draw(base)
    dress = [(118, 158 + dy), (182, 158 + dy), (196, 244 + dy), (104, 244 + dy)]
    blob(d, catmull(dress, 10), DRESS)
    # 裙摆白边
    hem = []
    for i in range(9):
        x = 104 + (196 - 104) * i / 8
        hem.append((x, 244 + dy + (4 if i % 2 else 1)))
    for i in range(8, -1, -1):
        x = 104 + (196 - 104) * i / 8
        hem.append((x, 234 + dy))
    blob(d, hem, WHITE)
    # 围裙
    apron = [(132, 174 + dy), (168, 174 + dy), (176, 234 + dy), (124, 234 + dy)]
    blob(d, catmull(apron, 10), WHITE)
    ell(d, (138, 198 + dy, 154, 210 + dy), HAIR_MID)
    d.polygon(sc([(138, 204 + dy), (130, 198 + dy), (132, 212 + dy)]), fill=HAIR_MID)
    ell(d, (148, 200 + dy, 152, 204 + dy), WHITE)
    # 领口
    blob(d, [(126, 158 + dy), (174, 158 + dy), (150, 176 + dy)], WHITE)
    d.polygon(sc([(150, 170 + dy), (139, 162 + dy), (139, 179 + dy)]), fill=DRESS)
    d.polygon(sc([(150, 170 + dy), (161, 162 + dy), (161, 179 + dy)]), fill=DRESS)
    ell(d, (147, 167 + dy, 153, 173 + dy), DRESS_HI)
    return base


def legs(base, dy=0):
    d = ImageDraw.Draw(base)
    ell(d, (132, 236 + dy, 146, 262 + dy), SKIN)
    ell(d, (154, 236 + dy, 168, 262 + dy), SKIN)
    ell(d, (130, 252 + dy, 148, 270 + dy), WHITE)
    ell(d, (152, 252 + dy, 170, 270 + dy), WHITE)
    ell(d, (126, 266 + dy, 150, 284 + dy), SHOE)
    ell(d, (150, 266 + dy, 174, 284 + dy), SHOE)
    ell(d, (130, 268 + dy, 144, 274 + dy), (78, 92, 156))
    ell(d, (156, 268 + dy, 170, 274 + dy), (78, 92, 156))
    return base


def hair_back(base):
    pts = catmull(arc_pts(HEAD_CX, HEAD_CY, HAIR_R, math.pi * 0.98, math.pi * 2.02, 26), 4, closed=False)
    # 加两侧下摆
    pts = pts + [(150 + 62, 186), (150 + 40, 168), (150, 170), (150 - 40, 168), (150 - 62, 186)]
    return grad_shape(base, catmull(pts, 8), HAIR_HI, HAIR_DARK)


def head(base):
    d = ImageDraw.Draw(base)
    circle(d, HEAD_CX, HEAD_CY, HEAD_R, SKIN)
    return base


def face(base, mood='idle'):
    d = ImageDraw.Draw(base)
    for bx in (114, 186):
        ell(d, (bx - 13, 132, bx + 13, 144), BLUSH)

    eye_y = 124
    if mood == 'sleepy':
        for ex in (128, 172):
            stroke(d, [(ex - 11, eye_y - 2), (ex - 4, eye_y - 8), (ex + 4, eye_y - 8), (ex + 11, eye_y - 2)],
                   LASH, 3.0)
        ell(d, (146, 146, 154, 152), (130, 74, 84))
    elif mood == 'happy':
        for ex in (128, 172):
            stroke(d, [(ex - 10, eye_y - 2), (ex, eye_y - 12), (ex + 10, eye_y - 2)], LASH, 3.2)
        d.arc([142 * S, 140 * S, 158 * S, 154 * S], 25, 155, fill=MOUTH, width=2 * S)
    else:
        for ex in (128, 172):
            ell(d, (ex - 11, eye_y - 16, ex + 11, eye_y + 14), IRIS_BOT)
            ell(d, (ex - 11, eye_y - 16, ex + 11, eye_y - 2), IRIS_TOP)
            ell(d, (ex - 6, eye_y - 11, ex, eye_y - 3), WHITE)
            ell(d, (ex + 2, eye_y + 4, ex + 7, eye_y + 9), (196, 220, 255))
            stroke(d, arc_pts(ex, eye_y - 14, 11, math.pi * 1.10, math.pi * 1.90, 12), LASH, 2.6)
        d.arc([142 * S, 142 * S, 158 * S, 156 * S], 25, 155, fill=MOUTH, width=2 * S)
    return base


def bangs(base):
    """尖刘海：覆盖额头，四尖"""
    top = arc_pts(HEAD_CX, HEAD_CY, HEAD_R + 2, math.pi * 1.12, math.pi * 1.88, 18)
    pts = list(top)
    tips = [(178, 118), (166, 104), (150, 126), (134, 104), (122, 118)]
    pts = pts + tips
    return grad_shape(base, catmull(pts, 8), HAIR_HI, HAIR_MID)


def side_locks(base):
    d = ImageDraw.Draw(base)
    for side in (-1, 1):
        x = HEAD_CX + side * 58
        pts = [(x, 100), (x + side * 10, 138), (x + side * 4, 168),
               (x - side * 6, 154), (x - side * 8, 116)]
        blob(d, catmull(pts, 12), HAIR_MID)
    return base


def fins(base):
    d = ImageDraw.Draw(base)
    left = [(106, 88), (74, 66), (64, 84), (84, 98), (104, 100)]
    right = [(194, 88), (226, 66), (236, 84), (216, 98), (196, 100)]
    for fin in (left, right):
        blob(d, catmull(fin, 12), HAIR_MID)
        cx = sum(p[0] for p in fin) / len(fin)
        cy = sum(p[1] for p in fin) / len(fin)
        inner = [(cx + (x - cx) * 0.46, cy + (y - cy) * 0.42) for x, y in fin]
        blob(d, catmull(inner, 12), WHITE)
    return base


def ahoge(base):
    d = ImageDraw.Draw(base)
    pts = catmull([(150, 40), (147, 22), (162, 10), (180, 14), (174, 28)],
                  samples=20, closed=False)
    stroke(d, pts, HAIR_MID, 4.0)
    return base


def arms(base, pose='idle', dy=0):
    d = ImageDraw.Draw(base)
    if pose == 'up':
        for side in (-1, 1):
            x = 150 + side * 46
            stroke(d, [(x, 176 + dy), (x + side * 18, 152 + dy)], SKIN, 10)
            ell(d, (x + side * 18 - 6, 144 + dy, x + side * 18 + 6, 158 + dy), SKIN)
    else:
        for side in (-1, 1):
            x = 150 + side * 44
            stroke(d, [(x, 174 + dy), (x + side * 3, 202 + dy)], SKIN, 9)
            ell(d, (x + side * 3 - 5, 196 + dy, x + side * 3 + 5, 208 + dy), SKIN)
    return base


def desk(base):
    d = ImageDraw.Draw(base)
    d.rectangle([64 * S, 250 * S, 236 * S, 260 * S], fill=WHITE)
    d.rectangle([64 * S, 260 * S, 76 * S, 296 * S], fill=WHITE_SH)
    d.rectangle([224 * S, 260 * S, 236 * S, 296 * S], fill=WHITE_SH)
    d.polygon(sc([(114, 250), (186, 250), (180, 222), (120, 222)]), fill=(31, 39, 78))
    d.polygon(sc([(120, 246), (180, 246), (175, 227), (125, 227)]), fill=(168, 196, 255))
    ell(d, (144, 231, 156, 241), (37, 52, 130))
    d.polygon(sc([(144, 237), (136, 231), (138, 243)]), fill=(37, 52, 130))
    return base


def render(mood='idle'):
    base = Image.new('RGBA', (CW, CH), (0, 0, 0, 0))
    if mood == 'busy':
        base = tail(base, dy=-4)
        base = body(base, dy=22)
        base = desk(base)
        base = hair_back(base)
        base = head(base)
        base = face(base, 'idle')
        base = bangs(base)
        base = side_locks(base)
        base = fins(base)
        base = ahoge(base)
    else:
        base = tail(base)
        base = body(base)
        base = legs(base)
        base = hair_back(base)
        base = head(base)
        base = face(base, mood)
        base = bangs(base)
        base = side_locks(base)
        base = fins(base)
        base = ahoge(base)
        base = arms(base, 'up' if mood == 'happy' else 'idle')
    return base.resize((W, H), Image.LANCZOS)


if __name__ == '__main__':
    outdir = sys.argv[1] if len(sys.argv) > 1 else '.'
    os.makedirs(outdir, exist_ok=True)
    states = ['idle', 'busy', 'happy', 'sleepy']
    for m in states:
        im = render(m)
        im.save(os.path.join(outdir, f'pet_{m}.png'))
        print('saved', m, im.size)

    cell = 320
    sheet = Image.new('RGB', (cell * len(states), cell + 20), (26, 26, 32))
    for i, m in enumerate(states):
        im = Image.open(os.path.join(outdir, f'pet_{m}.png')).convert('RGBA')
        sheet.paste(im, (i * cell + 10, 10), im)
    sheet.save(os.path.join(outdir, 'states-sheet.png'))
    print('sheet saved')
