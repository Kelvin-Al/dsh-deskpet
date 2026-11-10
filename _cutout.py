from collections import deque
from PIL import Image
import sys

src, out, legs_preview = sys.argv[1], sys.argv[2], sys.argv[3]

im = Image.open(src).convert('RGBA')
W, H = im.size
px = im.load()

# 背景色：取四角平均，支持白底 / 浅灰底 / 浅蓝底
corners = [px[2, 2], px[W - 3, 2], px[2, H - 3], px[W - 3, H - 3]]
BG = tuple(sum(c[i] for c in corners) // 4 for i in range(3))
BGTOL = 30
print('size', (W, H), 'bg', BG)


def near_bg(p, tol=BGTOL):
    r, g, b, a = p
    return a > 0 and abs(r - BG[0]) <= tol and abs(g - BG[1]) <= tol and abs(b - BG[2]) <= tol


def near_white(p, tol=246):
    r, g, b, a = p
    return a > 0 and r >= tol and g >= tol and b >= tol


# ---- 1) 从边缘泛洪去背景 ----
seen = bytearray(W * H)
q = deque()
for x in range(W):
    for y in (0, H - 1):
        if near_bg(px[x, y]) and not seen[y * W + x]:
            seen[y * W + x] = 1
            q.append((x, y))
for y in range(H):
    for x in (0, W - 1):
        if near_bg(px[x, y]) and not seen[y * W + x]:
            seen[y * W + x] = 1
            q.append((x, y))

while q:
    x, y = q.popleft()
    for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
        if 0 <= nx < W and 0 <= ny < H:
            i = ny * W + nx
            if not seen[i] and near_bg(px[nx, ny]):
                seen[i] = 1
                q.append((nx, ny))

for y in range(H):
    for x in range(W):
        if seen[y * W + x]:
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 0)

# ---- 2) 被围住的白块（如两腿之间）：按行找夹在两侧实体之间的白条，只留最大连通块 ----
GAP_TOP, GAP_BOTTOM = int(H * 0.60), H - 1
cand = set()
for y in range(GAP_TOP, GAP_BOTTOM):
    x = 1
    while x < W - 1:
        if near_white(px[x, y]):
            x0 = x
            while x < W - 1 and near_white(px[x, y]):
                x += 1
            x1 = x
            run = x1 - x0
            left = px[x0 - 1, y]
            right = px[min(x1, W - 1), y]
            left_opaque = left[3] > 200 and not near_white(left)
            right_opaque = right[3] > 200 and not near_white(right)
            if 3 <= run <= 90 and left_opaque and right_opaque:
                for xx in range(x0, x1):
                    cand.add((xx, y))
        else:
            x += 1

comps = []
left_over = set(cand)
while left_over:
    seed = left_over.pop()
    comp = [seed]
    qq = deque([seed])
    while qq:
        x, y = qq.popleft()
        for nb in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if nb in left_over:
                left_over.discard(nb)
                comp.append(nb)
                qq.append(nb)
    ys = [p[1] for p in comp]
    comps.append((max(ys) - min(ys), len(comp), comp))

comps.sort(reverse=True)
removed = 0
if comps:
    span, size, comp = comps[0]
    print('largest enclosed-white blob: span %d rows, %d px' % (span, size))
    if span >= int(H * 0.05):
        for xx, yy in comp:
            r, g, b, a = px[xx, yy]
            px[xx, yy] = (r, g, b, 0)
            removed += 1
    else:
        print('skip: blob too small to be a leg gap')
print('gap pixels removed:', removed)

# ---- 3) 边缘羽化 ----
for y in range(1, H - 1):
    for x in range(1, W - 1):
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        holes = 0
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if px[nx, ny][3] == 0:
                holes += 1
        if holes and abs(r - BG[0]) < 26 and abs(g - BG[1]) < 26 and abs(b - BG[2]) < 26:
            px[x, y] = (r, g, b, 120)

im.save(out)
print('saved', out, im.size, 'bbox', im.getbbox())

box = (110, int(H * 0.70), min(W, 240), H)
c = im.crop(box)
scale = max(1, 360 // max(1, c.size[0]))
c = c.resize((c.size[0] * scale, c.size[1] * scale), Image.LANCZOS)
bg = Image.new('RGBA', c.size, (32, 32, 40, 255))
bg.alpha_composite(c)
bg.save(legs_preview)
print('legs preview', legs_preview)
