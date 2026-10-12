#!/usr/bin/env python3
"""Renders GUI trees exported by export_ui.luau into PNG screenshots.

It follows Roblox's GUI rules closely enough to judge layout, spacing, overlap
and style at different screen sizes: UDim2 + AnchorPoint layout, UIScale,
UIPadding, UIListLayout, UIGridLayout, size/aspect/text-size constraints,
UICorner, UIStroke, UIGradient, UIShadow, TextScaled fitting with the real
fonts, emoji, ScrollingFrame clipping, CanvasGroup and ViewportFrames (drawn
with render3d). It also draws the Roblox top bar and, on touch screens, the
jump button and thumbstick area, to show what they cover.

Fonts: Fredoka One and Luckiest Guy come from Google Fonts (put the .ttf files
in --fonts); Gotham / Builder Sans / Source Sans are approximated with Inter.

Usage:
    python3 render_ui.py ui_hud_phone.json out.png [--fonts DIR] [--background bg.png]
    python3 render_ui.py --all DIR [--scene scene.json]   # every ui_*.json in DIR
"""

from __future__ import annotations

import argparse
import glob
import html
import json
import math
import os
import re
import sys
from functools import lru_cache

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import render3d  # noqa: E402

SS = 2  # supersampling factor
TOP_INSET = 58  # Roblox top bar height
INTER = "/usr/share/fonts/opentype/inter"
DEJAVU = "/usr/share/fonts/truetype/dejavu"
EMOJI = "/usr/share/fonts/truetype/noto/NotoColorEmoji.ttf"
TEXT_CLASSES = ("TextLabel", "TextButton", "TextBox")

FONT_DIR = os.environ.get("PREVIEW_FONTS", os.path.join(os.path.dirname(os.path.abspath(__file__)), "fonts"))


# --------------------------------------------------------------------------- fonts


def font_path(name: str) -> str:
    inter = {
        "GothamBlack": "Inter-Black.otf",
        "GothamBold": "Inter-Bold.otf",
        "GothamSemibold": "Inter-SemiBold.otf",
        "GothamMedium": "Inter-Medium.otf",
        "Gotham": "Inter-Medium.otf",
        "BuilderSansExtraBold": "Inter-ExtraBold.otf",
        "BuilderSansBold": "Inter-Bold.otf",
        "BuilderSansMedium": "Inter-Medium.otf",
        "BuilderSans": "Inter-Regular.otf",
        "SourceSansBold": "Inter-Bold.otf",
        "SourceSansSemibold": "Inter-SemiBold.otf",
        "SourceSans": "Inter-Regular.otf",
        "Arial": "Inter-Regular.otf",
        "ArialBold": "Inter-Bold.otf",
    }
    google = {
        "FredokaOne": "FredokaOne-Regular.ttf",
        "Cartoon": "FredokaOne-Regular.ttf",
        "LuckiestGuy": "LuckiestGuy-Regular.ttf",
    }
    if name in google:
        path = os.path.join(FONT_DIR, google[name])
        variable = os.path.join(FONT_DIR, "Fredoka[wdth,wght].ttf")
        if google[name].startswith("Fredoka") and not is_font(path) and os.path.exists(variable):
            # Fredoka One is the variable Fredoka family at SemiBold weight.
            return variable + "#600,100"
    else:
        path = os.path.join(INTER, inter.get(name, "Inter-Regular.otf"))
    if not is_font(path):
        path = os.path.join(DEJAVU, "DejaVuSans-Bold.ttf")
    return path


def is_font(path: str) -> bool:
    try:
        with open(path, "rb") as f:
            magic = f.read(4)
    except OSError:
        return False
    return magic in (b"\x00\x01\x00\x00", b"OTTO", b"true", b"ttcf")


@lru_cache(maxsize=None)
def load_font(spec: str, size: int) -> ImageFont.FreeTypeFont:
    """`spec` is a font path, optionally followed by '#axis,values' for variable fonts."""
    path, _, axes = spec.partition("#")
    font = ImageFont.truetype(path, max(1, size))
    if axes:
        font.set_variation_by_axes([float(v) for v in axes.split(",")])
    return font


@lru_cache(maxsize=None)
def line_ratio(path: str) -> float:
    """PIL font size per pixel of Roblox TextSize (TextSize is the line height)."""
    f = load_font(path, 200)
    ascent, descent = f.getmetrics()
    return 200 / (ascent + descent)


@lru_cache(maxsize=None)
def _glyph_render(path: str, ch: str) -> bytes:
    size = 109 if path == EMOJI else 48
    f = load_font(path, size)
    im = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((4, 4), ch, font=f, fill=(255, 255, 255, 255), embedded_color=(path == EMOJI))
    return im.tobytes()


@lru_cache(maxsize=None)
def has_glyph(path: str, ch: str) -> bool:
    try:
        return _glyph_render(path, ch) != _glyph_render(path, "\U0010fffd")
    except Exception:
        return False


def is_emojiish(ch: str) -> bool:
    o = ord(ch)
    return o >= 0x1F000 or 0x2300 <= o <= 0x23FF or 0x2600 <= o <= 0x27BF or 0x2B00 <= o <= 0x2BFF or o in (0x2122, 0x2139)


@lru_cache(maxsize=None)
def emoji_image(ch: str, px: int) -> Image.Image:
    f = load_font(EMOJI, 109)
    im = Image.new("RGBA", (160, 160), (0, 0, 0, 0))
    ImageDraw.Draw(im).text((10, 10), ch, font=f, embedded_color=True)
    box = im.getbbox() or (0, 0, 1, 1)
    im = im.crop(box)
    scale = px / max(im.width, im.height)
    return im.resize((max(1, round(im.width * scale)), max(1, round(im.height * scale))), Image.LANCZOS)


# ------------------------------------------------------------------------ text layout


class Run:
    __slots__ = ("kind", "path", "text")

    def __init__(self, kind: str, path: str, text: str):
        self.kind = kind  # "font" or "emoji"
        self.path = path
        self.text = text


def split_runs(text: str, main: str) -> list[Run]:
    runs: list[Run] = []
    fallback = os.path.join(DEJAVU, "DejaVuSans-Bold.ttf")
    for ch in text:
        if ch in ("️", "‍", "︎"):
            continue
        if ch == " ":
            kind, path = "font", main
        elif ord(ch) >= 0x1F000 and has_glyph(EMOJI, ch):
            kind, path = "emoji", EMOJI
        elif has_glyph(main, ch):
            kind, path = "font", main
        elif is_emojiish(ch) and has_glyph(EMOJI, ch):
            kind, path = "emoji", EMOJI
        else:
            kind, path = "font", fallback
        if runs and runs[-1].kind == kind and runs[-1].path == path:
            runs[-1].text += ch
        else:
            runs.append(Run(kind, path, ch))
    return runs


def emoji_size(size: float) -> int:
    return max(1, round(size * 0.9))


@lru_cache(maxsize=200000)
def measure(text: str, main: str, size: float) -> float:
    width = 0.0
    for run in split_runs(text, main):
        if run.kind == "emoji":
            width += len(run.text) * emoji_size(size) * 1.08
        else:
            f = load_font(run.path, round(size * line_ratio(run.path)))
            width += f.getlength(run.text)
    return width


def wrap_lines(text: str, main: str, size: float, max_width: float | None) -> list[str]:
    lines: list[str] = []
    for para in text.split("\n"):
        if max_width is None:
            lines.append(para)
            continue
        current = ""
        for word in para.split(" "):
            candidate = word if current == "" else current + " " + word
            if current == "" or measure(candidate, main, size) <= max_width + 0.5:
                current = candidate
            else:
                lines.append(current)
                current = word
        lines.append(current)
    return lines


def fits(text: str, main: str, size: float, width: float, height: float, line_height: float) -> bool:
    lines = wrap_lines(text, main, size, width)
    if len(lines) * size * line_height > height + 0.5:
        return False
    return all(measure(line, main, size) <= width + 0.5 for line in lines)


def plain_text(node: dict) -> str:
    text = node.get("Text", "") or ""
    if node.get("RichText"):
        text = re.sub(r"<br\s*/?>", "\n", text)
        text = re.sub(r"<[^>]+>", "", text)
        text = html.unescape(text)
    return text


# ------------------------------------------------------------------------- helpers


def rgb255(c) -> tuple[int, int, int]:
    return tuple(int(round(max(0.0, min(1.0, v)) * 255)) for v in c)  # type: ignore[return-value]


@lru_cache(maxsize=4096)
def rounded_mask(w: int, h: int, r: float) -> Image.Image:
    """Antialiased rounded-rectangle mask (L mode)."""
    w, h = max(1, w), max(1, h)
    r = max(0.0, min(r, min(w, h) / 2))
    if r < 0.5:
        return Image.new("L", (w, h), 255)
    # Signed distance to the rounded rectangle gives exact antialiasing.
    xs = np.abs(np.arange(w) + 0.5 - w / 2)[None, :]
    ys = np.abs(np.arange(h) + 0.5 - h / 2)[:, None]
    qx = xs - (w / 2 - r)
    qy = ys - (h / 2 - r)
    outside = np.hypot(np.maximum(qx, 0), np.maximum(qy, 0))
    inside = np.minimum(np.maximum(qx, qy), 0)
    dist = outside + inside - r
    alpha = np.clip(0.5 - dist, 0, 1)
    return Image.fromarray((alpha * 255 + 0.5).astype(np.uint8), "L")


def interpolate(keys: list, t: np.ndarray, channels: int) -> np.ndarray:
    times = np.array([k[0] for k in keys])
    values = np.array([k[1 : 1 + channels] for k in keys], dtype=np.float64)
    out = np.empty(t.shape + (channels,))
    for c in range(channels):
        out[..., c] = np.interp(t, times, values[:, c])
    return out


def gradient_fields(w: int, h: int, grad: dict, ox: float = 0, oy: float = 0, rw: float | None = None, rh: float | None = None):
    """Colour (h,w,3) and opacity (h,w) of a UIGradient over a w*h area.

    (ox, oy, rw, rh) place the gradient's element rect inside the area, for layers
    with margins (text, strokes)."""
    rw = rw or w
    rh = rh or h
    ys, xs = np.mgrid[0:h, 0:w].astype(np.float64)
    u = (xs + 0.5 - ox) / max(rw, 1) - 0.5 - grad["offset"][0]
    v = (ys + 0.5 - oy) / max(rh, 1) - 0.5 - grad["offset"][1]
    a = math.radians(grad.get("rotation", 0))
    t = np.clip(0.5 + u * math.cos(a) + v * math.sin(a), 0, 1)
    color = interpolate(grad["colors"], t, 3)
    trans = interpolate(grad["transparency"], t, 1)[..., 0]
    return color, 1 - trans


def colored(mask: Image.Image, color, opacity: float, grad: dict | None = None, place=None) -> Image.Image:
    """RGBA layer: `mask` filled with `color` (times an optional gradient)."""
    if not grad:
        layer = Image.new("RGBA", mask.size, rgb255(color) + (0,))
        if opacity >= 0.999:
            layer.putalpha(mask)
        else:
            layer.putalpha(mask.point(lambda v: int(v * max(0.0, opacity) + 0.5)))
        return layer
    w, h = mask.size
    m = np.asarray(mask, dtype=np.float64) / 255.0
    if grad:
        g, gop = gradient_fields(w, h, grad, *(place or (0, 0, None, None)))
        rgb = g * np.array(color)[None, None, :]
        alpha = m * gop * opacity
    else:
        rgb = np.broadcast_to(np.array(color, dtype=np.float64), (h, w, 3))
        alpha = m * opacity
    arr = np.concatenate([np.clip(rgb, 0, 1), np.clip(alpha, 0, 1)[..., None]], axis=2)
    return Image.fromarray((arr * 255 + 0.5).astype(np.uint8), "RGBA")


def composite(canvas: Image.Image, layer: Image.Image, x: int, y: int, clip):
    cx0, cy0, cx1, cy1 = clip
    x0, y0 = max(x, cx0, 0), max(y, cy0, 0)
    x1 = min(x + layer.width, cx1, canvas.width)
    y1 = min(y + layer.height, cy1, canvas.height)
    if x1 <= x0 or y1 <= y0:
        return
    canvas.alpha_composite(layer, dest=(x0, y0), source=(x0 - x, y0 - y, x1 - x, y1 - y))


def intersect(a, b):
    return (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))


def enabled_modifier(mods: dict, name: str):
    m = mods.get(name)
    if m is None or m.get("enabled") is False:
        return None
    return m


# -------------------------------------------------------------------------- layout


def measure_size(node: dict, pw: float, ph: float, cs: float) -> tuple[float, float]:
    s = node.get("size", [0, 0, 0, 0])
    w = pw * s[0] + s[1] * cs
    h = ph * s[2] + s[3] * cs
    mods = node.get("modifiers", {})
    sc = mods.get("UISizeConstraint")
    if sc:
        w = min(max(w, sc["min"][0] * cs), sc["max"][0] * cs)
        h = min(max(h, sc["min"][1] * cs), sc["max"][1] * cs)
    ar = mods.get("UIAspectRatioConstraint")
    if ar and ar["ratio"] > 0 and w > 0 and h > 0:
        ratio = ar["ratio"]
        if ar.get("type") == "ScaleWithParentSize":
            if ar.get("axis") == "Height":
                w = h * ratio
            else:
                h = w / ratio
        elif w / h > ratio:
            w = h * ratio
        else:
            h = w / ratio
    return max(0.0, w), max(0.0, h)


def own_scale(node: dict) -> float:
    m = node.get("modifiers", {}).get("UIScale")
    return float(m["scale"]) if m else 1.0


def content_area(node: dict, rect, cs: float):
    x, y, w, h = rect
    pad = node.get("modifiers", {}).get("UIPadding")
    if pad:
        left = pad["left"][0] * w + pad["left"][1] * cs
        right = pad["right"][0] * w + pad["right"][1] * cs
        top = pad["top"][0] * h + pad["top"][1] * cs
        bottom = pad["bottom"][0] * h + pad["bottom"][1] * cs
        x, y, w, h = x + left, y + top, w - left - right, h - top - bottom
    return x, y, max(0.0, w), max(0.0, h)


def sort_children(kids: list[dict], sort: str | None) -> list[dict]:
    if sort == "Name":
        return sorted(kids, key=lambda k: k["name"])
    if sort == "LayoutOrder":
        return sorted(kids, key=lambda k: k.get("LayoutOrder", 0))
    return kids


def align_offset(free: float, how: str | None, start: str, mid: str, end: str) -> float:
    if how == mid:
        return free / 2
    if how == end:
        return free
    return 0.0


def place(kid: dict, x: float, y: float, w: float, h: float, cs: float):
    kid["_rect"] = (x, y, w, h)
    kid["_cs"] = cs


def layout(node: dict, rect, cs: float):
    """Assigns `_rect` (x, y, w, h in canvas pixels) and `_cs` (pixel scale) to the subtree."""
    node["_rect"] = rect
    node["_cs"] = cs
    kids = [k for k in node.get("children", []) if k.get("Visible", True)]
    if not kids:
        return
    x, y, w, h = rect
    if node.get("class") != "ScrollingFrame":
        place_children(node, kids, rect, cs)
    else:
        # Children live on the canvas, which is at least the window size and,
        # with AutomaticCanvasSize, grows to fit the content.
        canvas = node.get("canvasSize", [0, 0, 0, 0])
        cw = max(w, w * canvas[0] + canvas[1] * cs)
        ch = max(h, h * canvas[2] + canvas[3] * cs)
        place_children(node, kids, (x, y, cw, ch), cs)
        auto = node.get("automaticCanvas") or "None"
        if auto != "None":
            pad = node.get("modifiers", {}).get("UIPadding")
            px = (pad["left"][1] + pad["right"][1]) * cs if pad else 0.0
            py = (pad["top"][1] + pad["bottom"][1]) * cs if pad else 0.0
            need_w = max(k["_rect"][0] + k["_rect"][2] for k in kids) - min(k["_rect"][0] for k in kids) + px
            need_h = max(k["_rect"][1] + k["_rect"][3] for k in kids) - min(k["_rect"][1] for k in kids) + py
            grow_w = "X" in auto and need_w > cw + 0.5
            grow_h = "Y" in auto and need_h > ch + 0.5
            if grow_w or grow_h:
                cw = need_w if grow_w else cw
                ch = need_h if grow_h else ch
                place_children(node, kids, (x, y, cw, ch), cs)
        node["_canvas"] = (cw, ch)
    for kid in kids:
        layout(kid, kid["_rect"], kid["_cs"])


def place_children(node: dict, kids: list[dict], rect, cs: float):
    mods = node.get("modifiers", {})
    cx, cy, cw, ch = content_area(node, rect, cs)

    sizes = {}
    for kid in kids:
        kw, kh = measure_size(kid, cw, ch, cs)
        s = own_scale(kid)
        sizes[id(kid)] = (kw * s, kh * s, s)

    grid = mods.get("UIGridLayout")
    lst = mods.get("UIListLayout")
    if grid:
        ordered = sort_children(kids, grid.get("sort"))
        cell = grid["cellSize"]
        pad = grid["cellPadding"]
        gw = cw * cell[0] + cell[1] * cs
        gh = ch * cell[2] + cell[3] * cs
        px = cw * pad[0] + pad[1] * cs
        py = ch * pad[2] + pad[3] * cs
        n = len(ordered)
        horizontal = grid.get("direction", "Horizontal") == "Horizontal"
        span = cw if horizontal else ch
        step = (gw + px) if horizontal else (gh + py)
        per = int(grid.get("maxCells") or 0)
        fit = max(1, int((span + (px if horizontal else py) + 0.01) // max(step, 1e-6)))
        per = min(per, fit) if per > 0 else fit
        per = max(1, min(per, n))
        lines = math.ceil(n / per)
        cols, rows = (per, lines) if horizontal else (lines, per)
        total_w = cols * gw + (cols - 1) * px
        total_h = rows * gh + (rows - 1) * py
        x0 = cx + align_offset(cw - total_w, grid.get("halign"), "Left", "Center", "Right")
        y0 = cy + align_offset(ch - total_h, grid.get("valign"), "Top", "Center", "Bottom")
        for i, kid in enumerate(ordered):
            col, row = (i % per, i // per) if horizontal else (i // per, i % per)
            s = sizes[id(kid)][2]
            place(kid, x0 + col * (gw + px), y0 + row * (gh + py), gw * s, gh * s, cs * s)
    elif lst:
        ordered = sort_children(kids, lst.get("sort"))
        vertical = lst.get("direction", "Vertical") == "Vertical"
        gap = (lst["padding"][0] * (ch if vertical else cw)) + lst["padding"][1] * cs
        if vertical:
            total = sum(sizes[id(k)][1] for k in ordered) + gap * (len(ordered) - 1)
            yy = cy + align_offset(ch - total, lst.get("valign"), "Top", "Center", "Bottom")
            for kid in ordered:
                kw, kh, s = sizes[id(kid)]
                xx = cx + align_offset(cw - kw, lst.get("halign"), "Left", "Center", "Right")
                place(kid, xx, yy, kw, kh, cs * s)
                yy += kh + gap
        else:
            rows: list[list[dict]] = [[]]
            used = 0.0
            for kid in ordered:
                kw = sizes[id(kid)][0]
                if lst.get("wraps") and rows[-1] and used + gap + kw > cw + 0.5:
                    rows.append([])
                    used = 0.0
                used += kw if not rows[-1] else gap + kw
                rows[-1].append(kid)
            heights = [max(sizes[id(k)][1] for k in row) for row in rows]
            total_h = sum(heights) + gap * (len(rows) - 1)
            yy = cy + align_offset(ch - total_h, lst.get("valign"), "Top", "Center", "Bottom")
            for row, rh in zip(rows, heights):
                total = sum(sizes[id(k)][0] for k in row) + gap * (len(row) - 1)
                xx = cx + align_offset(cw - total, lst.get("halign"), "Left", "Center", "Right")
                for kid in row:
                    kw, kh, s = sizes[id(kid)]
                    ky = yy + align_offset(rh - kh, lst.get("valign"), "Top", "Center", "Bottom")
                    place(kid, xx, ky, kw, kh, cs * s)
                    xx += kw + gap
                yy += rh + gap
    else:
        for kid in kids:
            kw, kh, s = sizes[id(kid)]
            p = kid.get("position", [0, 0, 0, 0])
            a = kid.get("anchor", [0, 0])
            ax = cx + cw * p[0] + p[1] * cs
            ay = cy + ch * p[2] + p[3] * cs
            place(kid, ax - a[0] * kw, ay - a[1] * kh, kw, kh, cs * s)


def content_extent(node: dict) -> float:
    """Bottom of the lowest visible child (for scrollbars)."""
    bottom = 0.0
    for kid in node.get("children", []):
        if kid.get("Visible", True) and "_rect" in kid:
            r = kid["_rect"]
            bottom = max(bottom, r[1] + r[3])
    pad = node.get("modifiers", {}).get("UIPadding")
    if pad:
        bottom += pad["bottom"][1] * node["_cs"]
    return bottom


# ------------------------------------------------------------------------- drawing


class Renderer:
    def __init__(self, data: dict, background: Image.Image | None):
        self.vw, self.vh = data["viewport"]
        self.touch = bool(data.get("touch"))
        self.data = data
        self.W, self.H = self.vw * SS, self.vh * SS
        if background is not None:
            bg = background.convert("RGBA").resize((self.W, self.H), Image.LANCZOS)
        else:
            bg = self.default_background()
        self.canvas = bg

    def default_background(self) -> Image.Image:
        ys = np.linspace(0, 1, self.H)[:, None, None]
        sky = np.array([0.55, 0.78, 0.98]) * (1 - ys) + np.array([0.80, 0.92, 1.0]) * ys
        grass = np.array([0.45, 0.75, 0.35])
        img = np.where(ys > 0.55, grass, sky)
        img = np.broadcast_to(img, (self.H, self.W, 3))
        alpha = np.ones((self.H, self.W, 1))
        return Image.fromarray((np.concatenate([img, alpha], axis=2) * 255).astype(np.uint8), "RGBA")

    # ----- screens

    def render(self) -> Image.Image:
        for screen in self.data["screens"]:
            if screen.get("enabled") is False:
                continue
            scale = screen.get("modifiers", {}).get("UIScale", {}).get("scale", 1.0)
            inset = 0 if screen.get("ignoreGuiInset") else TOP_INSET * SS
            rect = (0.0, float(inset), float(self.W), float(self.H - inset))
            layout(screen, rect, SS * scale)
            full = (0, 0, self.W, self.H)
            for kid in self.ordered(screen):
                self.draw(kid, self.canvas, full)
        self.draw_system_ui()
        return self.canvas.resize((self.vw, self.vh), Image.LANCZOS)

    @staticmethod
    def ordered(node: dict) -> list[dict]:
        kids = [k for k in node.get("children", []) if k.get("Visible", True)]
        return sorted(kids, key=lambda k: k.get("ZIndex", 1))  # stable: insertion order breaks ties

    def draw(self, node: dict, canvas: Image.Image, clip):
        rotation = float(node.get("Rotation", 0) or 0)
        group = node.get("class") == "CanvasGroup"
        if abs(rotation) > 0.01 or group:
            layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
            self.draw_tree(node, layer, (0, 0, layer.width, layer.height))
            if group:
                gt = float(node.get("GroupTransparency", 0) or 0)
                if gt > 0:
                    a = layer.getchannel("A").point(lambda v: int(v * (1 - gt)))
                    layer.putalpha(a)
            if abs(rotation) > 0.01:
                x, y, w, h = node["_rect"]
                layer = layer.rotate(-rotation, center=(x + w / 2, y + h / 2), resample=Image.BICUBIC)
            composite(canvas, layer, 0, 0, clip)
            return
        self.draw_tree(node, canvas, clip)

    def draw_tree(self, node: dict, canvas: Image.Image, clip):
        self.draw_self(node, canvas, clip)
        x, y, w, h = node["_rect"]
        child_clip = clip
        if node.get("class") == "ScrollingFrame" or node.get("ClipsDescendants"):
            child_clip = intersect(clip, (int(round(x)), int(round(y)), int(round(x + w)), int(round(y + h))))
        for kid in self.ordered(node):
            self.draw(kid, canvas, child_clip)
        if node.get("class") == "ScrollingFrame":
            self.draw_scrollbar(node, canvas, clip)

    def draw_scrollbar(self, node: dict, canvas: Image.Image, clip):
        x, y, w, h = node["_rect"]
        extent = max(content_extent(node) - y, node.get("_canvas", (w, h))[1])
        if extent <= h + 1:
            return
        cs = node["_cs"]
        thickness = max(2, int(round((node.get("ScrollBarThickness") or 12) * cs)))
        length = max(thickness * 2, int(h * h / extent))
        layer = colored(rounded_mask(thickness, length, thickness / 2), (0.1, 0.1, 0.12), 0.55)
        composite(canvas, layer, int(round(x + w - thickness)), int(round(y)), clip)

    def draw_self(self, node: dict, canvas: Image.Image, clip):
        x, y, w, h = node["_rect"]
        cs = node["_cs"]
        ix, iy = int(round(x)), int(round(y))
        iw, ih = int(round(x + w)) - ix, int(round(y + h)) - iy
        if iw <= 0 or ih <= 0:
            return
        mods = node.get("modifiers", {})
        corner = mods.get("UICorner")
        radius = 0.0
        if corner:
            radius = min(iw, ih) * corner["radius"][0] + corner["radius"][1] * cs
            radius = max(0.0, min(radius, min(iw, ih) / 2))
        grad = enabled_modifier(mods, "UIGradient")
        is_text = node.get("class") in TEXT_CLASSES
        bg_t = float(node.get("BackgroundTransparency", 0))

        shadow = enabled_modifier(mods, "UIShadow")
        if shadow and shadow.get("transparency", 0) < 1:
            self.draw_shadow(canvas, clip, shadow, ix, iy, iw, ih, radius, cs)

        if bg_t < 1:
            if radius < 0.5 and not grad:
                # Plain rectangles (like a full-screen dimmer) only need their visible part.
                vx0, vy0 = max(ix, clip[0], 0), max(iy, clip[1], 0)
                vx1, vy1 = min(ix + iw, clip[2], canvas.width), min(iy + ih, clip[3], canvas.height)
                if vx1 > vx0 and vy1 > vy0:
                    layer = colored(rounded_mask(vx1 - vx0, vy1 - vy0, 0), node.get("background", [1, 1, 1]), 1 - bg_t)
                    composite(canvas, layer, vx0, vy0, clip)
            else:
                mask = rounded_mask(iw, ih, radius)
                layer = colored(mask, node.get("background", [1, 1, 1]), 1 - bg_t, grad)
                composite(canvas, layer, ix, iy, clip)
            border = int(node.get("BorderSizePixel", 0) or 0)
            if border > 0 and not corner and node.get("class") != "ViewportFrame":
                b = max(1, int(round(border * cs)))
                ring = Image.new("L", (iw + 2 * b, ih + 2 * b), 255)
                ring.paste(0, (b, b, b + iw, b + ih))
                composite(canvas, colored(ring, node.get("border", [0.1, 0.16, 0.2]), 1 - bg_t), ix - b, iy - b, clip)

        stroke = enabled_modifier(mods, "UIStroke")
        if stroke and (not is_text or stroke.get("mode") == "Border") and stroke.get("transparency", 0) < 1:
            t = max(1, int(round(stroke["thickness"] * cs)))
            outer = rounded_mask(iw + 2 * t, ih + 2 * t, radius + t)
            inner = rounded_mask(iw, ih, radius)
            ring_arr = np.asarray(outer, dtype=np.int16).copy()
            ring_arr[t : t + ih, t : t + iw] -= np.asarray(inner, dtype=np.int16)
            ring = Image.fromarray(np.clip(ring_arr, 0, 255).astype(np.uint8), "L")
            layer = colored(ring, stroke["color"], 1 - stroke["transparency"], stroke.get("gradient"), (t, t, iw, ih))
            composite(canvas, layer, ix - t, iy - t, clip)

        if node.get("class") == "ViewportFrame":
            self.draw_viewport(node, canvas, clip, ix, iy, iw, ih)

        if is_text and plain_text(node).strip():
            self.draw_text(node, canvas, clip, ix, iy, iw, ih, cs, grad, stroke if stroke and stroke.get("mode") != "Border" else None)

        if node.get("Image") and node.get("class") in ("ImageLabel", "ImageButton"):
            # Asset images can't be fetched offline; show where they are.
            layer = colored(rounded_mask(iw, ih, radius), (1.0, 0.3, 0.8), 0.35 * (1 - float(node.get("ImageTransparency", 0))))
            composite(canvas, layer, ix, iy, clip)

    def draw_shadow(self, canvas, clip, shadow, ix, iy, iw, ih, radius, cs):
        off = shadow.get("offset", [0, 0, 0, 0])
        spread = shadow.get("spread", [0, 0, 0, 0])
        blur = shadow.get("blur", [0, 0])
        sw = iw + iw * spread[0] + spread[1] * cs
        sh = ih + ih * spread[2] + spread[3] * cs
        sx = ix + iw * off[0] + off[1] * cs - (sw - iw) / 2
        sy = iy + ih * off[2] + off[3] * cs - (sh - ih) / 2
        b = min(iw, ih) * blur[0] + blur[1] * cs
        margin = int(math.ceil(b * 1.5)) + 2
        sw_i, sh_i = max(1, int(round(sw))), max(1, int(round(sh)))
        mask = Image.new("L", (sw_i + 2 * margin, sh_i + 2 * margin), 0)
        mask.paste(rounded_mask(sw_i, sh_i, radius + (sw_i - iw) / 2), (margin, margin))
        if b > 0.5:
            mask = mask.filter(ImageFilter.GaussianBlur(b / 2))
        layer = colored(mask, shadow["color"], 1 - shadow.get("transparency", 0))
        composite(canvas, layer, int(round(sx)) - margin, int(round(sy)) - margin, clip)

    def draw_viewport(self, node, canvas, clip, ix, iy, iw, ih):
        cam = node.get("camera")
        parts = node.get("parts") or []
        if not cam or not parts:
            return
        cf = cam["cf"]
        eye = np.array(cf[0:3])
        rot = np.array(cf[3:12]).reshape(3, 3)
        look = -rot[:, 2]
        lighting = render3d.viewport_lighting(
            [c for c in node.get("ambient", [0.75, 0.75, 0.78])],
            node.get("lightColor", [1, 1, 1]),
            node.get("lightDirection", [-1, -1, -1]),
        )
        try:
            img = render3d.render_rgba(parts, eye, eye + look, cam["fov"], iw, ih, lighting, ss=2)
        except Exception as exc:  # keep going; a broken preview shows as empty
            print(f"warning: viewport {node['name']} failed: {exc}")
            return
        tint = node.get("imageColor", [1, 1, 1])
        if tint != [1, 1, 1]:
            arr = np.asarray(img, dtype=np.float64)
            arr[..., :3] *= np.array(tint)[None, None, :]
            img = Image.fromarray(arr.astype(np.uint8), "RGBA")
        composite(canvas, img, ix, iy, clip)

    def draw_text(self, node, canvas, clip, ix, iy, iw, ih, cs, grad, ui_stroke):
        text = plain_text(node)
        main = font_path(node.get("font", "SourceSans"))
        line_height = float(node.get("LineHeight", 1) or 1)
        # UIPadding insets the text too.
        bx, by, bw, bh = content_area(node, (float(ix), float(iy), float(iw), float(ih)), cs)
        if node.get("TextScaled"):
            tsc = node.get("modifiers", {}).get("UITextSizeConstraint")
            hi = 100 * cs
            lo = 1.0
            if tsc:
                hi = min(hi, tsc["max"] * cs)
                lo = max(lo, tsc["min"] * cs)
            size = lo
            a, b = int(lo), int(hi)
            while a <= b:
                mid = (a + b) // 2
                if fits(text, main, mid, bw, bh, line_height):
                    size = max(size, mid)
                    a = mid + 1
                else:
                    b = mid - 1
            wrap_width: float | None = bw
        else:
            size = float(node.get("TextSize", 14)) * cs
            wrap_width = bw if node.get("TextWrapped") else None
        size = max(1.0, size)
        lines = wrap_lines(text, main, size, wrap_width)
        block = len(lines) * size * line_height
        yalign = node.get("yalign", "Center")
        top = by + align_offset(bh - block, yalign, "Top", "Center", "Bottom")

        stroke_w = 0
        stroke_color = None
        stroke_opacity = 0.0
        if ui_stroke and ui_stroke.get("transparency", 0) < 1:
            stroke_w = max(1, int(round(ui_stroke["thickness"] * cs)))
            stroke_color = ui_stroke["color"]
            stroke_opacity = 1 - ui_stroke["transparency"]
        elif float(node.get("TextStrokeTransparency", 1)) < 1:
            stroke_w = max(1, int(round(SS * 1.0)))
            stroke_color = node.get("textStrokeColor", [0, 0, 0])
            stroke_opacity = 1 - float(node["TextStrokeTransparency"])

        margin = int(size) + stroke_w + 4
        lw, lh = iw + 2 * margin, ih + 2 * margin
        fill_mask = Image.new("L", (lw, lh), 0)
        stroke_mask = Image.new("L", (lw, lh), 0)
        emoji_layer = Image.new("RGBA", (lw, lh), (0, 0, 0, 0))
        fd = ImageDraw.Draw(fill_mask)
        sd = ImageDraw.Draw(stroke_mask)
        xalign = node.get("xalign", "Center")
        for i, line in enumerate(lines):
            width = measure(line, main, size)
            lx = bx + align_offset(bw - width, xalign, "Left", "Center", "Right") - ix + margin
            ly = top + i * size * line_height - iy + margin
            cursor = lx
            for run in split_runs(line, main):
                if run.kind == "emoji":
                    e = emoji_size(size)
                    for ch in run.text:
                        im = emoji_image(ch, e)
                        ex = int(round(cursor + (e * 1.08 - im.width) / 2))
                        ey = int(round(ly + (size - im.height) / 2))
                        emoji_layer.alpha_composite(im, dest=(max(0, ex), max(0, ey)))
                        cursor += e * 1.08
                    continue
                f = load_font(run.path, round(size * line_ratio(run.path)))
                ascent, _ = f.getmetrics()
                baseline = ly + ascent
                if stroke_w:
                    sd.text((cursor, baseline), run.text, font=f, fill=255, anchor="ls", stroke_width=stroke_w, stroke_fill=255)
                fd.text((cursor, baseline), run.text, font=f, fill=255, anchor="ls")
                cursor += f.getlength(run.text)

        opacity = 1 - float(node.get("TextTransparency", 0))
        place_rect = (margin, margin, iw, ih)
        if stroke_w and stroke_color is not None:
            layer = colored(stroke_mask, stroke_color, stroke_opacity * opacity, ui_stroke.get("gradient") if ui_stroke else None, place_rect)
            composite(canvas, layer, ix - margin, iy - margin, clip)
        layer = colored(fill_mask, node.get("textColor", [0, 0, 0]), opacity, grad, place_rect)
        composite(canvas, layer, ix - margin, iy - margin, clip)
        if emoji_layer.getbbox():
            if opacity < 1:
                emoji_layer.putalpha(emoji_layer.getchannel("A").point(lambda v: int(v * opacity)))
            composite(canvas, emoji_layer, ix - margin, iy - margin, clip)

    # ----- Roblox's own UI on top

    def draw_system_ui(self):
        full = (0, 0, self.W, self.H)
        dark = (0.07, 0.07, 0.09)
        # top bar: menu button + chat/unibar pill
        d = 44 * SS
        composite(self.canvas, colored(rounded_mask(d, d, d / 2), dark, 0.7), 12 * SS, 7 * SS, full)
        composite(self.canvas, colored(rounded_mask(96 * SS, d, d / 2), dark, 0.7), 64 * SS, 7 * SS, full)
        for k in range(2):
            dot = 18 * SS
            composite(self.canvas, colored(rounded_mask(dot, dot, dot / 2), (1, 1, 1), 0.9), (76 + k * 44) * SS, 20 * SS, full)
        dot = 18 * SS
        composite(self.canvas, colored(rounded_mask(dot, dot, 4 * SS), (1, 1, 1), 0.9), 25 * SS, 20 * SS, full)
        if not self.touch:
            return
        small = min(self.vw, self.vh) <= 500
        if small:
            size, jx, jy = 70, self.vw - 95, self.vh - 90
            stick, sx, sy = 120, 40, self.vh - 150
        else:
            size, jx, jy = 120, self.vw - 170, self.vh - 210
            stick, sx, sy = 160, 60, self.vh - 230
        s = size * SS
        composite(self.canvas, colored(rounded_mask(s, s, s / 2), (0.1, 0.1, 0.12), 0.45), jx * SS, jy * SS, full)
        ring = rounded_mask(s, s, s / 2)
        inner = rounded_mask(s - 6 * SS, s - 6 * SS, (s - 6 * SS) / 2)
        ring_arr = np.asarray(ring, dtype=np.int16).copy()
        ring_arr[3 * SS : 3 * SS + inner.height, 3 * SS : 3 * SS + inner.width] -= np.asarray(inner, dtype=np.int16)
        ring_img = Image.fromarray(np.clip(ring_arr, 0, 255).astype(np.uint8), "L")
        composite(self.canvas, colored(ring_img, (1, 1, 1), 0.7), jx * SS, jy * SS, full)
        t = stick * SS
        composite(self.canvas, colored(rounded_mask(t, t, t / 2), (1, 1, 1), 0.12), sx * SS, sy * SS, full)


# ------------------------------------------------------------------------- driver


def background_for(scene_path: str | None, width: int, height: int, cache_dir: str) -> Image.Image | None:
    """A real game view behind the UI: the player's nest seen from outside the gate."""
    if not scene_path:
        return None
    path = os.path.join(cache_dir, f"bg_{width}x{height}.png")
    if os.path.exists(path) and os.path.getmtime(path) >= os.path.getmtime(scene_path):
        return Image.open(path)
    scene = json.load(open(scene_path))
    eye, target = render3d.plot_view(scene, 1, 34, 16, 3)
    img = render3d.render_parts(scene["parts"], eye, target, 70, width, height, ss=1)
    img.save(path)
    return img


def render_file(path: str, out: str, scene: str | None = None):
    data = json.load(open(path))
    w, h = data["viewport"]
    bg = background_for(scene, w, h, os.path.dirname(out) or ".")
    img = Renderer(data, bg).render()
    img.save(out)
    return img


def main():
    global FONT_DIR
    ap = argparse.ArgumentParser()
    ap.add_argument("input", nargs="?")
    ap.add_argument("out", nargs="?")
    ap.add_argument("--all", dest="all_dir")
    ap.add_argument("--only", default=None, help="comma-separated scene names for --all")
    ap.add_argument("--scene", default=None, help="scene.json to render a game background")
    ap.add_argument("--fonts", default=None)
    args = ap.parse_args()
    if args.fonts:
        FONT_DIR = args.fonts
    if args.all_dir:
        only = set(args.only.split(",")) if args.only else None
        files = sorted(glob.glob(os.path.join(args.all_dir, "ui_*.json")))
        for f in files:
            name = os.path.basename(f)[3:-5]
            scene_name = name.rsplit("_", 1)[0]
            if only and scene_name not in only:
                continue
            out = os.path.join(args.all_dir, f"ui_{name}.png")
            render_file(f, out, args.scene)
            print("rendered", out)
        return
    render_file(args.input, args.out, args.scene)


if __name__ == "__main__":
    main()
