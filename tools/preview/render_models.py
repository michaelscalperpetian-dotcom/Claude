#!/usr/bin/env python3
"""Contact sheets of every dino and egg from models.json (export_models.luau).

Usage:
    python3 render_models.py models.json OUT_DIR [--sheet adults|stages|mutations|eggs|all]
"""

from __future__ import annotations

import argparse
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render3d  # noqa: E402

FONT = "/usr/share/fonts/opentype/inter/Inter-Bold.otf"
LIGHT = render3d.viewport_lighting([0.72, 0.72, 0.78], [1, 0.97, 0.92], [-0.5, -1, 0.6])
LIGHT["sun_strength"] = 0.55


def bounds(parts: list[dict]):
    pts = []
    for p in parts:
        c = np.array(p["cf"][0:3])
        r = np.array(p["cf"][3:12]).reshape(3, 3)
        h = np.array(p["size"]) / 2
        for sx in (-1, 1):
            for sy in (-1, 1):
                for sz in (-1, 1):
                    pts.append(c + r @ (h * np.array([sx, sy, sz])))
    pts = np.array(pts)
    return pts.min(axis=0), pts.max(axis=0)


def render_model(parts: list[dict], size: int, yaw: float = -35, pitch: float = 18, fit: float | None = None) -> Image.Image:
    lo, hi = bounds(parts)
    center = (lo + hi) / 2
    radius = fit or float(np.linalg.norm(hi - lo)) / 2
    fov = 30
    dist = radius / np.tan(np.radians(fov / 2)) * 1.05
    a, e = np.radians(yaw), np.radians(pitch)
    # model faces -Z, so the camera sits on the -Z side
    direction = np.array([np.sin(a) * np.cos(e), np.sin(e), -np.cos(a) * np.cos(e)])
    eye = center + direction * dist
    return render3d.render_rgba(parts, eye, center, fov, size, size, LIGHT, ss=2)


def tile(img: Image.Image, label: str, size: int) -> Image.Image:
    t = Image.new("RGBA", (size, size + 26), (236, 241, 250, 255))
    t.alpha_composite(img, (0, 0))
    d = ImageDraw.Draw(t)
    f = ImageFont.truetype(FONT, 15)
    w = d.textlength(label, font=f)
    d.text(((size - w) / 2, size + 4), label, font=f, fill=(40, 34, 60))
    return t


def grid(tiles: list[Image.Image], cols: int) -> Image.Image:
    w, h = tiles[0].size
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * w, rows * h), (255, 255, 255, 255))
    for i, t in enumerate(tiles):
        sheet.alpha_composite(t, ((i % cols) * w, (i // cols) * h))
    return sheet


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("models")
    ap.add_argument("out")
    ap.add_argument("--sheet", default="all")
    ap.add_argument("--only", default=None, help="comma-separated species ids")
    ap.add_argument("--size", type=int, default=230)
    ap.add_argument("--yaw", type=float, default=-35)
    args = ap.parse_args()
    data = json.load(open(args.models))
    only = set(args.only.split(",")) if args.only else None
    dinos = [d for d in data["dinos"] if not only or d["id"] in only]
    s = args.size
    sheets = ["adults", "stages", "mutations", "eggs"] if args.sheet == "all" else [args.sheet]
    for name in sheets:
        tiles = []
        if name == "adults":
            for d in dinos:
                tiles.append(tile(render_model(d["stages"]["3"] if isinstance(d["stages"], dict) else d["stages"][2], s, args.yaw), d["name"], s))
            cols = 5
        elif name == "stages":
            for d in dinos:
                stages = d["stages"] if isinstance(d["stages"], list) else [d["stages"][k] for k in sorted(d["stages"])]
                # same camera distance for all stages so growth is visible
                fit = float(np.linalg.norm(np.subtract(*bounds(stages[3])[::-1]))) / 2
                for i, parts in enumerate(stages):
                    tiles.append(tile(render_model(parts, s, args.yaw, fit=fit), f"{d['id']} {['Baby', 'Juvenile', 'Adult', 'Giant'][i]}", s))
            cols = 4
        elif name == "mutations":
            for d in dinos:
                for m, parts in d["mutations"].items():
                    tiles.append(tile(render_model(parts, s, args.yaw), f"{m} {d['id']}", s))
            cols = len(dinos[0]["mutations"]) if dinos else 5
        else:
            for e in data["eggs"]:
                tiles.append(tile(render_model(e["parts"], s // 2 * 2, -20, 10), e["id"], s))
            cols = 6
        if tiles:
            out = os.path.join(args.out, f"models_{name}.png")
            grid(tiles, cols).convert("RGB").save(out)
            print("wrote", out)


if __name__ == "__main__":
    main()
