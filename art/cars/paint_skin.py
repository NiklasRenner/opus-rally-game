"""Paints a car skin in separate panel pieces and combines them into one texture.

    python art/cars/paint_skin.py martello            # combine the pieces into models/martello_skin.png
    python art/cars/paint_skin.py martello --repaint  # paint the pieces again from scratch first

build_cars.py writes art/cars/<car>_layout.json: the skin size, its pieces
(side_r, side_l, top, front, rear, screen, under) with how each panel is
projected onto them, and the outline of every painted face. This script
paints each piece as its own PNG in art/cars/<car>_pieces/, so a piece can be
touched up by hand in any pixel editor (LibreSprite, Krita, GIMP...) and the
next combine picks the edit up. Positions below are in metres in Blender
space: front +Y, up +Z, ground at 0. Needs Pillow.
"""
import json
import math
import os
import sys

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.normpath(os.path.join(HERE, "..", ".."))


def rgb(r, g, b):
    return (int(r * 255), int(g * 255), int(b * 255), 255)


WHITE = rgb(0.95, 0.95, 0.93)
SHADE = rgb(0.80, 0.81, 0.82)
DARK_BLUE = rgb(0.06, 0.16, 0.48)
LIGHT_BLUE = rgb(0.30, 0.62, 0.92)
RED = rgb(0.82, 0.08, 0.08)
BLACK = rgb(0.05, 0.05, 0.06)
GREY = rgb(0.25, 0.25, 0.27)
GLASS = rgb(0.06, 0.08, 0.13)
AMBER = rgb(1.0, 0.6, 0.1)
YELLOW = rgb(1.0, 0.85, 0.1)


# 5x7 pixel font, one string per row, top to bottom
FONT_ROWS = {
    "A": (".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
    "B": ("####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."),
    "C": (".####", "#....", "#....", "#....", "#....", "#....", ".####"),
    "D": ("####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."),
    "E": ("#####", "#....", "#....", "####.", "#....", "#....", "#####"),
    "F": ("#####", "#....", "#....", "####.", "#....", "#....", "#...."),
    "G": (".####", "#....", "#....", "#.###", "#...#", "#...#", ".####"),
    "H": ("#...#", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"),
    "I": ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "#####"),
    "J": ("..###", "...#.", "...#.", "...#.", "...#.", "#..#.", ".##.."),
    "K": ("#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"),
    "L": ("#....", "#....", "#....", "#....", "#....", "#....", "#####"),
    "M": ("#...#", "##.##", "#.#.#", "#.#.#", "#...#", "#...#", "#...#"),
    "N": ("#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#", "#...#"),
    "O": (".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    "P": ("####.", "#...#", "#...#", "####.", "#....", "#....", "#...."),
    "Q": (".###.", "#...#", "#...#", "#...#", "#.#.#", "#..#.", ".##.#"),
    "R": ("####.", "#...#", "#...#", "####.", "#.#..", "#..#.", "#...#"),
    "S": (".####", "#....", "#....", ".###.", "....#", "....#", "####."),
    "T": ("#####", "..#..", "..#..", "..#..", "..#..", "..#..", "..#.."),
    "U": ("#...#", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."),
    "V": ("#...#", "#...#", "#...#", "#...#", "#...#", ".#.#.", "..#.."),
    "W": ("#...#", "#...#", "#...#", "#.#.#", "#.#.#", "#.#.#", ".#.#."),
    "X": ("#...#", "#...#", ".#.#.", "..#..", ".#.#.", "#...#", "#...#"),
    "Y": ("#...#", "#...#", ".#.#.", "..#..", "..#..", "..#..", "..#.."),
    "Z": ("#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"),
    "0": (".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."),
    "1": ("..#..", ".##..", "..#..", "..#..", "..#..", "..#..", ".###."),
    "2": (".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"),
    "3": ("#####", "...#.", "..#..", "...#.", "....#", "#...#", ".###."),
    "4": ("...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."),
    "5": ("#####", "#....", "####.", "....#", "....#", "#...#", ".###."),
    "6": ("..##.", ".#...", "#....", "####.", "#...#", "#...#", ".###."),
    "7": ("#####", "....#", "...#.", "..#..", ".#...", ".#...", ".#..."),
    "8": (".###.", "#...#", "#...#", ".###.", "#...#", "#...#", ".###."),
    "9": (".###.", "#...#", "#...#", ".####", "....#", "...#.", ".##.."),
    " ": (".....",) * 7,
    "-": (".....", ".....", ".....", "#####", ".....", ".....", "....."),
}
FONT = {k: "".join(v) for k, v in FONT_ROWS.items()}


class Skin:
    def __init__(self, layout):
        self.L = layout
        self.size = layout["size"]
        self.s = layout["px_per_m"]
        self.img = Image.new("RGBA", (self.size, self.size), BLACK)
        self.body = Image.new("L", (self.size, self.size), 0)
        self.glass = Image.new("L", (self.size, self.size), 0)
        for f in layout["faces"]:
            poly = [tuple(p) for p in f["poly"]]
            ImageDraw.Draw(self.glass if f["mat"] == "Glass" else self.body).polygon(poly, fill=255)
        # glass wins where faces overlap at the window edges
        self.body = Image.composite(Image.new("L", self.body.size, 0), self.body, self.glass)

    # ----------------------------------------------------------------- mapping

    def px(self, piece, p):
        pc = self.L["pieces"][piece]
        r, o, u, v = pc["rect"], pc["origin"], pc["u"], pc["v"]
        d = [p[i] - o[i] for i in range(3)]
        return (r[0] + sum(d[i] * u[i] for i in range(3)) * self.s,
                r[1] + sum(d[i] * v[i] for i in range(3)) * self.s)

    def rect(self, piece):
        x, y, w, h = self.L["pieces"][piece]["rect"]
        return (x, y, x + w, y + h)

    def side_pt(self, side, y, z):
        return self.px("side_r" if side > 0 else "side_l", (side, y, z))

    # ----------------------------------------------------------------- painting

    def paint(self, draw_fn, mask="body", clip=None):
        """Draw on a fresh layer with draw_fn(ImageDraw) and stamp it where the mask allows."""
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        draw_fn(ImageDraw.Draw(layer))
        m = {"body": self.body, "glass": self.glass, "any": None}[mask]
        alpha = layer.getchannel("A")
        if m is not None:
            alpha = Image.composite(alpha, Image.new("L", alpha.size, 0), m)
        if clip:
            c = Image.new("L", alpha.size, 0)
            ImageDraw.Draw(c).rectangle(clip, fill=255)
            alpha = Image.composite(alpha, Image.new("L", alpha.size, 0), c)
        layer.putalpha(alpha)
        self.img.alpha_composite(layer)

    def box(self, a, b, col, mask="body"):
        x0, x1 = sorted((a[0], b[0]))
        y0, y1 = sorted((a[1], b[1]))
        r = (round(x0), round(y0), max(round(x1), round(x0) + 1) - 1, max(round(y1), round(y0) + 1) - 1)
        self.paint(lambda d: d.rectangle(r, fill=col), mask)

    def side_box(self, side, y0, y1, z0, z1, col, mask="body"):
        self.box(self.side_pt(side, y0, z0), self.side_pt(side, y1, z1), col, mask)

    def end_box(self, front, x0, x1, z0, z1, col, mask="body"):
        piece = "front" if front else "rear"
        self.box(self.px(piece, (x0, 0, z0)), self.px(piece, (x1, 0, z1)), col, mask)

    def top_box(self, x0, x1, y0, y1, col, mask="body"):
        self.box(self.px("top", (x0, y0, 0)), self.px("top", (x1, y1, 0)), col, mask)

    def text(self, s, centre, height, col, mask="body", rotate=0, bold=False):
        """Pixel-font text about `height` pixels tall (whole multiples of 7)."""
        k = max(1, round(height / 7.0))
        tmp = Image.new("L", ((len(s) * 6 - 1) * k + (1 if bold else 0), 7 * k), 0)
        d = ImageDraw.Draw(tmp)
        for i, ch in enumerate(s.upper()):
            g = FONT.get(ch, FONT[" "])
            for row in range(7):
                for c in range(5):
                    if g[row * 5 + c] == "#":
                        x = (i * 6 + c) * k
                        d.rectangle((x, row * k, x + k - 1 + (1 if bold else 0), row * k + k - 1), fill=255)
        if rotate:
            tmp = tmp.rotate(rotate, expand=True)
        layer = Image.new("RGBA", tmp.size, col)
        layer.putalpha(tmp)
        x = round(centre[0] - tmp.width / 2)
        y = round(centre[1] - tmp.height / 2)
        full = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        full.alpha_composite(layer, (max(x, 0), max(y, 0)))
        m = {"body": self.body, "glass": self.glass, "any": None}[mask]
        if m is not None:
            full.putalpha(Image.composite(full.getchannel("A"), Image.new("L", full.size, 0), m))
        self.img.alpha_composite(full)

    def side_oval(self, side, y0, y1, z0, z1):
        """Pixel box of an oval on one side between two lengths and heights."""
        a, b = self.side_pt(side, y0, z0), self.side_pt(side, y1, z1)
        return (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))

    def crescent(self, outer, inner, col, mask="body"):
        """Ellipse `outer` minus ellipse `inner` (pixel boxes)."""
        def draw(d):
            d.ellipse(outer, fill=col)
            d.ellipse(inner, fill=(0, 0, 0, 0))
        self.paint(draw, mask)

    def disc(self, centre, r, col, mask="body"):
        cx, cy = centre
        self.paint(lambda d: d.ellipse((round(cx - r), round(cy - r), round(cx + r) - 1, round(cy + r) - 1), fill=col), mask)

    def shade(self, piece, fn):
        """Multiply each pixel of a piece by fn(x, y) given its piece-local pixel."""
        x0, y0, x1, y1 = self.rect(piece)
        px = self.img.load()
        for y in range(y0, y1):
            for x in range(x0, x1):
                k = fn(x - x0, y - y0)
                r, g, b, a = px[x, y]
                px[x, y] = (min(255, int(r * k)), min(255, int(g * k)), min(255, int(b * k)), a)

    def outline_glass(self, col):
        """One-pixel window rubbers: body pixels touching glass."""
        g = self.glass.load()
        b = self.body.load()
        px = self.img.load()
        n = self.size
        for y in range(1, n - 1):
            for x in range(1, n - 1):
                if b[x, y] and (g[x - 1, y] or g[x + 1, y] or g[x, y - 1] or g[x, y + 1]):
                    px[x, y] = col


# --------------------------------------------------------------------------- the Delta

def paint_martello(sk):
    W = 0.95  # half width used for full-width bands
    base(sk, WHITE)

    def stripe_z(y):
        """Centre height of the side stripes: level along the doors, sweeping up the front wing."""
        return 0.56 + 0.1 * min(max((y - 1.0) / 0.9, 0.0), 1.0)

    bands = [(0.0, 0.05, DARK_BLUE), (0.05, 0.125, LIGHT_BLUE), (0.125, 0.15, RED)]  # from the top down

    for side in (-1, 1):
        piece = "side_r" if side > 0 else "side_l"
        x0, y0, x1, y1 = sk.rect(piece)

        def stripes(d, side=side, x0=x0, x1=x1):
            for px in range(x0, x1):
                # world y of this column
                o = sk.L["pieces"]["side_r" if side > 0 else "side_l"]["origin"]
                u = sk.L["pieces"]["side_r" if side > 0 else "side_l"]["u"][1]
                yy = o[1] + (px - x0 + 0.5) / sk.s * u
                top = stripe_z(yy) + 0.075
                for a, b, col in bands:
                    _, pa = sk.side_pt(side, yy, top - a)
                    _, pb = sk.side_pt(side, yy, top - b)
                    d.line((px, round(pa), px, round(pb) - 1), fill=col)
        sk.paint(stripes)

        # shut lines, handles, fuel cap
        for dy in (0.86, -0.33, -0.98):
            sk.side_box(side, dy, dy - 0.013, 0.3, 0.84, GREY)
        sk.side_box(side, -0.33, -0.98, 0.835, 0.85, GREY)
        for hy in (-0.2, -0.86):
            sk.side_box(side, hy, hy + 0.12, 0.76, 0.785, BLACK)
        sk.side_box(side, -1.32, -1.42, 0.74, 0.8, SHADE)
        # number on the rear door, roundel on the front door
        sk.side_box(side, -0.46, -0.84, 0.55, 0.82, BLACK)
        sk.side_box(side, -0.475, -0.825, 0.565, 0.805, WHITE)
        sk.text("4", sk.side_pt(side, -0.65, 0.685), 0.22 * sk.s, BLACK, bold=True)
        c = sk.side_pt(side, 0.25, 0.74)
        sk.disc(c, 0.105 * sk.s, BLACK)
        sk.disc(c, 0.095 * sk.s, RED)
        sk.box((c[0] - 0.12 * sk.s, c[1] - 0.022 * sk.s), (c[0] + 0.12 * sk.s, c[1] + 0.022 * sk.s), DARK_BLUE)
        sk.text("PIXEL", c, 0.04 * sk.s, WHITE)
        # tyre maker low along the doors, small stickers behind the front wheel
        sk.text("PIXEL TYRES", sk.side_pt(side, 0.1, 0.38), 0.07 * sk.s, DARK_BLUE, bold=True)
        for i, col in enumerate((RED, DARK_BLUE, BLACK)):
            yy = 0.78 - i * 0.13
            sk.side_box(side, yy, yy - 0.11, 0.47, 0.52, col)

    # top: stripes along the bonnet, roof and spoiler, left of centre; vents are
    # geometry. Spoiler lettering.
    for a, b, col in ((-0.34, -0.27, DARK_BLUE), (-0.27, -0.15, LIGHT_BLUE), (-0.15, -0.115, RED)):
        sk.top_box(a, b, 2.1, -2.1, col)
    sk.text("PIXEL RACING", sk.px("top", (0.0, -1.6, 0)), 0.09 * sk.s, DARK_BLUE, rotate=-90, bold=True)
    c = sk.px("top", (0.35, -0.6, 0))
    sk.box((c[0] - 9, c[1] - 9), (c[0] + 9, c[1] + 9), BLACK)
    sk.box((c[0] - 8, c[1] - 8), (c[0] + 8, c[1] + 8), WHITE)
    sk.text("4", c, 12, BLACK, rotate=-90, bold=True)

    # front: black lamp band, slim red grille, deep bumper with slatted grille,
    # amber corner indicators and a lip sponsor
    sk.end_box(True, -0.82, 0.82, 0.53, 0.715, BLACK)
    sk.end_box(True, -0.11, 0.11, 0.565, 0.685, RED)
    sk.end_box(True, -0.09, 0.09, 0.575, 0.675, BLACK)
    for i in range(5):
        z = 0.585 + i * 0.02
        sk.end_box(True, -0.08, 0.08, z, z + 0.008, GREY)
    for a, b, col in ((-0.34, -0.27, DARK_BLUE), (-0.27, -0.15, LIGHT_BLUE), (-0.15, -0.115, RED)):
        sk.end_box(True, a, b, 0.715, 0.8, col)
    sk.end_box(True, -0.6, 0.6, 0.26, 0.41, BLACK)
    for i in range(6):
        z = 0.28 + i * 0.022
        sk.end_box(True, -0.58, 0.58, z, z + 0.01, GREY)
    for s in (-1, 1):
        sk.end_box(True, s * 0.64, s * 0.8, 0.44, 0.49, AMBER)
    sk.end_box(True, -0.95, 0.95, 0.2, 0.25, RED)
    sk.text("PIXEL OIL", sk.px("front", (0, 0, 0.225)), 0.045 * sk.s, WHITE)

    # rear: tall tail lights (red over amber) at the corners, plate in a black
    # recess, a black bumper band with the tyre maker, stripes wrapping round
    for a, b, col in ((0.0, 0.05, DARK_BLUE), (0.05, 0.125, LIGHT_BLUE), (0.125, 0.15, RED)):
        sk.end_box(False, -W, W, 0.635 - a, 0.635 - b, col)
    for s in (-1, 1):
        sk.end_box(False, s * 0.57, s * 0.85, 0.6, 0.93, BLACK)
        sk.end_box(False, s * 0.59, s * 0.83, 0.75, 0.915, RED)
        sk.end_box(False, s * 0.61, s * 0.81, 0.885, 0.9, rgb(1.0, 0.45, 0.4))
        sk.end_box(False, s * 0.59, s * 0.83, 0.62, 0.74, AMBER)
        sk.disc(sk.px("rear", (s * 0.71, 0, 0.98)), 0.04 * sk.s, RED)
    sk.end_box(False, -0.3, 0.3, 0.66, 0.85, BLACK)
    sk.end_box(False, -0.24, 0.24, 0.7, 0.81, YELLOW)
    sk.text("MH 4", sk.px("rear", (0, 0, 0.755)), 0.08 * sk.s, BLACK, bold=True)
    sk.text("MARTELLO", sk.px("rear", (0, 0, 0.9)), 0.06 * sk.s, BLACK, bold=True)
    sk.end_box(False, -W, W, 0.37, 0.49, BLACK)
    sk.text("PIXEL TYRES", sk.px("rear", (0, 0, 0.43)), 0.07 * sk.s, WHITE, bold=True)
    sk.end_box(False, -W, W, 0.0, 0.33, rgb(0.08, 0.08, 0.09))

    sun_strip(sk, "PIXEL RACING", DARK_BLUE, WHITE)
    finish(sk)


def base(sk, paint):
    sk.paint(lambda d: d.rectangle((0, 0, sk.size, sk.size), fill=paint), "body")
    sk.paint(lambda d: d.rectangle((0, 0, sk.size, sk.size), fill=GLASS), "glass")


def sun_strip(sk, text, bg, fg):
    x0, y0, x1, y1 = sk.rect("screen")
    sk.box((x0, y0), (x1, y0 + 0.15 * sk.s), bg, "glass")
    sk.text(text, ((x0 + x1) / 2, y0 + 0.075 * sk.s), 0.08 * sk.s, fg, "glass", bold=True)


def finish(sk, wheels=(1.32, -1.28)):
    """Glass glints, hand-painted light, window rubbers and the underside."""
    def glints(d):
        for k in range(-sk.size, sk.size, 23):
            d.line((k, 0, k + sk.size, sk.size), fill=rgb(0.16, 0.2, 0.28), width=2)
    sk.paint(glints, "glass")

    # hand-painted light: sides darken towards the sills and round the wheel
    # arches, catch a highlight under the belt; nose and tail fall off at the
    # corners; the top is brightest down the middle
    for side in (-1, 1):
        piece = "side_r" if side > 0 else "side_l"
        o = sk.L["pieces"][piece]["origin"]
        u = sk.L["pieces"][piece]["u"][1]

        def k(x, y, o=o, u=u):
            wy = o[1] + (x + 0.5) / sk.s * u
            z = o[2] - (y + 0.5) / sk.s
            v = 0.74 + 0.3 * min(max((z - 0.15) / 0.7, 0.0), 1.0)
            if 0.79 < z < 0.82:
                v += 0.08
            for wy0 in wheels:
                r = math.hypot(wy - wy0, z - 0.34)
                if 0.4 < r < 0.52 and z > 0.2:
                    v *= 0.78 + 0.22 * (r - 0.4) / 0.12
            return v
        sk.shade(piece, k)
    for piece in ("front", "rear"):
        sk.shade(piece, lambda x, y: (1.04 - 0.24 * max(abs(x / sk.s - 1.0) - 0.6, 0.0) / 0.4)
                 * (0.86 + 0.14 * min(max((1.6 - y / sk.s - 0.2) / 0.5, 0.0), 1.0)))
    sk.shade("top", lambda x, y: 1.02 - 0.12 * max(abs(y / sk.s - 1.0) - 0.5, 0.0) / 0.5)
    sk.outline_glass(BLACK)
    x0, y0, x1, y1 = sk.rect("under")
    sk.img.paste(rgb(0.08, 0.08, 0.09), (x0, y0, x1, y1))


# --------------------------------------------------------------------------- the Impreza

DEEP_BLUE = rgb(0.165, 0.247, 0.627)
GOLD_YELLOW = rgb(1.0, 0.84, 0.1)


def paint_pleiad(sk):
    """555-style works Impreza: deep blue, yellow crescent swooshes and big
    lucky numbers (made-up sponsor STAR 777), number panels with a yellow top."""
    base(sk, DEEP_BLUE)
    navy = rgb(0.08, 0.12, 0.36)
    for side in (-1, 1):
        # shut lines, handles, fuel cap
        for dy in (0.92, -0.35, -1.12):
            sk.side_box(side, dy, dy - 0.013, 0.3, 0.86, navy)
        for hy in (-0.22, -0.98):
            sk.side_box(side, hy, hy + 0.11, 0.78, 0.8, BLACK)
        sk.side_box(side, -1.45, -1.55, 0.78, 0.84, rgb(0.12, 0.18, 0.5))
        # the big swoosh along the rear door and quarter, numbers riding on it
        outer = sk.side_oval(side, -0.3, -2.1, 0.46, 0.86)
        inner = sk.side_oval(side, -0.25, -2.05, 0.535, 0.93)
        sk.crescent(outer, inner, GOLD_YELLOW)
        sk.text("777", sk.side_pt(side, -0.74, 0.68), 0.22 * sk.s, GOLD_YELLOW, bold=True)
        sk.text("STAR", sk.side_pt(side, -1.45, 0.72), 0.07 * sk.s, WHITE)
        # number panel with a yellow top on the front door
        sk.side_box(side, 0.5, 0.06, 0.52, 0.8, WHITE)
        sk.side_box(side, 0.5, 0.06, 0.74, 0.8, GOLD_YELLOW)
        sk.text("5", sk.side_pt(side, 0.28, 0.625), 0.18 * sk.s, BLACK, bold=True)
        sk.text("PLEIAD", sk.side_pt(side, 0.28, 0.42), 0.07 * sk.s, WHITE, bold=True)
        # small stickers behind the front wheel, tyre maker on the sill
        for i, col in enumerate((GOLD_YELLOW, WHITE, RED)):
            yy = 0.86 - i * 0.12
            sk.side_box(side, yy, yy - 0.1, 0.64, 0.69, col)
        sk.text("PIXELLI", sk.side_pt(side, 0.28, 0.33), 0.07 * sk.s, GOLD_YELLOW)
        # crew names on the rear side windows
        sk.text("A PIXEL", sk.side_pt(side, -0.82, 1.12), 7, WHITE, "glass")
        sk.text("B BYTE", sk.side_pt(side, -0.82, 1.02), 7, WHITE, "glass")

    # top: crescent and numbers on the bonnet (reading from in front) and on
    # the boot (from behind), roof number
    def top_crescent(cy, flip):
        a = sk.px("top", (-0.55, cy + 0.32 * flip, 0))
        b = sk.px("top", (0.55, cy - 0.32 * flip, 0))
        outer = (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))
        sh = 0.06 * sk.s * flip
        inner = (outer[0] + sh, outer[1] - 0.02 * sk.s, outer[2] + sh, outer[3] + 0.02 * sk.s)
        sk.crescent(outer, inner, GOLD_YELLOW)
    top_crescent(1.55, 1)
    sk.text("777", sk.px("top", (0.0, 1.6, 0)), 0.18 * sk.s, GOLD_YELLOW, rotate=90, bold=True)
    sk.text("PLEIAD", sk.px("top", (0.0, 1.3, 0)), 0.08 * sk.s, WHITE, rotate=90, bold=True)
    top_crescent(-1.85, -1)
    sk.text("777", sk.px("top", (0.0, -1.85, 0)), 0.12 * sk.s, GOLD_YELLOW, rotate=-90, bold=True)
    c = sk.px("top", (0.0, -0.35, 0))
    sk.box((c[0] - 10, c[1] - 10), (c[0] + 10, c[1] + 10), GOLD_YELLOW)
    sk.box((c[0] - 9, c[1] - 9), (c[0] + 9, c[1] + 9), WHITE)
    sk.text("5", c, 14, BLACK, rotate=-90, bold=True)

    # front: rounded headlamps under the bonnet edge, small grille with a
    # cluster of gold stars, deep bumper with a wide black intake and fog lamps
    sk.end_box(True, -0.27, 0.27, 0.6, 0.69, BLACK)
    for x, z in ((-0.08, 0.66), (0.0, 0.64), (0.07, 0.66), (0.13, 0.63), (-0.14, 0.63), (0.03, 0.615)):
        sk.disc(sk.px("front", (x, 0, z)), 1.5, GOLD_YELLOW)
    for s_ in (-1, 1):
        a = sk.px("front", (s_ * 0.31, 0, 0.6))
        b = sk.px("front", (s_ * 0.8, 0, 0.71))
        box = (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))
        sk.paint(lambda d, box=box: d.rounded_rectangle(box, radius=4, fill=GREY, outline=BLACK))
        a = sk.px("front", (s_ * 0.36, 0, 0.615))
        b = sk.px("front", (s_ * 0.6, 0, 0.695))
        sk.paint(lambda d, a=a, b=b: d.ellipse((min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1])),
                                               fill=rgb(1.0, 0.98, 0.86)))
        sk.end_box(True, s_ * 0.63, s_ * 0.77, 0.625, 0.69, rgb(1.0, 0.95, 0.75))
        sk.end_box(True, s_ * 0.66, s_ * 0.79, 0.5, 0.54, AMBER)
        sk.disc(sk.px("front", (s_ * 0.7, 0, 0.34)), 0.065 * sk.s, BLACK)
        sk.disc(sk.px("front", (s_ * 0.7, 0, 0.34)), 0.05 * sk.s, rgb(1.0, 0.92, 0.55))
    sk.end_box(True, -0.58, 0.58, 0.24, 0.43, BLACK)
    for i in range(7):
        z = 0.26 + i * 0.024
        sk.end_box(True, -0.56, 0.56, z, z + 0.008, GREY)
    sk.text("PIXELDRIVE", sk.px("front", (0, 0, 0.49)), 7, WHITE)
    sk.end_box(True, -0.95, 0.95, 0.19, 0.23, BLACK)

    # rear: wide red tail lights with amber sections either side of a black
    # plate panel, stickers on the bumper corners, black diffuser
    for s_ in (-1, 1):
        sk.end_box(False, s_ * 0.3, s_ * 0.86, 0.66, 0.85, BLACK)
        sk.end_box(False, s_ * 0.44, s_ * 0.84, 0.68, 0.83, RED)
        sk.end_box(False, s_ * 0.46, s_ * 0.82, 0.8, 0.815, rgb(1.0, 0.45, 0.4))
        sk.end_box(False, s_ * 0.32, s_ * 0.43, 0.68, 0.83, AMBER)
        sk.end_box(False, s_ * 0.68, s_ * 0.84, 0.43, 0.49, GOLD_YELLOW)
        sk.text("PIX", sk.px("rear", (s_ * 0.76, 0, 0.46)), 7, RED)
    sk.end_box(False, -0.3, 0.3, 0.66, 0.85, BLACK)
    sk.end_box(False, -0.24, 0.24, 0.69, 0.8, YELLOW)
    sk.text("PL 555", sk.px("rear", (0, 0, 0.745)), 7, BLACK, bold=True)
    sk.text("PLEIAD", sk.px("rear", (0, 0, 0.92)), 7, GOLD_YELLOW, bold=True)
    sk.end_box(False, -0.95, 0.95, 0.0, 0.34, rgb(0.08, 0.08, 0.09))

    sun_strip(sk, "PLEIAD", navy, GOLD_YELLOW)
    finish(sk)


# --------------------------------------------------------------------------- the F1 car

def paint_veloce(sk):
    """Black works F1 livery: gloss black with red highlights, a red charging
    bolt on the engine cover, red wing elements and endplate details, a
    silver halo, silver-grey sponsors (made-up ORBITAL and PAYPIX) and a
    dithered metallic fade along the sidepod flanks. Number 1."""
    black = rgb(0.045, 0.045, 0.05)
    matte = rgb(0.03, 0.03, 0.035)
    red = rgb(0.86, 0.06, 0.08)
    silver = rgb(0.72, 0.74, 0.78)
    grey = rgb(0.5, 0.52, 0.56)
    base(sk, black)

    def bolt(c, r, col):
        """Charging bolt, about r pixels from its centre to its tips."""
        x, y = c
        pts = [(x - 1.0 * r, y + 0.45 * r), (x + 0.05 * r, y - 0.1 * r), (x - 0.15 * r, y - 0.3 * r),
               (x + 1.0 * r, y - 0.55 * r), (x - 0.05 * r, y + 0.1 * r), (x + 0.15 * r, y + 0.3 * r)]
        sk.paint(lambda d: d.polygon(pts, fill=col))

    def fade(side, y0, y1, z0, z1, a, b):
        """Ordered-dither fade from colour a at y0 to colour b at y1."""
        p0, p1 = sk.side_pt(side, y0, z0), sk.side_pt(side, y1, z1)
        bayer = ((0, 8, 2, 10), (12, 4, 14, 6), (3, 11, 1, 9), (15, 7, 13, 5))

        def draw(d):
            xa, xb = sorted((round(p0[0]), round(p1[0])))
            ya, yb = sorted((round(p0[1]), round(p1[1])))
            for x in range(xa, xb):
                t = (x - p0[0]) / (p1[0] - p0[0])
                for y in range(ya, yb):
                    d.point((x, y), fill=b if t * 16 > bayer[y % 4][x % 4] + 0.5 else a)
        sk.paint(draw)

    for side in (-1, 1):
        # red and white nose tip, red front wing endplates with a grey stripe
        sk.side_box(side, 2.25, 2.6, 0.0, 0.6, red)
        sk.side_box(side, 2.1, 2.25, 0.0, 0.6, WHITE)
        sk.side_box(side, 2.18, 2.62, 0.04, 0.31, red)
        sk.side_box(side, 2.18, 2.62, 0.2, 0.22, silver)
        sk.text("1", sk.side_pt(side, 1.8, 0.34), 7, red, bold=True)
        sk.side_box(side, 1.62, 1.5, 0.3, 0.36, WHITE)
        # sidepods: big light-grey sponsor, metallic fade to the gearbox, matte undercut
        fade(side, -0.5, -1.35, 0.15, 0.36, black, grey)
        sk.side_box(side, 0.22, -1.35, 0.15, 0.22, matte)
        sk.text("ORBITAL", sk.side_pt(side, -0.4, 0.42), 14, silver, bold=True)
        sk.side_box(side, 0.2, -0.95, 0.28, 0.3, red)
        # engine cover: the red charging bolt by the airbox, small red logos
        bolt(sk.side_pt(side, -0.9, 0.7), 0.2 * sk.s, red)
        sk.text("PAYPIX", sk.side_pt(side, -1.55, 0.36), 7, red)
        sk.text("VELOCE", sk.side_pt(side, 0.85, 0.36), 7, grey)
        # silver halo, red rear wing endplate details
        sk.side_box(side, 0.36, -0.46, 0.66, 0.84, silver)
        x0, y0 = sk.side_pt(side, -2.08, 0.72)
        sk.text("PAYPIX", (x0, y0), 7, silver, rotate=90 * side, bold=True)
        sk.side_box(side, -1.85, -2.31, 0.98, 1.03, red)
        sk.side_box(side, -1.85, -2.31, 0.42, 0.47, red)

    # top: red/white nose, red wing elements with grey-white lettering, halo,
    # the bolt on the engine cover, rear wing sponsor
    sk.top_box(-0.12, 0.12, 2.25, 2.6, red)
    sk.top_box(-0.12, 0.12, 2.1, 2.25, WHITE)
    for sx in (-1, 1):
        sk.top_box(sx * 0.12, sx * 1.0, 2.15, 2.6, red)
        sk.text("VELOCE", sk.px("top", (sx * 0.55, 2.41, 0)), 7, rgb(0.9, 0.9, 0.9), rotate=90, bold=True)
        sk.top_box(sx * 0.23, sx * 0.33, 0.25, -0.45, silver)
    sk.text("1", sk.px("top", (0.0, 1.85, 0)), 7, red, rotate=90, bold=True)
    sk.top_box(-0.05, 0.05, 1.45, 1.3, WHITE)
    sk.top_box(-0.05, 0.05, 0.33, 0.22, silver)
    bolt(sk.px("top", (0.0, -1.05, 0)), 0.12 * sk.s, red)
    sk.text("ORBITAL", sk.px("top", (0.0, -2.12, 0)), 7, silver, rotate=-90, bold=True)
    sk.top_box(-0.6, 0.6, -2.26, -2.3, red)

    # front: nose and wing faces; rear: rear wing edge, rain light surround
    sk.end_box(True, -0.15, 0.15, 0.1, 0.5, red)
    sk.end_box(True, -1.0, -0.15, 0.04, 0.3, red)
    sk.end_box(True, 0.15, 1.0, 0.04, 0.3, red)
    sk.end_box(False, -0.6, 0.6, 0.97, 1.03, red)
    sk.end_box(False, -0.12, 0.12, 0.27, 0.37, matte)

    finish(sk, wheels=())


PAINTERS = {"martello": paint_martello, "pleiad": paint_pleiad, "veloce": paint_veloce}


def main():
    car = sys.argv[1] if len(sys.argv) > 1 else "martello"
    repaint = "--repaint" in sys.argv
    layout = json.load(open(os.path.join(HERE, car + "_layout.json")))
    pieces_dir = os.path.join(HERE, car + "_pieces")
    os.makedirs(pieces_dir, exist_ok=True)
    names = list(layout["pieces"])
    missing = [n for n in names if not os.path.exists(os.path.join(pieces_dir, n + ".png"))]
    if repaint or missing:
        sk = Skin(layout)
        PAINTERS[car](sk)
        for n in names:
            sk.img.crop(sk.rect(n)).save(os.path.join(pieces_dir, n + ".png"))
    # combine: every piece pasted back into its rect
    out = Image.new("RGBA", (layout["size"], layout["size"]), BLACK)
    for n in names:
        x, y, w, h = layout["pieces"][n]["rect"]
        out.paste(Image.open(os.path.join(pieces_dir, n + ".png")).convert("RGBA"), (x, y))
    out.convert("RGB").save(os.path.join(REPO, "models", car + "_skin.png"))
    print("wrote models/%s_skin.png from %d pieces" % (car, len(names)))


if __name__ == "__main__":
    main()
