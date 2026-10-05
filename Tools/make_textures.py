"""Makes the tileable textures used in the scene.

  Shadow Hatch.png    - loose pencil-ish hatching strokes (shadow texture on the plane)
  Shadow Sparkle.png  - little 4 point sparkles and dots (shadow texture on the clouds / stars)
  Cloud Pastel.png    - soft pastel blotches for the textured cloud shader (extra credit)

Everything is drawn with wrap-around so the textures tile with no seams.
For the shadow textures dark = ink, white = paper.
Run from the project root:  python3 Tools/make_textures.py
"""
import math
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SIZE = 512
SS = 4  # supersampling for smoother strokes
OUT_DIR = "Assets/Textures"


def wrapped(draw_fn, size):
    # draw the same shape shifted by the texture size so anything crossing an edge wraps around
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            draw_fn(dx, dy)


def hatch_texture(seed=7):
    rng = random.Random(seed)
    big = SIZE * SS
    img = Image.new("L", (big, big), 255)
    d = ImageDraw.Draw(img)

    # place clumps of strokes on a jittered grid so the coverage is even-ish
    cells = 8
    for cy in range(cells):
        for cx in range(cells):
            ox = (cx + rng.uniform(0.1, 0.9)) / cells * big
            oy = (cy + rng.uniform(0.1, 0.9)) / cells * big
            angle = math.radians(rng.uniform(38, 52))
            count = rng.randint(4, 7)
            spacing = rng.uniform(9, 13) * SS
            for i in range(count):
                length = rng.uniform(40, 75) * SS
                width = rng.uniform(2.5, 4.5) * SS
                shade = rng.randint(40, 120)
                # each stroke starts a little offset along the clump direction
                along = rng.uniform(-6, 6) * SS
                px = ox + (i - count / 2) * spacing * math.cos(angle + math.pi / 2) + along * math.cos(angle)
                py = oy + (i - count / 2) * spacing * math.sin(angle + math.pi / 2) + along * math.sin(angle)
                bend = rng.uniform(-4, 4) * SS
                pts = []
                for k in range(9):
                    t = k / 8.0 - 0.5
                    x = px + t * length * math.cos(angle) + math.sin(t * math.pi) * bend * math.cos(angle + math.pi / 2)
                    y = py + t * length * math.sin(angle) + math.sin(t * math.pi) * bend * math.sin(angle + math.pi / 2)
                    pts.append((x, y))

                def draw(dx, dy, pts=pts, width=width, shade=shade):
                    shifted = [(x + dx, y + dy) for x, y in pts]
                    # taper: thinner at the ends like a real pencil flick
                    for j in range(len(shifted) - 1):
                        t = j / (len(shifted) - 2)
                        w = width * (0.45 + 0.55 * math.sin(t * math.pi))
                        d.line([shifted[j], shifted[j + 1]], fill=shade, width=max(1, int(w)))

                wrapped(draw, big)

    img = img.filter(ImageFilter.GaussianBlur(SS * 0.6))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def sparkle_texture(seed=21):
    rng = random.Random(seed)
    big = SIZE * SS
    img = Image.new("L", (big, big), 255)
    d = ImageDraw.Draw(img)

    def star(cx, cy, r, shade):
        def draw(dx, dy):
            pts = []
            for k in range(8):
                a = k * math.pi / 4
                rr = r if k % 2 == 0 else r * 0.28
                pts.append((cx + dx + rr * math.cos(a), cy + dy + rr * math.sin(a)))
            d.polygon(pts, fill=shade)
        wrapped(draw, big)

    def dot(cx, cy, r, shade):
        def draw(dx, dy):
            d.ellipse([cx + dx - r, cy + dy - r, cx + dx + r, cy + dy + r], fill=shade)
        wrapped(draw, big)

    cells = 5
    for cy in range(cells):
        for cx in range(cells):
            x = (cx + rng.uniform(0.15, 0.85)) / cells * big
            y = (cy + rng.uniform(0.15, 0.85)) / cells * big
            star(x, y, rng.uniform(16, 26) * SS, rng.randint(40, 90))
            for _ in range(3):
                dot(x + rng.uniform(-45, 45) * SS, y + rng.uniform(-45, 45) * SS,
                    rng.uniform(3, 6) * SS, rng.randint(60, 130))

    img = img.filter(ImageFilter.GaussianBlur(SS * 0.5))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def cloud_texture(seed=3):
    # white base with big soft blobs of the pastel colors from the concept (cream, pink, mint, light cyan)
    rng = np.random.default_rng(seed)
    n = SIZE
    y, x = np.mgrid[0:n, 0:n] / n
    img = np.ones((n, n, 3))
    colors = [(255, 245, 222), (255, 230, 241), (218, 250, 240), (228, 247, 255)]
    for col in colors:
        weight = np.zeros((n, n))
        for _ in range(4):
            cx, cy = rng.random(2)
            r = rng.uniform(0.08, 0.16)
            # toroidal distance so blobs wrap around the edges
            dx = np.minimum(abs(x - cx), 1 - abs(x - cx))
            dy = np.minimum(abs(y - cy), 1 - abs(y - cy))
            weight = np.maximum(weight, np.exp(-(dx * dx + dy * dy) / (2 * r * r)))
        weight = np.clip(weight * 1.3, 0, 1) ** 1.5
        c = np.array(col) / 255.0
        img = img * (1 - weight[..., None] * 0.7) + c * weight[..., None] * 0.7
    out = Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGB")
    return out.filter(ImageFilter.GaussianBlur(2))


if __name__ == "__main__":
    hatch_texture().save(f"{OUT_DIR}/Shadow Hatch.png")
    sparkle_texture().save(f"{OUT_DIR}/Shadow Sparkle.png")
    cloud_texture().save(f"{OUT_DIR}/Cloud Pastel.png")
    print("done")
