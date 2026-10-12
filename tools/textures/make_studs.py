"""Generates the square-stud material maps used by the SquareStuds MaterialVariant.

    python3 tools/textures/make_studs.py [out_dir]   (default: assets/textures)

Each 1024 px tile holds 4 x 4 studs (MaterialVariant.StudsPerTile = 4), so one
stud covers one 1 x 1 stud cell, like classic Roblox bricks. Every stud is a
raised rounded square with a soft shoulder. The maps tile seamlessly:

  SquareStuds_Color.png      near-white albedo (the part's colour tints it) with
                             soft contact shadows around each stud
  SquareStuds_Normal.png     tangent-space normal map, OpenGL (+Y up) like
                             Roblox expects
  SquareStuds_Roughness.png  slightly glossier stud tops and edges
  SquareStuds_UI.png         one see-through stud (white highlights, dark
                             shadows) that the UI tiles over panels and
                             buttons of any colour
"""

from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from PIL import Image

SIZE = 1024  # output pixels per tile
STUDS = 4  # studs per tile edge
SUPER = 4  # supersampling factor

HALF = 0.33  # half the stud's side, in studs (cell = 1 stud)
CORNER = 0.09  # corner radius
SHOULDER = 0.06  # width of the rounded top edge
HEIGHT = 0.09  # stud height, in studs

PLATE = 0.95  # albedo between studs
AO_STRENGTH = 0.16
AO_WIDTH = 0.045


def stud_field(n: int) -> tuple[np.ndarray, np.ndarray]:
    """Signed distance to the nearest stud's edge (negative inside) and the
    height (0 on the plate, 1 on the stud top), sampled on an n x n grid."""
    cells = (np.arange(n) + 0.5) / n * STUDS
    u, v = np.meshgrid(cells, cells)  # v grows down the image
    px = np.abs(u - np.floor(u) - 0.5)
    py = np.abs(v - np.floor(v) - 0.5)
    qx = px - (HALF - CORNER)
    qy = py - (HALF - CORNER)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    dist = outside + inside - CORNER
    t = np.clip(-dist / SHOULDER, 0, 1)
    height = np.sqrt(1 - (1 - t) ** 2)  # quarter-circle shoulder: steep wall, round top
    return dist, height


def downsample(a: np.ndarray, k: int) -> np.ndarray:
    n = a.shape[0] // k
    return a.reshape(n, k, n, k, *a.shape[2:]).mean(axis=(1, 3))


def make(out_dir: Path) -> None:
    n = SIZE * SUPER
    dist, height = stud_field(n)
    px_per_stud = n / STUDS

    # Wrapping differences keep the normal map seamless across tile edges.
    dh_du = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / 2 * px_per_stud
    dh_drow = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / 2 * px_per_stud
    # OpenGL convention: +Y (green) points up the image, i.e. against the rows.
    normal = np.stack([-HEIGHT * dh_du, HEIGHT * dh_drow, np.ones_like(height)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    normal = downsample(normal, SUPER)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)

    ao = 1 - AO_STRENGTH * np.exp(-np.maximum(dist, 0) / AO_WIDTH)
    on_stud = np.clip(-dist / 0.004 + 0.5, 0, 1)  # anti-aliased stud mask
    albedo = (PLATE + (1 - PLATE) * on_stud) * np.where(dist > 0, ao, 1.0)
    albedo = downsample(albedo, SUPER)

    shoulder = (height > 0.02) & (height < 0.98)
    roughness = np.where(dist > 0, 0.62, np.where(shoulder, 0.42, 0.5))
    roughness = downsample(roughness, SUPER)

    out_dir.mkdir(parents=True, exist_ok=True)

    def save(name: str, rgb: np.ndarray) -> None:
        img = Image.fromarray(np.clip(np.round(rgb * 255), 0, 255).astype(np.uint8), "RGB")
        img.save(out_dir / name, optimize=True)
        print(f"wrote {out_dir / name}")

    gray = lambda a: np.repeat(a[:, :, None], 3, axis=2)  # noqa: E731
    save("SquareStuds_Color.png", gray(albedo))
    save("SquareStuds_Normal.png", normal * 0.5 + 0.5)
    save("SquareStuds_Roughness.png", gray(roughness))


UI_SIZE = 128  # one stud per UI tile
LIGHT = np.array([-0.45, 0.5, 0.74])  # from the top-left (OpenGL: +Y up the image)


def over(rgb: np.ndarray, alpha: np.ndarray, color: float, a: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """Composite a flat grey/white/black layer with alpha `a` over (rgb, alpha)."""
    out_a = a + alpha * (1 - a)
    safe = np.where(out_a > 0, out_a, 1)
    out_rgb = (color * a + rgb * alpha * (1 - a)) / safe
    return out_rgb, out_a


def make_ui(out_dir: Path) -> None:
    n = UI_SIZE * SUPER
    cells = (np.arange(n) + 0.5) / n
    u, v = np.meshgrid(cells, cells)

    def rounded(cx: float, cy: float) -> np.ndarray:
        qx = np.abs(u - cx) - (HALF - CORNER)
        qy = np.abs(v - cy) - (HALF - CORNER)
        return np.hypot(np.maximum(qx, 0), np.maximum(qy, 0)) + np.minimum(np.maximum(qx, qy), 0) - CORNER

    dist = rounded(0.5, 0.5)
    t = np.clip(-dist / SHOULDER, 0, 1)
    height = np.sqrt(1 - (1 - t) ** 2)
    dh_du = np.gradient(height, axis=1) * n
    dh_drow = np.gradient(height, axis=0) * n
    normal = np.stack([-HEIGHT * dh_du, HEIGHT * dh_drow, np.ones_like(height)], axis=-1)
    normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
    light = LIGHT / np.linalg.norm(LIGHT)
    diffuse = normal @ light - light[2]  # brighter or darker than a flat surface

    rgb = np.zeros((n, n))
    alpha = np.zeros((n, n))
    # soft drop shadow toward the bottom-right
    shadow = np.clip(1 - rounded(0.53, 0.545) / 0.07, 0, 1) * (dist > 0)
    rgb, alpha = over(rgb, alpha, 0.0, 0.2 * shadow)
    inside = np.clip(-dist / 0.004 + 0.5, 0, 1)
    rgb, alpha = over(rgb, alpha, 1.0, 0.07 * inside)  # a slightly lighter top
    rgb, alpha = over(rgb, alpha, 1.0, np.clip(diffuse * 1.1, 0, 0.6))
    rgb, alpha = over(rgb, alpha, 0.0, np.clip(-diffuse * 0.8, 0, 0.42))

    rgb = downsample(rgb, SUPER)
    alpha = downsample(alpha, SUPER)
    rgba = np.dstack([rgb, rgb, rgb, alpha])
    img = Image.fromarray(np.clip(np.round(rgba * 255), 0, 255).astype(np.uint8), "RGBA")
    out_dir.mkdir(parents=True, exist_ok=True)
    img.save(out_dir / "SquareStuds_UI.png", optimize=True)
    print(f"wrote {out_dir / 'SquareStuds_UI.png'}")


if __name__ == "__main__":
    target = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("assets/textures")
    make(target)
    make_ui(target)
