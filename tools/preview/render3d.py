#!/usr/bin/env python3
"""Software renderer for Roblox part scenes exported by export_scene.luau.

Ray-casts Roblox part shapes (blocks, wedges, balls, cylinders and
SpecialMesh spheres) with a sun, soft ambient light, shadow mapping and haze,
so map and model changes can be checked visually without Roblox Studio.
It is an approximation of Roblox's renderer, good for judging shapes, colors,
composition and scale, not exact lighting.

Usage:
    python3 render3d.py scene.json out.png --eye 0,120,-200 --target 0,0,0 --fov 60
    python3 render3d.py scene.json out.png --view overview
"""

from __future__ import annotations

import argparse
import json
import math

import numpy as np
from PIL import Image

EPS = 1e-4


# --------------------------------------------------------------------------- parts


class Part:
    __slots__ = ("shape", "center", "rot", "half", "color", "material", "transparency", "reflectance", "name")

    def __init__(self, data: dict):
        cf = data["cf"]
        self.center = np.array(cf[0:3], dtype=np.float64)
        self.rot = np.array(cf[3:12], dtype=np.float64).reshape(3, 3)  # columns = local axes
        self.half = np.array(data["size"], dtype=np.float64) / 2.0
        self.shape = data.get("shape", "Block")
        self.color = np.array(data["color"], dtype=np.float64)
        self.material = data.get("material", "SmoothPlastic")
        self.transparency = float(data.get("transparency", 0))
        self.reflectance = float(data.get("reflectance", 0))
        self.name = data.get("name", "")

    def corners(self) -> np.ndarray:
        signs = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], dtype=np.float64)
        return (self.rot @ (signs * self.half).T).T + self.center

    def radius(self) -> float:
        return float(np.linalg.norm(self.half))


def load_parts(items: list[dict]) -> list[Part]:
    parts = []
    for item in items:
        if float(item.get("transparency", 0)) >= 0.6:
            continue
        values = list(item["cf"]) + list(item["size"])
        if any(v is None or (isinstance(v, float) and math.isnan(v)) for v in values):
            print(f"warning: skipping part {item.get('name')} with an invalid CFrame")
            continue
        parts.append(Part(item))
    return parts


# --------------------------------------------------------------------- intersection


def _convex(o: np.ndarray, d: np.ndarray, planes: list[tuple[np.ndarray, float]]):
    n_rays = d.shape[0]
    t_enter = np.full(n_rays, -np.inf)
    t_exit = np.full(n_rays, np.inf)
    normal = np.zeros((n_rays, 3))
    valid = np.ones(n_rays, dtype=bool)
    for n, dist in planes:
        denom = d @ n
        num = dist - o @ n
        with np.errstate(divide="ignore", invalid="ignore"):
            t = num / denom
        entering = denom < -1e-12
        exiting = denom > 1e-12
        parallel = ~(entering | exiting)
        valid &= ~(parallel & (num < 0))
        better = entering & (t > t_enter)
        t_enter = np.where(better, t, t_enter)
        normal[better] = n
        t_exit = np.where(exiting, np.minimum(t_exit, t), t_exit)
    hit = valid & (t_enter <= t_exit) & (t_enter > EPS)
    t = np.where(hit, t_enter, np.inf)
    return t, normal


def _box_planes(h: np.ndarray):
    return [
        (np.array([1.0, 0, 0]), h[0]),
        (np.array([-1.0, 0, 0]), h[0]),
        (np.array([0, 1.0, 0]), h[1]),
        (np.array([0, -1.0, 0]), h[1]),
        (np.array([0, 0, 1.0]), h[2]),
        (np.array([0, 0, -1.0]), h[2]),
    ]


def intersect(part: Part, o: np.ndarray, d: np.ndarray):
    """o: ray origin in local space (3,), d: local directions (N,3). Returns t (N,), local normals (N,3)."""
    h = part.half
    shape = part.shape
    if shape in ("Block", "Wedge", "CornerWedge"):
        planes = _box_planes(h)
        if shape == "Wedge":
            # Roblox wedge: full height at the back (+Z), slope down to the front (-Z).
            n = np.array([0.0, h[2], -h[1]])
            planes.append((n / np.linalg.norm(n), 0.0))
        elif shape == "CornerWedge":
            n1 = np.array([h[0], h[2] * 0 + 0.0, 0.0])
            planes.append((np.array([0.0, h[2], -h[1]]) / np.linalg.norm([h[2], h[1]]), 0.0))
            planes.append((np.array([-h[1], h[0], 0.0]) / np.linalg.norm([h[1], h[0]]), 0.0))
            del n1
        return _convex(o, d, planes)
    if shape in ("Ellipsoid", "Ball"):
        if shape == "Ball":
            r = float(h.min())
            scale = np.array([r, r, r])
        else:
            scale = h
        os_ = o / scale
        ds = d / scale
        a = np.einsum("ij,ij->i", ds, ds)
        b = 2.0 * (ds @ os_)
        c = float(os_ @ os_) - 1.0
        disc = b * b - 4 * a * c
        hit = disc >= 0
        sq = np.sqrt(np.where(hit, disc, 0))
        t = (-b - sq) / (2 * a)
        hit &= t > EPS
        t = np.where(hit, t, np.inf)
        p = o + d * np.where(hit, t, 0)[:, None]
        normal = p / (scale * scale)
        return t, normal
    if shape == "Cylinder":
        r = float(min(h[1], h[2]))
        hx = float(h[0])
        dy, dz, dx = d[:, 1], d[:, 2], d[:, 0]
        oy, oz, ox = o[1], o[2], o[0]
        a = dy * dy + dz * dz
        b = 2 * (oy * dy + oz * dz)
        c = oy * oy + oz * oz - r * r
        disc = b * b - 4 * a * c
        side_ok = (disc >= 0) & (a > 1e-12)
        sq = np.sqrt(np.where(side_ok, disc, 0))
        with np.errstate(divide="ignore", invalid="ignore"):
            t_side = (-b - sq) / (2 * a)
        x_side = ox + t_side * dx
        side_ok &= (t_side > EPS) & (np.abs(x_side) <= hx)
        t_side = np.where(side_ok, t_side, np.inf)
        best_t = t_side
        normal = np.zeros_like(d)
        p_side = o + d * np.where(side_ok, t_side, 0)[:, None]
        normal[:, 1] = p_side[:, 1]
        normal[:, 2] = p_side[:, 2]
        for sign in (1.0, -1.0):
            with np.errstate(divide="ignore", invalid="ignore"):
                t_cap = (sign * hx - ox) / dx
            py = oy + t_cap * dy
            pz = oz + t_cap * dz
            cap_ok = (np.abs(dx) > 1e-12) & (t_cap > EPS) & (py * py + pz * pz <= r * r)
            closer = cap_ok & (t_cap < best_t)
            best_t = np.where(closer, t_cap, best_t)
            normal[closer] = np.array([sign, 0.0, 0.0])
        return best_t, normal
    # Unknown shapes render as blocks.
    return _convex(o, d, _box_planes(h))


# ------------------------------------------------------------------------- cameras


class Camera:
    def __init__(self, eye, target, fov_deg, width, height, ortho_size: float | None = None):
        self.eye = np.array(eye, dtype=np.float64)
        self.target = np.array(target, dtype=np.float64)
        self.width = width
        self.height = height
        self.aspect = width / height
        self.tan = math.tan(math.radians(fov_deg) / 2)
        self.ortho = ortho_size
        forward = self.target - self.eye
        self.forward = forward / np.linalg.norm(forward)
        world_up = np.array([0.0, 1.0, 0.0])
        if abs(self.forward @ world_up) > 0.999:
            world_up = np.array([0.0, 0.0, 1.0])
        right = np.cross(self.forward, world_up)
        self.right = right / np.linalg.norm(right)
        self.up = np.cross(self.right, self.forward)

    def rays(self, xs: np.ndarray, ys: np.ndarray):
        nx = ((xs + 0.5) / self.width * 2 - 1) * self.aspect
        ny = 1 - (ys + 0.5) / self.height * 2
        if self.ortho:
            origins = (
                self.eye[None, :]
                + (nx * self.ortho)[:, None] * self.right[None, :]
                + (ny * self.ortho)[:, None] * self.up[None, :]
            )
            dirs = np.repeat(self.forward[None, :], len(xs), axis=0)
            return origins, dirs
        dirs = (
            self.forward[None, :]
            + (nx * self.tan)[:, None] * self.right[None, :]
            + (ny * self.tan)[:, None] * self.up[None, :]
        )
        dirs /= np.linalg.norm(dirs, axis=1, keepdims=True)
        return np.repeat(self.eye[None, :], len(xs), axis=0), dirs

    def project(self, points: np.ndarray):
        v = points - self.eye
        z = v @ self.forward
        if self.ortho:
            x = (v @ self.right) / (self.ortho * self.aspect)
            y = (v @ self.up) / self.ortho
            z = np.maximum(z, 1.0)
        else:
            with np.errstate(divide="ignore", invalid="ignore"):
                x = (v @ self.right) / (z * self.tan * self.aspect)
                y = (v @ self.up) / (z * self.tan)
        px = (x + 1) / 2 * self.width
        py = (1 - y) / 2 * self.height
        return px, py, z


def raster(parts: list[Part], cam: Camera):
    """Closest hit per pixel: returns depth, part index, local normal arrays."""
    W, H = cam.width, cam.height
    depth = np.full(H * W, np.inf)
    index = np.full(H * W, -1, dtype=np.int64)
    normals = np.zeros((H * W, 3))
    for i, part in enumerate(parts):
        corners = part.corners()
        px, py, z = cam.project(corners)
        if np.all(z < 0.05):
            continue
        if np.any(z < 0.05) or not np.all(np.isfinite(px)):
            x0, x1, y0, y1 = 0, W - 1, 0, H - 1
        else:
            x0 = int(max(0, math.floor(px.min()) - 1))
            x1 = int(min(W - 1, math.ceil(px.max()) + 1))
            y0 = int(max(0, math.floor(py.min()) - 1))
            y1 = int(min(H - 1, math.ceil(py.max()) + 1))
            if x0 > x1 or y0 > y1:
                continue
        ys, xs = np.mgrid[y0 : y1 + 1, x0 : x1 + 1]
        xs = xs.ravel().astype(np.float64)
        ys = ys.ravel().astype(np.float64)
        origins, dirs = cam.rays(xs, ys)
        rt = part.rot.T
        d_local = dirs @ part.rot  # == (rot.T @ d.T).T
        if cam.ortho:
            o_local_all = (origins - part.center) @ part.rot
            # Orthographic: origins differ per ray; intersect in chunks sharing math via broadcasting.
            t, n_local = _intersect_many(part, o_local_all, d_local)
        else:
            o_local = rt @ (cam.eye - part.center)
            t, n_local = intersect(part, o_local, d_local)
        flat = (ys.astype(np.int64) * W + xs.astype(np.int64))
        closer = t < depth[flat]
        if not np.any(closer):
            continue
        sel = flat[closer]
        depth[sel] = t[closer]
        index[sel] = i
        normals[sel] = n_local[closer]
    return depth.reshape(H, W), index.reshape(H, W), normals.reshape(H, W, 3)


def _intersect_many(part: Part, o_local: np.ndarray, d_local: np.ndarray):
    """Ray origins vary per ray (orthographic shadow map). Shift each ray so its
    origin is the same point along a shared plane, then reuse intersect()."""
    # Parallel rays: move every origin back along the ray so all share t-offset 0,
    # then solve per unique origin batch. Simple approach: loop over shape math
    # with per-ray origins by translating into a common frame per ray.
    t = np.full(len(d_local), np.inf)
    normals = np.zeros_like(d_local)
    # Vectorized trick: intersect(o, d) only uses o in dot products, so evaluate
    # in chunks where we pass each ray's own origin via a generalized version.
    return _intersect_vec_origins(part, o_local, d_local, t, normals)


def _intersect_vec_origins(part: Part, O: np.ndarray, D: np.ndarray, t_out, n_out):
    h = part.half
    shape = part.shape
    if shape in ("Ellipsoid", "Ball"):
        scale = np.array([h.min()] * 3) if shape == "Ball" else h
        os_ = O / scale
        ds = D / scale
        a = np.einsum("ij,ij->i", ds, ds)
        b = 2.0 * np.einsum("ij,ij->i", ds, os_)
        c = np.einsum("ij,ij->i", os_, os_) - 1.0
        disc = b * b - 4 * a * c
        hit = disc >= 0
        t = (-b - np.sqrt(np.where(hit, disc, 0))) / (2 * a)
        hit &= t > EPS
        return np.where(hit, t, np.inf), n_out
    if shape == "Cylinder":
        r = float(min(h[1], h[2]))
        hx = float(h[0])
        a = D[:, 1] ** 2 + D[:, 2] ** 2
        b = 2 * (O[:, 1] * D[:, 1] + O[:, 2] * D[:, 2])
        c = O[:, 1] ** 2 + O[:, 2] ** 2 - r * r
        disc = b * b - 4 * a * c
        ok = (disc >= 0) & (a > 1e-12)
        with np.errstate(divide="ignore", invalid="ignore"):
            ts = (-b - np.sqrt(np.where(ok, disc, 0))) / (2 * a)
        ok &= (ts > EPS) & (np.abs(O[:, 0] + ts * D[:, 0]) <= hx)
        best = np.where(ok, ts, np.inf)
        for sign in (1.0, -1.0):
            with np.errstate(divide="ignore", invalid="ignore"):
                tc = (sign * hx - O[:, 0]) / D[:, 0]
            py = O[:, 1] + tc * D[:, 1]
            pz = O[:, 2] + tc * D[:, 2]
            cap = (np.abs(D[:, 0]) > 1e-12) & (tc > EPS) & (py * py + pz * pz <= r * r)
            best = np.where(cap & (tc < best), tc, best)
        return best, n_out
    planes = _box_planes(h)
    if shape == "Wedge":
        n = np.array([0.0, h[2], -h[1]])
        planes.append((n / np.linalg.norm(n), 0.0))
    t_enter = np.full(len(D), -np.inf)
    t_exit = np.full(len(D), np.inf)
    valid = np.ones(len(D), dtype=bool)
    for n, dist in planes:
        denom = D @ n
        num = dist - O @ n
        with np.errstate(divide="ignore", invalid="ignore"):
            t = num / denom
        entering = denom < -1e-12
        exiting = denom > 1e-12
        valid &= ~(~(entering | exiting) & (num < 0))
        t_enter = np.where(entering & (t > t_enter), t, t_enter)
        t_exit = np.where(exiting, np.minimum(t_exit, t), t_exit)
    hit = valid & (t_enter <= t_exit) & (t_enter > EPS)
    return np.where(hit, t_enter, np.inf), n_out


# ------------------------------------------------------------------------ lighting

DAY = {
    "sun_dir": (-0.35, 0.85, -0.4),
    "sun_color": (1.0, 0.96, 0.88),
    "sun_strength": 0.62,
    "sky_ambient": (0.62, 0.68, 0.78),
    "ground_ambient": (0.46, 0.44, 0.40),
    "sky_top": (0.36, 0.62, 0.95),
    "sky_horizon": (0.78, 0.89, 1.0),
    "haze": (0.80, 0.88, 1.0),
    "haze_density": 0.0011,
    "saturation": 1.12,
}

NIGHT = {
    "sun_dir": (0.3, 0.8, 0.5),
    "sun_color": (0.65, 0.72, 1.0),
    "sun_strength": 0.28,
    "sky_ambient": (0.33, 0.36, 0.55),
    "ground_ambient": (0.22, 0.22, 0.32),
    "sky_top": (0.05, 0.07, 0.2),
    "sky_horizon": (0.18, 0.2, 0.42),
    "haze": (0.2, 0.22, 0.4),
    "haze_density": 0.0016,
    "saturation": 1.0,
}


def shadow_map(parts: list[Part], light_dir: np.ndarray, size: int = 2048):
    # Huge flat parts (ocean, island base) don't cast useful shadows and would
    # stretch the shadow map, so only reasonably sized parts are casters.
    casters = [p for p in parts if p.radius() < 120]
    parts = casters
    pts = np.concatenate([p.corners() for p in parts]) if parts else np.zeros((1, 3))
    lo = pts.min(axis=0)
    hi = pts.max(axis=0)
    center = (lo + hi) / 2
    extent = float(np.linalg.norm(hi - lo)) / 2 + 2
    eye = center + light_dir * extent * 2
    cam = Camera(eye, center, 60, size, size, ortho_size=extent)
    depth, _, _ = raster(parts, cam)
    return cam, depth


def in_shadow(points: np.ndarray, cam: Camera, depth: np.ndarray, bias: float = 1.2):
    px, py, z = cam.project(points)
    ix = np.clip(px.astype(np.int64), 0, cam.width - 1)
    iy = np.clip(py.astype(np.int64), 0, cam.height - 1)
    inside = (px >= 0) & (px < cam.width) & (py >= 0) & (py < cam.height)
    occluder = depth[iy, ix]
    return inside & (occluder + bias < z)


def render(parts: list[Part], cam: Camera, lighting: dict, shadows: bool = True, with_mask: bool = False):
    depth, index, normals_local = raster(parts, cam)
    H, W = depth.shape
    ys, xs = np.mgrid[0:H, 0:W]
    _, dirs = cam.rays(xs.ravel().astype(np.float64), ys.ravel().astype(np.float64))
    dirs = dirs.reshape(H, W, 3)

    # sky gradient
    up = np.clip(dirs[:, :, 1], -0.2, 1.0)
    tsky = np.clip(up * 1.6, 0, 1)[:, :, None]
    sky = np.array(lighting["sky_horizon"]) * (1 - tsky) + np.array(lighting["sky_top"]) * tsky
    img = sky.copy()

    hit = index >= 0
    if np.any(hit):
        idx = index[hit]
        rots = np.stack([parts[i].rot for i in range(len(parts))])
        colors = np.stack([parts[i].color for i in range(len(parts))])
        neon = np.array([parts[i].material == "Neon" for i in range(len(parts))])
        refl = np.array([parts[i].reflectance for i in range(len(parts))])
        glass = np.array([parts[i].material in ("Glass", "Ice", "ForceField") for i in range(len(parts))])
        trans = np.array([parts[i].transparency for i in range(len(parts))])

        n_local = normals_local[hit]
        n_world = np.einsum("nij,nj->ni", rots[idx], n_local)
        n_world /= np.linalg.norm(n_world, axis=1, keepdims=True) + 1e-12
        view = dirs[hit]
        facing = np.einsum("ij,ij->i", n_world, view) > 0
        n_world[facing] *= -1

        light = np.array(lighting["sun_dir"], dtype=np.float64)
        light /= np.linalg.norm(light)
        ndl = np.clip(n_world @ light, 0, 1)

        points = cam.eye + view * depth[hit][:, None]
        if shadows:
            scam, sdepth = shadow_map(parts, light)
            shadowed = in_shadow(points + n_world * 0.3, scam, sdepth)
            ndl = np.where(shadowed, 0.0, ndl)

        hemi = (n_world[:, 1:2] * 0.5 + 0.5)
        ambient = np.array(lighting["ground_ambient"]) * (1 - hemi) + np.array(lighting["sky_ambient"]) * hemi
        base = colors[idx]
        lit = base * (ambient + np.array(lighting["sun_color"]) * lighting["sun_strength"] * 1.6 * ndl[:, None])
        # soft rim so silhouettes read like Roblox's specular
        rim = np.clip(1 - np.abs(np.einsum("ij,ij->i", n_world, -view)), 0, 1) ** 3
        lit += rim[:, None] * 0.08
        r = refl[idx][:, None]
        lit = lit * (1 - r * 0.5) + np.array(lighting["sky_horizon"]) * r * 0.6
        g = glass[idx][:, None]
        lit = np.where(g, lit * 0.85 + 0.12, lit)
        t = trans[idx][:, None]
        lit = lit * (1 - t) + img[hit] * t
        n = neon[idx][:, None]
        lit = np.where(n, base * 1.25 + 0.08, lit)

        dist = depth[hit][:, None]
        fog = 1 - np.exp(-dist * lighting["haze_density"])
        lit = lit * (1 - fog) + np.array(lighting["haze"]) * fog
        img[hit] = lit

    # saturation boost (like ColorCorrection)
    gray = img.mean(axis=2, keepdims=True)
    img = gray + (img - gray) * lighting.get("saturation", 1.0)
    img = np.clip(img, 0, 1)
    if with_mask:
        return img, hit
    return img


def to_image(img: np.ndarray, ss: int) -> Image.Image:
    im = Image.fromarray((img * 255).astype(np.uint8))
    if ss > 1:
        im = im.resize((im.width // ss, im.height // ss), Image.LANCZOS)
    return im


def render_parts(items: list[dict], eye, target, fov, width, height, ss=2, night=False, shadows=True) -> Image.Image:
    parts = load_parts(items)
    cam = Camera(eye, target, fov, width * ss, height * ss)
    img = render(parts, cam, NIGHT if night else DAY, shadows=shadows)
    return to_image(img, ss)


def viewport_lighting(ambient, light_color, light_direction) -> dict:
    """Lighting for a ViewportFrame: one directional light plus flat ambient, no sky or fog."""
    amb = np.array(ambient, dtype=np.float64)
    return {
        "sun_dir": tuple(-np.array(light_direction, dtype=np.float64)),
        "sun_color": tuple(light_color),
        "sun_strength": 0.5,
        "sky_ambient": tuple(amb * 0.95),
        "ground_ambient": tuple(amb * 0.75),
        "sky_top": (0, 0, 0),
        "sky_horizon": (0, 0, 0),
        "haze": (0, 0, 0),
        "haze_density": 0.0,
        "saturation": 1.05,
    }


def render_rgba(items: list[dict], eye, target, fov, width, height, lighting: dict, ss=3) -> Image.Image:
    """Transparent-background render (for ViewportFrames in UI previews)."""
    parts = load_parts(items)
    w, h = max(1, int(width * ss)), max(1, int(height * ss))
    cam = Camera(eye, target, fov, w, h)
    img, mask = render(parts, cam, lighting, shadows=False, with_mask=True)
    rgba = np.concatenate([img, mask[:, :, None].astype(np.float64)], axis=2)
    im = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
    return im.resize((max(1, int(width)), max(1, int(height))), Image.LANCZOS)


def plot_view(scene: dict, plot_index: int, distance: float, height: float, look_height: float = 2.0):
    """Camera standing outside a plot's gate, looking in."""
    plot = next(p for p in scene["plots"] if p["index"] == plot_index)
    cf = plot["cf"]
    pos = np.array(cf[0:3])
    rot = np.array(cf[3:12]).reshape(3, 3)
    back = rot[:, 2]  # +Z local in world (Roblox LookVector is -Z)
    look = -back
    eye = pos + look * distance + np.array([0, height, 0])
    target = pos + np.array([0, look_height, 0])
    return eye, target


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("scene")
    ap.add_argument("out")
    ap.add_argument("--eye", default=None)
    ap.add_argument("--target", default="0,0,0")
    ap.add_argument("--fov", type=float, default=60)
    ap.add_argument("--size", default="1280x720")
    ap.add_argument("--ss", type=int, default=2)
    ap.add_argument("--night", action="store_true")
    ap.add_argument("--noshadow", action="store_true")
    ap.add_argument("--view", default=None, help="overview | plot:N | hub | lineup")
    args = ap.parse_args()

    with open(args.scene) as f:
        scene = json.load(f)
    w, h = (int(v) for v in args.size.split("x"))

    if args.view == "overview":
        eye, target = (150, 240, -330), (0, -10, 10)
    elif args.view == "hub":
        eye, target = (0, 26, -62), (0, 8, 0)
    elif args.view and args.view.startswith("plot:"):
        eye, target = plot_view(scene, int(args.view.split(":")[1]), 62, 30)
    elif args.view == "lineup":
        parts = scene["parts"]
        pts = np.array([p["cf"][0:3] for p in parts])
        lo, hi = pts.min(axis=0), pts.max(axis=0)
        center = (lo + hi) / 2
        span = float(np.linalg.norm(hi - lo))
        eye = center + np.array([0.0, span * 0.55, -span * 0.75])
        target = center
    else:
        eye = tuple(float(v) for v in args.eye.split(",")) if args.eye else (0, 120, -200)
        target = tuple(float(v) for v in args.target.split(","))

    im = render_parts(scene["parts"], eye, target, args.fov, w, h, args.ss, args.night, not args.noshadow)
    im.save(args.out)
    print(f"wrote {args.out}")


if __name__ == "__main__":
    main()
