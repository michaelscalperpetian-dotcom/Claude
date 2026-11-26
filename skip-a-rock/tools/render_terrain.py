#!/usr/bin/env python3
"""Preview renderer for Skip a Rock: terrain + the open ocean + parts.

Ray-marches the height grid written by export_scene.luau (terrain.json), shades
it by material with a sun, soft sky light, heightfield shadows and haze, draws
the lake as a reflective water surface, and composites the part scene from the
repo's render3d.py on top using depth. An approximation of Roblox's renderer:
good for judging shapes, colours and composition, not exact lighting.

Usage:
    python3 render_terrain.py OUT_DIR out.png --eye 0,40,-260 --target 0,0,0 [--fov 60] [--size 1280x720]
"""

from __future__ import annotations

import argparse
import json
import math
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "tools", "preview"))
import render3d  # noqa: E402


class Heightfield:
    def __init__(self, data: dict):
        self.ox = float(data["originX"])
        self.oz = float(data["originZ"])
        self.step = float(data["step"])
        self.h = np.array(data["heights"], dtype=np.float64)  # [z][x]
        self.nz, self.nx = self.h.shape
        names = sorted({m for row in data["materials"] for m in row})
        self.names = names
        lookup = {n: i for i, n in enumerate(names)}
        self.mat = np.array([[lookup[m] for m in row] for row in data["materials"]], dtype=np.int32)
        palette = []
        for n in names:
            palette.append(data["colors"].get(n, [0.5, 0.5, 0.5]))
        self.palette = np.array(palette, dtype=np.float64)
        self.water = np.array(data["water"], dtype=np.float64)
        # a little per-cell colour variation, like terrain texture
        rng = np.random.default_rng(3)
        self.grain = 1 + (rng.random(self.h.shape) - 0.5) * 0.12

    def _cell(self, x, z):
        gx = (x - self.ox) / self.step
        gz = (z - self.oz) / self.step
        gx = np.clip(gx, 0, self.nx - 1.001)
        gz = np.clip(gz, 0, self.nz - 1.001)
        i0 = np.floor(gx).astype(np.int64)
        k0 = np.floor(gz).astype(np.int64)
        return gx - i0, gz - k0, i0, k0

    def height(self, x, z):
        fx, fz, i0, k0 = self._cell(x, z)
        h = self.h
        a = h[k0, i0] * (1 - fx) + h[k0, i0 + 1] * fx
        b = h[k0 + 1, i0] * (1 - fx) + h[k0 + 1, i0 + 1] * fx
        return a * (1 - fz) + b * fz

    def normal(self, x, z):
        d = self.step * 0.5
        dx = self.height(x + d, z) - self.height(x - d, z)
        dz = self.height(x, z + d) - self.height(x, z - d)
        n = np.stack([-dx, np.full_like(dx, 2 * d), -dz], axis=-1)
        return n / np.linalg.norm(n, axis=-1, keepdims=True)

    def albedo(self, x, z):
        _, _, i0, k0 = self._cell(x + self.step / 2, z + self.step / 2)
        return self.palette[self.mat[k0, i0]] * self.grain[k0, i0][:, None]

    def inside(self, x, z):
        x1 = self.ox + (self.nx - 1) * self.step
        z1 = self.oz + (self.nz - 1) * self.step
        return (x > self.ox) & (x < x1) & (z > self.oz) & (z < z1)

    def height_or_sea(self, x, z):
        """Ground height on the grid; deep sea floor out in the open ocean."""
        return np.where(self.inside(x, z), self.height(x, z), -30.0)


def march(field: Heightfield, origins, dirs, far=9000.0, steps=520):
    """First hit with the ground or the water surface (y = 0 over the lake)."""
    n = len(dirs)
    t = np.full(n, 0.5)
    hit_t = np.full(n, np.inf)
    hit_kind = np.zeros(n, dtype=np.int8)  # 1 ground, 2 water
    active = np.ones(n, dtype=bool)
    prev_t = t.copy()
    for _ in range(steps):
        idx = np.nonzero(active)[0]
        if len(idx) == 0:
            break
        p = origins[idx] + dirs[idx] * t[idx, None]
        h = field.height_or_sea(p[:, 0], p[:, 2])
        below = p[:, 1] < h
        water = (p[:, 1] < 0) & (h < 0) & ~below
        out = t[idx] > far
        done = below | water | out
        if np.any(below):
            # refine the ground hit between the last two samples
            j = idx[below]
            lo, hi = prev_t[j].copy(), t[j].copy()
            for _ in range(8):
                mid = (lo + hi) / 2
                q = origins[j] + dirs[j] * mid[:, None]
                under = q[:, 1] < field.height(q[:, 0], q[:, 2])
                hi = np.where(under, mid, hi)
                lo = np.where(under, lo, mid)
            hit_t[j] = hi
            hit_kind[j] = 1
        if np.any(water):
            j = idx[water]
            # exact crossing of y = 0
            hit_t[j] = (0 - origins[j, 1]) / np.where(np.abs(dirs[j, 1]) < 1e-9, -1e-9, dirs[j, 1])
            hit_kind[j] = 2
        active[idx[done]] = False
        prev_t[idx] = t[idx]
        # step grows with distance and with clearance above the ground
        clearance = np.maximum(p[:, 1] - np.maximum(h, 0), 0)
        t[idx] += np.clip(0.35 * clearance + t[idx] * 0.004, 0.25, 60)
    return hit_t, hit_kind


def shadowed(field: Heightfield, points, sun, steps=48):
    lit = np.ones(len(points), dtype=bool)
    t = np.full(len(points), 1.5)
    for _ in range(steps):
        p = points + sun[None, :] * t[:, None]
        h = field.height(p[:, 0], p[:, 2])
        lit &= (p[:, 1] > h - 0.2) | ~field.inside(p[:, 0], p[:, 2])
        t += np.clip(t * 0.15, 1.0, 40)
    return ~lit


def render(field: Heightfield, scene: dict, eye, target, fov, w, h):
    light = render3d.DAY
    cam = render3d.Camera(eye, target, fov, w, h)
    ys, xs = np.mgrid[0:h, 0:w]
    origins, dirs = cam.rays(xs.ravel().astype(np.float64), ys.ravel().astype(np.float64))

    # sky
    up = np.clip(dirs[:, 1], -0.2, 1.0)
    tsky = np.clip(up * 1.6, 0, 1)[:, None]
    sky = np.array(light["sky_horizon"]) * (1 - tsky) + np.array(light["sky_top"]) * tsky
    img = sky.copy()

    sun = np.array(light["sun_dir"], dtype=np.float64)
    sun /= np.linalg.norm(sun)
    hit_t, kind = march(field, origins, dirs)
    depth = hit_t.copy()

    ground = kind == 1
    if np.any(ground):
        p = origins[ground] + dirs[ground] * hit_t[ground, None]
        n = field.normal(p[:, 0], p[:, 2])
        base = field.albedo(p[:, 0], p[:, 2])
        ndl = np.clip(n @ sun, 0, 1)
        ndl = np.where(shadowed(field, p + n * 0.5, sun), 0.0, ndl)
        hemi = n[:, 1:2] * 0.5 + 0.5
        amb = np.array(light["ground_ambient"]) * (1 - hemi) + np.array(light["sky_ambient"]) * hemi
        img[ground] = base * (amb + np.array(light["sun_color"]) * light["sun_strength"] * 1.6 * ndl[:, None])

    water = kind == 2
    if np.any(water):
        p = origins[water] + dirs[water] * hit_t[water, None]
        bed = field.height_or_sea(p[:, 0], p[:, 2])
        depthw = np.clip(-bed, 0, 20)
        # what lies under the water, fading with depth
        under = field.albedo(p[:, 0], p[:, 2]) * 0.75
        clarity = np.exp(-depthw * 0.35)[:, None]
        body = under * clarity + field.water * (1 - clarity)
        # sky reflection, stronger at grazing angles (Fresnel)
        cos = np.clip(-dirs[water, 1], 0, 1)
        fres = (0.04 + 0.96 * (1 - cos) ** 5)[:, None] * 0.9 + 0.08
        refl_dir = dirs[water] * np.array([1, -1, 1])
        rt = np.clip(refl_dir[:, 1] * 1.6, 0, 1)[:, None]
        reflected = np.array(light["sky_horizon"]) * (1 - rt) + np.array(light["sky_top"]) * rt
        # sun glint
        half = sun - dirs[water]
        half /= np.linalg.norm(half, axis=1, keepdims=True)
        spec = np.clip(half[:, 1], 0, 1) ** 400 * 1.5
        img[water] = body * (1 - fres) + reflected * fres + spec[:, None]

    hit = ground | water
    fog = 1 - np.exp(-np.where(hit, hit_t, 0) * light["haze_density"] * 0.8)
    img[hit] = img[hit] * (1 - fog[hit, None]) + np.array(light["haze"]) * fog[hit, None]

    # parts on top, wherever they're nearer
    parts = render3d.load_parts(scene["parts"])
    pimg, pmask = render3d.render(parts, cam, light, shadows=True, with_mask=True)
    pdepth, _, _ = render3d.raster(parts, cam)
    pimg = pimg.reshape(-1, 3)
    pmask = pmask.reshape(-1)
    pdepth = pdepth.reshape(-1)
    nearer = pmask & (pdepth < depth)
    img[nearer] = pimg[nearer]

    gray = img.mean(axis=1, keepdims=True)
    img = gray + (img - gray) * light.get("saturation", 1.0)
    img = np.clip(img, 0, 1).reshape(h, w, 3)
    return Image.fromarray((img * 255).astype(np.uint8))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("out")
    ap.add_argument("--eye", required=True)
    ap.add_argument("--target", required=True)
    ap.add_argument("--fov", type=float, default=60)
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--ss", type=int, default=1)
    args = ap.parse_args()
    field = Heightfield(json.load(open(os.path.join(args.dir, "terrain.json"))))
    scene = json.load(open(os.path.join(args.dir, "scene.json")))
    w, h = (int(v) for v in args.size.split("x"))
    eye = tuple(float(v) for v in args.eye.split(","))
    target = tuple(float(v) for v in args.target.split(","))
    img = render(field, scene, eye, target, args.fov, w * args.ss, h * args.ss)
    if args.ss > 1:
        img = img.resize((w, h), Image.LANCZOS)
    img.save(args.out)
    print("wrote", args.out)


if __name__ == "__main__":
    main()
