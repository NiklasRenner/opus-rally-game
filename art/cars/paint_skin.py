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
    "Б": ("#####", "#....", "#....", "####.", "#...#", "#...#", "####."),
    "Й": (".#.#.", "#...#", "#..##", "#.#.#", "##..#", "#...#", "#...#"),
    ".": (".....", ".....", ".....", ".....", ".....", ".##..", ".##.."),
    "Д": ("..##.", ".#.#.", ".#.#.", ".#.#.", ".#.#.", "#####", "#...#"),
    "И": ("#...#", "#...#", "#..##", "#.#.#", "##..#", "#...#", "#...#"),
    "Л": ("..###", ".#..#", ".#..#", ".#..#", ".#..#", ".#..#", "#...#"),
    "П": ("#####", "#...#", "#...#", "#...#", "#...#", "#...#", "#...#"),
    "Э": ("###..", "...#.", "....#", ".####", "....#", "...#.", "###.."),
    " ": (".....",) * 7,
    "-": (".....", ".....", ".....", "#####", ".....", ".....", "....."),
}
FONT = {k: "".join(v) for k, v in FONT_ROWS.items()}
for _cy, _lat in zip("АВЕКМНОРСТХ", "ABEKMHOPCTX"):
    FONT[_cy] = FONT[_lat]


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

    def text(self, s, centre, height, col, mask="body", rotate=0, bold=False, italic=False):
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
        if italic:  # lean the top of the letters forward
            lean = round(0.3 * tmp.height)
            tmp = tmp.transform((tmp.width + lean, tmp.height), Image.AFFINE, (1, 0.3, -lean, 0, 1, 0),
                                resample=Image.NEAREST)
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


def finish(sk, wheels=(1.32, -1.28), hub=0.34, arch=0.4, belt=0.8):
    """Hand-painted light, window rubbers and the underside. The glass stays
    plain: the game's RetroLook shader gives it a moving fake reflection.
    hub, arch: wheel centre height and arch radius; belt: the highlight line."""
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
            if belt - 0.01 < z < belt + 0.02:
                v += 0.08
            for wy0 in wheels:
                r = math.hypot(wy - wy0, z - hub)
                if arch < r < arch + 0.12 and z > 0.2:
                    v *= 0.78 + 0.22 * (r - arch) / 0.12
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
        sk.text("SAKSEN", sk.side_pt(side, 0.28, 0.42), 0.07 * sk.s, WHITE, bold=True)
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
    sk.text("SAKSEN", sk.px("top", (0.0, 1.3, 0)), 0.08 * sk.s, WHITE, rotate=90, bold=True)
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
    sk.text("SA 777", sk.px("rear", (0, 0, 0.745)), 7, BLACK, bold=True)
    sk.text("SAKSEN", sk.px("rear", (0, 0, 0.92)), 7, GOLD_YELLOW, bold=True)
    sk.end_box(False, -0.95, 0.95, 0.0, 0.34, rgb(0.08, 0.08, 0.09))

    sun_strip(sk, "SAKSEN", navy, GOLD_YELLOW)
    finish(sk)


# --------------------------------------------------------------------------- the Ibiza

def paint_balear(sk):
    """Kit car in works yellow: big blue italic name on the doors, a red and
    blue fuel-company stripe over the bonnet and screen, a blue phone-company
    panel on the bonnet and bumper (made-up PETROPIX and MOVIPIX), number 15."""
    yellow = rgb(1.0, 0.82, 0.05)
    blue = rgb(0.08, 0.2, 0.62)
    base(sk, yellow)
    for side in (-1, 1):
        # shut lines, handle, fuel cap
        sk.side_box(side, 0.95, 0.937, 0.3, 0.86, rgb(0.62, 0.5, 0.05))
        sk.side_box(side, -0.62, -0.633, 0.3, 0.86, rgb(0.62, 0.5, 0.05))
        sk.side_box(side, -0.42, -0.54, 0.78, 0.8, BLACK)
        sk.side_box(side, -1.25, -1.35, 0.78, 0.84, rgb(0.85, 0.7, 0.05))
        # number panel, the name in big blue italics with the trim above it
        sk.side_box(side, -0.17, -0.56, 0.62, 0.84, BLACK)
        sk.side_box(side, -0.18, -0.55, 0.63, 0.83, WHITE)
        sk.text("15", sk.side_pt(side, -0.365, 0.73), 14, BLACK, bold=True)
        sk.text("BALEAR", sk.side_pt(side, 0.2, 0.47), 21, blue, bold=True, italic=True)
        sk.text("KIT CAR", sk.side_pt(side, 0.42, 0.72), 7, blue, bold=True, italic=True)
        sk.text("SPORT", sk.side_pt(side, -0.4, 0.4), 7, RED, italic=True)
        # stickers on the rear quarter and the front bumper corner
        for i, col in enumerate((blue, RED, WHITE)):
            yy = -0.8 - i * 0.14
            sk.side_box(side, yy, yy - 0.12, 0.62, 0.67, col)
        sk.text("PIXELLI", sk.side_pt(side, 1.68, 0.4), 7, BLACK)

    # top: phone-company panel across the bonnet front, fuel stripe at the
    # base of the screen, roof number, the name along the spoiler
    sk.top_box(-1.0, 1.0, 1.55, 1.9, blue)
    sk.text("MOVIPIX", sk.px("top", (0.0, 1.72, 0)), 14, WHITE, rotate=90, bold=True)
    sk.top_box(-1.0, 1.0, 1.0, 1.1, RED)
    sk.top_box(-1.0, 1.0, 1.1, 1.18, blue)
    c = sk.px("top", (0.0, -0.4, 0))
    sk.box((c[0] - 10, c[1] - 12), (c[0] + 10, c[1] + 12), BLACK)
    sk.box((c[0] - 9, c[1] - 11), (c[0] + 9, c[1] + 11), WHITE)
    sk.text("15", c, 7, BLACK, rotate=-90, bold=True)
    sk.text("BALEAR", sk.px("top", (0.0, -1.42, 0)), 14, blue, "any", rotate=-90, bold=True, italic=True)

    # front: slim lamps either side of a small grille, deep bumper with a
    # black intake, square fog lamps and tyre stickers on the corners
    sk.end_box(True, -0.22, 0.22, 0.6, 0.69, BLACK)
    sk.disc(sk.px("front", (0, 0, 0.645)), 3, RED)
    for s_ in (-1, 1):
        sk.end_box(True, s_ * 0.27, s_ * 0.76, 0.615, 0.69, BLACK)
        sk.end_box(True, s_ * 0.29, s_ * 0.6, 0.625, 0.68, rgb(1.0, 0.98, 0.86))
        sk.end_box(True, s_ * 0.62, s_ * 0.74, 0.625, 0.68, AMBER)
        sk.end_box(True, s_ * 0.6, s_ * 0.8, 0.29, 0.39, BLACK)
        sk.end_box(True, s_ * 0.62, s_ * 0.78, 0.31, 0.37, rgb(1.0, 0.93, 0.6))
        sk.text("PIX", sk.px("front", (s_ * 0.72, 0, 0.47)), 7, BLACK)
    sk.end_box(True, -0.55, 0.55, 0.24, 0.42, BLACK)
    for i in range(6):
        z = 0.26 + i * 0.026
        sk.end_box(True, -0.53, 0.53, z, z + 0.009, GREY)
    sk.end_box(True, -0.55, 0.55, 0.45, 0.52, blue)
    sk.text("MOVIPIX", sk.px("front", (0, 0, 0.485)), 7, WHITE)

    # rear: wide red tail lights, black plate panel, blue bumper panel with
    # the fuel company, stickers on the corners, diffuser
    for s_ in (-1, 1):
        sk.end_box(False, s_ * 0.36, s_ * 0.87, 0.64, 0.82, BLACK)
        sk.end_box(False, s_ * 0.48, s_ * 0.85, 0.66, 0.8, RED)
        sk.end_box(False, s_ * 0.5, s_ * 0.83, 0.77, 0.785, rgb(1.0, 0.45, 0.4))
        sk.end_box(False, s_ * 0.38, s_ * 0.47, 0.66, 0.8, AMBER)
        sk.text("PIX", sk.px("rear", (s_ * 0.74, 0, 0.47)), 7, BLACK)
    sk.end_box(False, -0.34, 0.34, 0.63, 0.84, BLACK)
    sk.end_box(False, -0.24, 0.24, 0.68, 0.79, YELLOW)
    sk.text("BK 15", sk.px("rear", (0, 0, 0.735)), 7, BLACK, bold=True)
    sk.end_box(False, -0.55, 0.55, 0.38, 0.52, blue)
    sk.text("PETROPIX", sk.px("rear", (0, 0, 0.45)), 7, WHITE, bold=True)
    sk.end_box(False, -0.95, 0.95, 0.0, 0.34, rgb(0.08, 0.08, 0.09))

    # sun strip: the fuel company in red and blue
    x0, y0, x1, y1 = sk.rect("screen")
    sk.box((x0, y0), (x1, y0 + 0.15 * sk.s), RED, "glass")
    sk.box((x0, y0 + 0.11 * sk.s), (x1, y0 + 0.15 * sk.s), blue, "glass")
    sk.text("PETROPIX", ((x0 + x1) / 2, y0 + 0.055 * sk.s), 7, WHITE, "glass", bold=True)
    finish(sk)


# --------------------------------------------------------------------------- the monster truck

def paint_swamp(sk):
    """Monster truck in lime splatter camo with yellow and orange swirls, a
    blacked-out grille and big outlined lettering (made-up SWAMP KING)."""
    import random
    rnd = random.Random(7)
    lime = rgb(0.55, 0.85, 0.12)
    green = rgb(0.18, 0.42, 0.08)
    dark = rgb(0.08, 0.22, 0.05)
    yellow = rgb(1.0, 0.85, 0.08)
    orange = rgb(1.0, 0.45, 0.05)
    base(sk, lime)

    def splatter(d):
        for _ in range(420):
            x, y = rnd.uniform(0, sk.size), rnd.uniform(0, sk.size)
            r = rnd.uniform(2, 9)
            d.ellipse((x - r, y - r * 0.7, x + r, y + r * 0.7), fill=green if rnd.random() < 0.7 else dark)
            for _ in range(3):  # drips and flecks round each blot
                fx, fy = x + rnd.uniform(-2, 2) * r, y + rnd.uniform(-2, 2) * r
                d.rectangle((fx, fy, fx + 1, fy + 1), fill=dark)
    sk.paint(splatter)

    def outlined(text, centre, height, fill, rotate=0, italic=False):
        for dx, dy in ((-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, 1), (-1, 1), (1, -1)):
            sk.text(text, (centre[0] + dx * 2, centre[1] + dy * 2), height, BLACK, rotate=rotate, bold=True, italic=italic)
        sk.text(text, centre, height, fill, rotate=rotate, bold=True, italic=italic)

    for side in (-1, 1):
        # swirls: big yellow and orange arcs sweeping along the bed and doors
        for (y0, y1, z0, z1, col, w) in ((-2.4, 0.0, 1.45, 2.5, yellow, 5), (-1.8, 0.7, 1.58, 2.3, orange, 4),
                                         (0.2, 2.4, 1.45, 2.4, yellow, 4)):
            box = sk.side_oval(side, y0, y1, z0, z1)
            sk.paint(lambda d, box=box, col=col, w=w: d.arc(box, 15, 165, fill=col, width=w))
        # the name reads front to back on both sides
        first, second = (-1.15, 0.2) if side > 0 else (0.2, -1.15)
        outlined("SWAMP", sk.side_pt(side, first, 1.75), 14, orange, italic=True)
        outlined("KING", sk.side_pt(side, second, 1.75), 14, yellow, italic=True)
        # number on the door, stickers on the front wing
        sk.side_box(side, 0.62, 0.34, 1.82, 1.98, WHITE)
        sk.text("7", sk.side_pt(side, 0.48, 1.9), 7, BLACK, bold=True)
        for i, col in enumerate((yellow, RED, WHITE)):
            yy = 1.85 - i * 0.15
            sk.side_box(side, yy, yy - 0.12, 1.5, 1.56, col)
        sk.text("PIXEL TYRES", sk.side_pt(side, 1.3, 1.62), 7, BLACK)

    # top: bonnet name reading from in front, splatter, bed liner
    outlined("KING", sk.px("top", (0.0, 1.5, 0)), 14, yellow, rotate=90, italic=True)
    sk.top_box(-0.8, 0.8, -0.55, -1.95, rgb(0.12, 0.12, 0.12))
    for i in range(6):
        y = -0.7 - i * 0.22
        sk.top_box(-0.78, 0.78, y, y - 0.05, rgb(0.2, 0.2, 0.2))

    # front: blacked-out grille, headlamps, bumper plate
    sk.end_box(True, -0.6, 0.6, 1.4, 1.72, BLACK)
    for i in range(5):
        z = 1.44 + i * 0.055
        sk.end_box(True, -0.45, 0.45, z, z + 0.02, rgb(0.15, 0.15, 0.16))
    for s_ in (-1, 1):
        sk.disc(sk.px("front", (s_ * 0.6, 0, 1.6)), 0.07 * sk.s, rgb(1.0, 0.97, 0.82))
        sk.end_box(True, s_ * 0.68, s_ * 0.86, 1.45, 1.52, AMBER)
    outlined("SWAMP KING", sk.px("front", (0, 0, 1.86)), 7, orange)

    # rear: tailgate name, tail lights, plate
    outlined("SWAMP KING", sk.px("rear", (0, 0, 1.68)), 7, orange)
    for s_ in (-1, 1):
        sk.end_box(False, s_ * 0.66, s_ * 0.88, 1.45, 1.75, BLACK)
        sk.end_box(False, s_ * 0.68, s_ * 0.86, 1.6, 1.73, RED)
        sk.end_box(False, s_ * 0.68, s_ * 0.86, 1.47, 1.58, AMBER)
    sk.end_box(False, -0.2, 0.2, 1.42, 1.52, YELLOW)
    sk.text("SK 7", sk.px("rear", (0, 0, 1.47)), 7, BLACK, bold=True)

    sun_strip(sk, "SWAMP KING", BLACK, yellow)
    finish(sk, wheels=())


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
        sk.text("PEAK", sk.side_pt(side, 0.85, 0.36), 7, grey)
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
        sk.text("PEAK", sk.px("top", (sx * 0.55, 2.41, 0)), 7, rgb(0.9, 0.9, 0.9), rotate=90, bold=True)
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


# --------------------------------------------------------------------------- the hypercar

def paint_bellatrix(sk):
    """Two-tone hypercar: bright blue nose, bonnet, front wings and the front
    of the doors, dark gunmetal behind the chrome C, over the roof and the
    engine cover. Dark mesh tail panel with the wordmark under the light bar,
    a darker spine down the bonnet. Made-up marque BONGATTI."""
    blue = rgb(0.12, 0.42, 0.88)
    deep = rgb(0.07, 0.27, 0.66)
    gun = rgb(0.22, 0.23, 0.26)
    mesh = rgb(0.06, 0.06, 0.07)
    silver = rgb(0.78, 0.8, 0.83)
    base(sk, blue)

    # the chrome C (build_cars.py, c_line): top run under the side glass,
    # round behind the door, bottom run along the sill
    y_top, y_back, z_low = -0.45, -0.9, 0.32

    def c_top(y):
        return lerp(0.71, 0.81, min(max((0.85 - y) / 1.3, 0.0), 1.0))

    for side in (-1, 1):
        piece = "side_r" if side > 0 else "side_l"
        o = sk.L["pieces"][piece]["origin"]
        u = sk.L["pieces"][piece]["u"][1]
        x0, y0, x1, y1 = sk.rect(piece)

        def two_tone(d, o=o, u=u, x0=x0, y0=y0, x1=x1, y1=y1):
            zt = c_top(y_top)
            zc, rz, ry = (zt + z_low) / 2, (zt - z_low) / 2, y_top - y_back
            for px in range(x0, x1):
                wy = o[1] + (px - x0 + 0.5) / sk.s * u
                for py in range(y0, y1):
                    z = o[2] - (py - y0 + 0.5) / sk.s
                    if wy > 0.88:
                        dark = False  # front wing: all blue
                    elif z > c_top(wy) + 0.015:
                        dark = True  # pillars and roof edge
                    elif z < z_low - 0.015:
                        dark = True  # sills
                    elif wy < y_top:
                        dark = ((wy - y_top) / ry) ** 2 + ((z - zc) / rz) ** 2 > 1.0
                    else:
                        dark = False
                    if dark:
                        d.point((px, py), fill=gun)
        sk.paint(two_tone)
        # shut line and handle on the door, inside the C
        sk.side_box(side, 0.86, 0.847, 0.3, 0.72, deep)
        sk.side_box(side, -0.32, -0.42, 0.66, 0.68, rgb(0.05, 0.18, 0.5))
        # side intake behind the C, small wordmark on the sill
        sk.paint(lambda d, side=side: d.polygon([sk.side_pt(side, -0.98, 0.72), sk.side_pt(side, -1.02, 0.42),
                                                  sk.side_pt(side, -0.9, 0.36), sk.side_pt(side, -0.93, 0.7)], fill=mesh))
        sk.text("BONGATTI", sk.side_pt(side, 0.25, 0.25), 7, silver)

    # top: blue bonnet with a darker spine, gunmetal roof and engine cover,
    # a dark band of glass over the engine
    sk.top_box(-1.0, 1.0, 0.85, -2.4, gun)
    sk.top_box(-0.035, 0.035, 2.3, 0.88, deep)
    for sx in (-1, 1):
        sk.top_box(sx * 0.3, sx * 0.32, 2.1, 0.95, deep)
    sk.top_box(-0.42, 0.42, -0.62, -1.05, mesh)

    # front: dark lower lip, red badge sits on the grille (geometry)
    sk.end_box(True, -0.95, 0.95, 0.0, 0.16, mesh)

    # rear: gunmetal tail with a black mesh panel under the light bar, the
    # wordmark between them, black diffuser
    sk.end_box(False, -1.0, 1.0, 0.0, 1.6, gun)
    sk.end_box(False, -0.8, 0.8, 0.34, 0.68, mesh)
    for i in range(9):
        z = 0.36 + i * 0.036
        sk.end_box(False, -0.78, 0.78, z, z + 0.012, rgb(0.14, 0.14, 0.16))
    for i in range(22):
        x = -0.76 + i * 0.072
        sk.end_box(False, x, x + 0.012, 0.35, 0.67, rgb(0.14, 0.14, 0.16))
    sk.text("BONGATTI", sk.px("rear", (0, 0, 0.73)), 7, silver, bold=True)
    sk.end_box(False, -1.0, 1.0, 0.0, 0.3, mesh)

    finish(sk, wheels=(1.4, -1.32))


# --------------------------------------------------------------------------- the Niva

def emblem(sk, draw_fn, centre, size, col, mask="body", rotate=0):
    """A small badge drawn big with draw_fn(ImageDraw, n) on an n x n canvas,
    then shrunk to `size` pixels with hard edges so it reads as pixel art."""
    n = 64
    big = Image.new("L", (n, n), 0)
    draw_fn(ImageDraw.Draw(big), n)
    if rotate:
        big = big.rotate(rotate)
    px = max(3, round(size))
    small = big.resize((px, px), Image.BOX).point(lambda v: 255 if v > 80 else 0)
    layer = Image.new("RGBA", small.size, col)
    layer.putalpha(small)
    full = Image.new("RGBA", sk.img.size, (0, 0, 0, 0))
    full.alpha_composite(layer, (round(centre[0] - px / 2), round(centre[1] - px / 2)))
    m = {"body": sk.body, "glass": sk.glass, "any": None}[mask]
    if m is not None:
        full.putalpha(Image.composite(full.getchannel("A"), Image.new("L", full.size, 0), m))
    sk.img.alpha_composite(full)


def star_shape(d, n):
    c, r0, r1 = n / 2, n * 0.5, n * 0.2
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = r0 if i % 2 == 0 else r1
        pts.append((c + r * math.cos(a), c + 0.04 * n + r * math.sin(a)))
    d.polygon(pts, fill=255)


def hammer_sickle_shape(d, n):
    k = n / 64.0
    # sickle: a crescent round the right, thick at the back of the blade and
    # opening to the left, its handle out to the bottom left
    d.ellipse((12 * k, 4 * k, 62 * k, 54 * k), fill=255)
    d.ellipse((6 * k, 0, 52 * k, 46 * k), fill=0)
    d.rectangle((0, 0, 20 * k, 40 * k), fill=0)
    d.line((30 * k, 50 * k, 8 * k, 61 * k), fill=255, width=round(8 * k))
    # hammer: head at the top left, handle down to the bottom right
    d.line((22 * k, 22 * k, 58 * k, 58 * k), fill=255, width=round(8 * k))
    d.polygon([(4 * k, 22 * k), (22 * k, 4 * k), (31 * k, 13 * k), (13 * k, 31 * k)], fill=255)


def paint_niva(sk):
    """USSR works Niva: dark red all over with yellow CCCP lettering, hammer
    and sickle and stars, the export agency name (АВТОЭКСПОРТ) along the
    flanks and bonnet, a white 157 door panel, a black grille with a red star
    and a yellow roof wedge. Shut lines, black sills and arch lips, chrome
    window trim, crew names on the rear glass and gravel dust thrown up
    along the bottom of the body."""
    import random
    rnd = random.Random(157)
    red = rgb(0.66, 0.07, 0.06)
    deep = rgb(0.38, 0.03, 0.03)
    yellow = rgb(1.0, 0.82, 0.1)
    star_red = rgb(0.9, 0.08, 0.06)
    chrome = rgb(0.78, 0.79, 0.8)
    sill = rgb(0.09, 0.08, 0.08)
    base(sk, red)

    def star(c, size, col, mask="body", rotate=0):
        emblem(sk, star_shape, c, size, col, mask, rotate)

    def sickle(c, size, col, mask="body", rotate=0):
        emblem(sk, hammer_sickle_shape, c, size, col, mask, rotate)

    wheels = (1.12, -1.08)
    for side in (-1, 1):
        piece = "side_r" if side > 0 else "side_l"
        # black sill and wheel arch lips, chrome trim under the side glass,
        # a crease line along the flank
        sk.side_box(side, 1.9, -1.9, 0.38, 0.5, sill)
        for wy in wheels:
            a, b = sk.side_pt(side, wy - 0.53, 0.36 + 0.53), sk.side_pt(side, wy + 0.53, 0.36 - 0.53)
            box = (min(a[0], b[0]), min(a[1], b[1]), max(a[0], b[0]), max(a[1], b[1]))
            sk.paint(lambda d, box=box: d.ellipse(box, outline=sill, width=4))
        sk.side_box(side, 0.62, -1.5, 1.0, 1.012, chrome)
        sk.side_box(side, 1.85, -1.85, 0.86, 0.872, deep)
        # shut lines: bonnet edge, door front, rear and bottom, fuel flap
        sk.side_box(side, 0.62, 0.607, 0.5, 1.02, deep)
        sk.side_box(side, -0.48, -0.493, 0.5, 1.02, deep)
        sk.side_box(side, 0.62, -0.48, 0.5, 0.513, deep)
        sk.side_box(side, 1.85, 0.62, 0.99, 1.0, deep)
        sk.side_box(side, -1.5, -1.62, 0.9, 0.98, deep)
        for i in range(3):  # cabin vent slots in the C-pillar
            z = 1.22 + i * 0.07
            sk.side_box(side, -1.5, -1.6, z, z + 0.025, deep)
        sk.side_box(side, -1.51, -1.61, 0.91, 0.97, rgb(0.55, 0.06, 0.05))
        sk.side_box(side, -0.3, -0.32, 0.88, 0.9, chrome)  # door lock
        # big CCCP along the door with the white 157 panel in front of it
        sk.text("CCCP", sk.side_pt(side, -0.3 + 0.012 * side, 0.688), 21, deep, bold=True)  # drop shadow
        sk.text("CCCP", sk.side_pt(side, -0.3, 0.7), 21, yellow, bold=True)
        sk.side_box(side, 0.21, 0.65, 0.555, 0.845, BLACK)
        sk.side_box(side, 0.225, 0.635, 0.57, 0.83, WHITE)
        sk.text("157", sk.side_pt(side, 0.43, 0.7), 14, BLACK, bold=True)
        # export agency over the rear wheel, emblems front and back, the
        # maker's badge on the front wing
        sk.text("АВТОЭКСПОРТ", sk.side_pt(side, -0.82, 0.93), 7, yellow, bold=True)
        star(sk.side_pt(side, 1.62, 0.76), 0.2 * sk.s, yellow)
        sk.text("ЛАДА", sk.side_pt(side, 1.0, 0.93), 7, chrome)
        sickle(sk.side_pt(side, -1.68, 0.72), 0.2 * sk.s, yellow)
        # small stickers ahead of the rear wheel
        for i, col in enumerate((yellow, WHITE, rgb(0.1, 0.3, 0.75))):
            yy = -0.52 - i * 0.12
            sk.side_box(side, yy, yy - 0.1, 0.43 + 0.13, 0.48 + 0.13, col)
        # crew names along the top of the rear side glass, emblem under them
        sk.text("Б.ПИКСЕЛОВ", sk.side_pt(side, -0.98, 1.47), 7, WHITE, "glass")
        sk.text("А.БАЙТОВ", sk.side_pt(side, -0.98, 1.37), 7, WHITE, "glass")
        sickle(sk.side_pt(side, -0.98, 1.18), 0.18 * sk.s, yellow, "glass")
        # the roof wedge: yellow with a red star on each cheek, roof gutter
        sk.side_box(side, -1.25, -2.05, 1.635, 1.85, yellow)
        star(sk.side_pt(side, -1.82, 1.72), 9, star_red)

    # top: hammer and sickle, CCCP and the export agency on the bonnet,
    # reading from in front; a big star on the roof; the yellow wedge with
    # CCCP and a red star, reading from behind
    for sx in (-1, 1):
        sk.top_box(sx * 0.7, sx * 0.715, 1.85, 0.62, deep)  # bonnet shut lines
        sk.top_box(sx * 0.6, sx * 0.62, 0.2, -1.3, deep)  # roof gutters
    sk.top_box(-0.7, 0.7, 1.85, 1.835, deep)
    sk.top_box(-0.28, 0.28, 0.66, 0.64, sill)  # scuttle vent
    sickle(sk.px("top", (0.0, 1.6, 0)), 0.3 * sk.s, yellow, rotate=90)
    sk.text("CCCP", sk.px("top", (0.0, 1.27, 0)), 14, yellow, rotate=90, bold=True)
    sk.text("АВТОЭКСПОРТ", sk.px("top", (0.0, 0.92, 0)), 7, yellow, rotate=90, bold=True)
    star(sk.px("top", (0.0, -0.55, 0)), 0.58 * sk.s, deep, rotate=-90)
    star(sk.px("top", (0.0, -0.55, 0)), 0.55 * sk.s, yellow, rotate=-90)
    sk.top_box(-1.0, 1.0, -1.28, -2.2, yellow)
    sk.top_box(-1.0, 1.0, -1.28, -1.31, rgb(0.85, 0.65, 0.05))
    sk.text("CCCP", sk.px("top", (0.18, -1.68, 0)), 7, star_red, rotate=-90, bold=True)
    star(sk.px("top", (-0.42, -1.68, 0)), 12, star_red, rotate=-90)

    # front: black grille right across between the round lamps, chrome
    # slats and badge, a red star in the middle, amber indicators, a white
    # ЛАДА 4X4 plate on the bumper and a black lower valance
    sk.end_box(True, -0.74, 0.74, 0.7, 0.94, BLACK)
    sk.end_box(True, -0.42, 0.42, 0.93, 0.94, chrome)
    for i in range(5):
        z = 0.73 + i * 0.04
        sk.end_box(True, -0.42, 0.42, z, z + 0.012, GREY)
    for i in range(9):
        x = -0.4 + i * 0.1
        sk.end_box(True, x, x + 0.012, 0.72, 0.92, rgb(0.15, 0.15, 0.16))
    sk.end_box(True, -0.08, 0.08, 0.75, 0.89, BLACK)
    star(sk.px("front", (0, 0, 0.82)), 10, star_red)
    for s_ in (-1, 1):
        sk.end_box(True, s_ * 0.48, s_ * 0.7, 0.635, 0.685, BLACK)
        sk.end_box(True, s_ * 0.5, s_ * 0.68, 0.645, 0.675, AMBER)
    sk.end_box(True, -0.36, 0.36, 0.41, 0.5, BLACK)
    sk.end_box(True, -0.35, 0.35, 0.415, 0.495, WHITE)
    sk.text("ЛАДА 4X4", sk.px("front", (0, 0, 0.455)), 7, BLACK, bold=True)
    sk.end_box(True, -1.0, 1.0, 0.3, 0.4, sill)
    sk.end_box(True, -1.0, 1.0, 1.62, 1.85, yellow)

    # rear: tailgate shut lines and badge, CCCP across it, a dark recess for
    # the lamp clusters (geometry) and the plate, a black bumper with a
    # ribbed rubber strip, the wedge's yellow edge
    for s_ in (-1, 1):
        sk.end_box(False, s_ * 0.73, s_ * 0.745, 0.58, 1.565, deep)
    sk.end_box(False, -0.745, 0.745, 0.575, 0.59, deep)
    sk.end_box(False, -0.8, 0.8, 1.555, 1.57, deep)  # seam between the roof and the tailgate
    sk.text("CCCP", sk.px("rear", (0.012, 0, 0.938)), 14, deep, bold=True)  # drop shadow
    sk.text("CCCP", sk.px("rear", (0, 0, 0.95)), 14, yellow, bold=True)
    sk.text("НИВА", sk.px("rear", (0.52, 0, 0.81)), 7, chrome)
    sk.end_box(False, -0.8, 0.8, 0.6, 0.76, sill)
    sk.end_box(False, -0.29, 0.29, 0.605, 0.745, chrome)
    sk.end_box(False, -0.28, 0.28, 0.615, 0.735, WHITE)
    sk.text("88-44", sk.px("rear", (0, 0, 0.675)), 7, BLACK, bold=True)
    sk.end_box(False, -1.0, 1.0, 0.0, 0.58, sill)
    for i in range(3):
        z = 0.47 + i * 0.03
        sk.end_box(False, -0.95, 0.95, z, z + 0.012, rgb(0.2, 0.2, 0.21))
    sk.end_box(False, -0.2, 0.2, 0.43, 0.56, GREY)
    sk.end_box(False, -1.0, 1.0, 1.62, 1.85, yellow)
    sk.text("CCCP", sk.px("rear", (0, 0, 1.72)), 7, star_red, "any", bold=True)

    # sun strip: CCCP and the export agency in white on red
    x0, y0, x1, y1 = sk.rect("screen")
    sk.box((x0, y0), (x1, y0 + 0.15 * sk.s), star_red, "glass")
    sk.text("CCCP АВТОЭКСПОРТ", ((x0 + x1) / 2, y0 + 0.075 * sk.s), 7, WHITE, "glass", bold=True)

    # gravel dust: speckles thickest along the sills and round the arches,
    # thinning out up the doors, and over the lower tail and nose
    dust = (rgb(0.52, 0.42, 0.3), rgb(0.4, 0.32, 0.23), rgb(0.62, 0.52, 0.38))

    def dirt(piece, height_at, arch_at=lambda x, y: 0.0, top=0.75):
        x0, y0, x1, y1 = sk.rect(piece)
        m = sk.body.load()
        px = sk.img.load()
        for y in range(y0, y1):
            for x in range(x0, x1):
                if not m[x, y]:
                    continue
                z = height_at(x - x0, y - y0)
                p = max(min((top - z) / (top - 0.4), 1.0), 0.0) ** 1.8 * 0.45 + arch_at(x - x0, y - y0)
                if rnd.random() < p:
                    c = dust[rnd.randrange(3)]
                    o = px[x, y]
                    px[x, y] = tuple((o[i] + c[i]) // 2 for i in range(3)) + (255,)
    for side in (-1, 1):
        piece = "side_r" if side > 0 else "side_l"
        o = sk.L["pieces"][piece]["origin"]
        u = sk.L["pieces"][piece]["u"][1]

        def arch(x, y, o=o, u=u):
            wy = o[1] + (x + 0.5) / sk.s * u
            z = o[2] - (y + 0.5) / sk.s
            r = min(math.hypot(wy - w, z - 0.36) for w in wheels)
            return 0.25 * max(0.0, 1.0 - (r - 0.46) / 0.1) if r > 0.44 else 0.0
        dirt(piece, lambda x, y, o=o: o[2] - (y + 0.5) / sk.s, arch)
    for piece in ("front", "rear"):
        dirt(piece, lambda x, y: 1.85 - (y + 0.5) / sk.s, top=0.5)

    finish(sk, wheels=wheels, hub=0.36, arch=0.46, belt=1.0)


# --------------------------------------------------------------------------- the police car

def paint_cavalier(sk):
    """Black-and-white county sheriff's sedan: black nose, bonnet, boot and
    rear quarters, white doors and roof. Gold six-point star on the front
    doors with POLICE under it, SHERIFF on the front wings, 911 on the rear
    quarters, POLICE across the boot."""
    black = rgb(0.06, 0.06, 0.07)
    gold = rgb(0.95, 0.74, 0.2)
    dark_gold = rgb(0.62, 0.44, 0.1)
    seam = rgb(0.55, 0.56, 0.58)
    base(sk, WHITE)

    def belt(y):  # the beltline of the profile in build_cars.py
        return lerp(0.83, 0.86, min(max((1.6 - y) / 0.68, 0.0), 1.0)) if y > 0.0 else 0.9

    def star(c, r):
        """Sheriff's star: six points with a ball on each tip, darker middle."""
        pts = []
        for i in range(12):
            a = math.pi * i / 6 - math.pi / 2
            k = r if i % 2 == 0 else r * 0.52
            pts.append((c[0] + k * math.cos(a), c[1] + k * math.sin(a)))
        sk.paint(lambda d: d.polygon(pts, fill=gold))
        for i in range(0, 12, 2):
            sk.disc(pts[i], 1.3, gold)
        sk.disc(c, r * 0.36, dark_gold)
        sk.disc(c, r * 0.18, gold)

    for side in (-1, 1):
        piece = "side_r" if side > 0 else "side_l"
        o = sk.L["pieces"][piece]["origin"]
        u = sk.L["pieces"][piece]["u"][1]
        x0, y0, x1, y1 = sk.rect(piece)

        def two_tone(d, o=o, u=u, x0=x0, y0=y0, x1=x1, y1=y1):
            for px in range(x0, x1):
                wy = o[1] + (px - x0 + 0.5) / sk.s * u
                if -1.02 < wy < 0.86:
                    continue  # the doors stay white
                # the wings, bonnet and boot edges are black all the way up;
                # the C-pillar above the rear quarter stays white
                _, top = sk.side_pt(side, wy, belt(wy) + 0.01 if wy > -1.45 and wy < 0.0 else 1.6)
                d.line((px, round(top), px, y1), fill=black)
        sk.paint(two_tone)
        # shut lines, handles, fuel filler behind the rear door
        for dy in (0.86, -0.36, -1.02):
            sk.side_box(side, dy + 0.007, dy - 0.007, 0.3, 0.9, seam)
        for hy in (0.0, -0.9):
            sk.side_box(side, hy, hy - 0.12, 0.78, 0.8, GREY)
        sk.side_box(side, -1.6, -1.72, 0.74, 0.82, rgb(0.14, 0.14, 0.15))
        # chrome strip along the sill, side marker lamps at the corners
        sk.side_box(side, 2.35, -2.35, 0.3, 0.315, rgb(0.7, 0.7, 0.72))
        sk.side_box(side, 2.3, 2.18, 0.58, 0.63, AMBER)
        sk.side_box(side, -2.2, -2.32, 0.58, 0.63, RED)
        # the star and POLICE on the front door, SHERIFF on the wing, 911 behind
        star(sk.side_pt(side, 0.42, 0.66), 0.13 * sk.s)
        sk.text("POLICE", sk.side_pt(side, 0.42, 0.47), 7, black, bold=True)
        sk.text("SHERIFF", sk.side_pt(side, 1.5, 0.62), 7, WHITE, bold=True)
        sk.text("911", sk.side_pt(side, -1.95, 0.76), 7, WHITE, bold=True)
        sk.text("CO 12", sk.side_pt(side, -0.7, 0.66), 7, black)

    # top: black bonnet and boot, white roof; unit number on the roof for
    # the helicopter, POLICE across the boot reading from behind
    sk.top_box(-1.0, 1.0, 2.5, 0.5, black)
    sk.top_box(-1.0, 1.0, -1.45, -2.5, black)
    # the strip under the back window belongs to the boot; the roof edges
    # either side of it (the C-pillar tops) stay white down to the deck
    sk.top_box(-0.6, 0.6, -0.95, -1.45, black)
    c = sk.px("top", (0.0, -0.55, 0))
    sk.text("12", c, 14, black, rotate=-90, bold=True)
    sk.text("POLICE", sk.px("top", (0.0, -1.95, 0)), 14, WHITE, rotate=-90, bold=True)

    # front: all black behind the chrome grille and lamps (geometry), amber
    # turn signals outboard of the headlamps
    sk.end_box(True, -1.0, 1.0, 0.0, 1.6, black)
    for s_ in (-1, 1):
        sk.end_box(True, s_ * 0.775, s_ * 0.86, 0.56, 0.71, AMBER)
        sk.end_box(True, s_ * 0.79, s_ * 0.845, 0.68, 0.695, rgb(1.0, 0.8, 0.45))

    # rear: POLICE across the boot lid, red tail lights at the corners, the
    # plate between them
    sk.end_box(False, -1.0, 1.0, 0.0, 1.6, black)
    for s_ in (-1, 1):  # the back faces of the white C-pillars, above the boot
        sk.end_box(False, s_ * 0.6, s_ * 1.0, 0.97, 1.6, WHITE)
    sk.text("POLICE", sk.px("rear", (0, 0, 0.765)), 14, WHITE, bold=True)
    for s_ in (-1, 1):
        sk.end_box(False, s_ * 0.5, s_ * 0.87, 0.52, 0.66, rgb(0.3, 0.3, 0.32))
        sk.end_box(False, s_ * 0.52, s_ * 0.85, 0.535, 0.645, RED)
        sk.end_box(False, s_ * 0.54, s_ * 0.83, 0.62, 0.63, rgb(1.0, 0.45, 0.4))
        sk.end_box(False, s_ * 0.68, s_ * 0.69, 0.535, 0.645, rgb(0.45, 0.04, 0.03))
    sk.end_box(False, -0.29, 0.29, 0.52, 0.66, rgb(0.3, 0.3, 0.32))
    sk.end_box(False, -0.28, 0.28, 0.53, 0.65, WHITE)
    sk.end_box(False, -0.28, 0.28, 0.53, 0.55, rgb(0.1, 0.2, 0.55))
    sk.text("PD 12", sk.px("rear", (0, 0, 0.598)), 7, rgb(0.1, 0.2, 0.55))

    finish(sk, wheels=(1.45, -1.4))


# --------------------------------------------------------------------------- the raid car

def paint_degaulle(sk):
    """Works desert-raid yellow: red, white and blue tricolour stripes running
    diagonally down from the A-pillar across the front door into a blue sill
    stripe, white 203 number panels, big blue cigarette-style lettering on the
    rear doors and bonnet, a red oil-company panel on the nose and a sponsor
    disc on each wing end plate (made-up DROMA, ORPIX, PIXELIN, PIXTRONIC)."""
    yellow = rgb(1.0, 0.8, 0.05)
    shut = rgb(0.62, 0.48, 0.04)
    blue = rgb(0.08, 0.2, 0.62)
    navy = rgb(0.06, 0.12, 0.4)
    base(sk, yellow)

    for side in (-1, 1):
        # tricolour: three slanted bands from the screen base down across the
        # front door, the blue one running on back along the sill
        for i, col in enumerate((RED, WHITE, blue)):
            ya, yb = 1.0 - i * 0.085, 0.92 - i * 0.085  # band edges at the top
            drop = 0.56  # how far back each band runs on its way down
            pts = [sk.side_pt(side, ya, 0.97), sk.side_pt(side, yb, 0.97),
                   sk.side_pt(side, yb - drop, 0.4), sk.side_pt(side, ya - drop, 0.4)]
            sk.paint(lambda d, pts=pts, col=col: d.polygon(pts, fill=col))
        sk.side_box(side, 0.3, -0.92, 0.4, 0.475, blue)
        # shut lines, fuel cap
        for dy in (0.96, -0.2, -0.95):
            sk.side_box(side, dy, dy - 0.013, 0.4, 1.0, shut)
        sk.side_box(side, -1.62, -1.72, 0.92, 0.98, shut)
        # number panel across the front door shut line, under a black sponsor header
        sk.side_box(side, 0.19, -0.39, 0.55, 0.95, BLACK)
        sk.side_box(side, 0.18, -0.38, 0.56, 0.94, WHITE)
        sk.side_box(side, 0.18, -0.38, 0.84, 0.94, BLACK)
        sk.text("PIXTRON", sk.side_pt(side, -0.1, 0.89), 7, WHITE)
        sk.text("203", sk.side_pt(side, -0.1, 0.7), 14, BLACK, bold=True)
        # the big name over the rear door, clear of the arch, stickers under it
        sk.text("DROMA", sk.side_pt(side, -0.87, 0.86), 14, navy, bold=True)
        for i, col in enumerate((RED, WHITE, blue, BLACK)):
            yy = -0.5 - i * 0.13
            sk.side_box(side, yy, yy - 0.11, 0.6, 0.65, col)
        sk.text("PIXELIN", sk.side_pt(side, -1.75, 1.0), 7, navy, bold=True)
        sk.text("ORPIX", sk.side_pt(side, 1.75, 0.75), 7, RED, bold=True)
        # wing end plates: black, with the oil company's disc
        sk.side_box(side, -1.6, -2.26, 1.14, 1.8, BLACK)
        c = sk.side_pt(side, -2.02, 1.55)
        sk.disc(c, 0.13 * sk.s, blue)
        sk.disc(c, 0.115 * sk.s, WHITE)
        sk.text("ORPIX", c, 7, RED, bold=True)
        # crew names on the rear side windows
        sk.text("J PIX", sk.side_pt(side, -0.55, 1.28), 7, WHITE, "glass")

    # top: oil panel across the nose, the name on the bonnet reading from in
    # front, tricolour over the screen base, name on the boot under the wing
    sk.top_box(-0.5, 0.5, 1.92, 2.14, RED)
    sk.text("ORPIX", sk.px("top", (0.0, 2.03, 0)), 7, WHITE, rotate=90, bold=True)
    sk.text("DROMA", sk.px("top", (0.0, 1.5, 0)), 14, navy, rotate=90, bold=True)
    sk.top_box(-0.24, 0.24, 1.18, 1.0, WHITE)
    sk.text("203", sk.px("top", (0.0, 1.09, 0)), 7, BLACK, rotate=90, bold=True)
    for sx in (-1, 1):
        for i, col in enumerate((RED, WHITE, blue)):
            x = sx * (0.6 + i * 0.07)
            sk.top_box(x, x + sx * 0.07, 1.06, 0.9, col)
    sk.text("DROMA", sk.px("top", (0.0, -1.9, 0)), 7, navy, rotate=-90, bold=True)

    # front: rectangular headlamps and a slim grille under the bonnet edge,
    # amber corners, black intake and the plate on the lifted bumper
    sk.end_box(True, -0.26, 0.26, 0.7, 0.77, BLACK)
    for i in range(3):
        z = 0.715 + i * 0.02
        sk.end_box(True, -0.24, 0.24, z, z + 0.007, GREY)
    sk.disc(sk.px("front", (0, 0, 0.735)), 3, rgb(0.78, 0.8, 0.83))
    for s_ in (-1, 1):
        sk.end_box(True, s_ * 0.29, s_ * 0.71, 0.68, 0.8, BLACK)
        sk.end_box(True, s_ * 0.31, s_ * 0.6, 0.69, 0.79, rgb(1.0, 0.98, 0.86))
        sk.end_box(True, s_ * 0.62, s_ * 0.69, 0.69, 0.79, AMBER)
        sk.text("PIX", sk.px("front", (s_ * 0.72, 0, 0.57)), 7, navy)
    sk.end_box(True, -0.55, 0.55, 0.36, 0.5, BLACK)
    for i in range(5):
        z = 0.38 + i * 0.024
        sk.end_box(True, -0.53, 0.53, z, z + 0.008, GREY)
    sk.end_box(True, -0.24, 0.24, 0.53, 0.61, WHITE)
    sk.text("DG 203", sk.px("front", (0, 0, 0.57)), 7, BLACK, bold=True)
    for s_ in (-1, 1):
        sk.end_box(True, s_ * 0.78, s_ * 0.86, 1.15, 1.8, BLACK)

    # rear: black panel between the tail lights, yellow plate on the bumper,
    # end plate edges black
    for s_ in (-1, 1):
        sk.end_box(False, s_ * 0.5, s_ * 0.88, 0.74, 0.94, BLACK)
        sk.end_box(False, s_ * 0.52, s_ * 0.86, 0.82, 0.92, RED)
        sk.end_box(False, s_ * 0.54, s_ * 0.84, 0.895, 0.91, rgb(1.0, 0.45, 0.4))
        sk.end_box(False, s_ * 0.52, s_ * 0.86, 0.76, 0.81, AMBER)
        sk.text("PIX", sk.px("rear", (s_ * 0.72, 0, 0.6)), 7, navy)
    sk.end_box(False, -0.5, 0.5, 0.74, 0.94, BLACK)
    sk.text("DE GAULLE", sk.px("rear", (0, 0, 0.84)), 7, rgb(0.78, 0.8, 0.83), bold=True)
    sk.end_box(False, -0.26, 0.26, 0.52, 0.62, BLACK)
    sk.end_box(False, -0.24, 0.24, 0.53, 0.61, YELLOW)
    sk.text("DG 203", sk.px("rear", (0, 0, 0.57)), 7, BLACK, bold=True)
    sk.end_box(False, -0.95, 0.95, 0.0, 0.46, rgb(0.08, 0.08, 0.09))
    sk.end_box(False, -1.0, 1.0, 1.13, 1.8, BLACK)

    sun_strip(sk, "DROMA  203", blue, YELLOW)
    finish(sk, wheels=(1.38, -1.32))


# --------------------------------------------------------------------------- the Lancer

def paint_lancer(sk):
    """Late-90s works Lancer in tobacco red: a big white chevron over the
    bonnet running down onto the front wings, the same chevron logo on the
    rear doors, wing end plates and the top of the wing, white number 2
    panels on the front doors, a white strip along the rear valance and
    yellow fog lamps (made-up MARLOW, RALLIPIX, KARISMO, SOLPIX, PIXELIN)."""
    red = rgb(0.85, 0.07, 0.07)
    shut = rgb(0.55, 0.04, 0.04)
    fog = rgb(1.0, 0.86, 0.15)
    base(sk, red)

    def logo(pts, w, h, text=True):
        """Chevron pack logo in a box given by its four corners (top-left,
        top-right, bottom-right, bottom-left in skin pixels): white with the
        red roof across its top, the name under it."""
        (ax, ay), (bx, by), (cx, cy), (dx, dy) = pts
        sk.paint(lambda d: d.polygon(pts, fill=WHITE))

        def at(u, v):  # u across, v down, both 0..1
            return (lerp(lerp(ax, bx, u), lerp(dx, cx, u), v), lerp(lerp(ay, by, u), lerp(dy, cy, u), v))
        roof = [at(0, 0), at(1, 0), at(1, 0.55), at(0.5, 0.2), at(0, 0.55)]
        sk.paint(lambda d: d.polygon(roof, fill=red))
        if text:
            c = at(0.5, 0.77)
            sk.text("MARLOW", c, h, BLACK)

    for side in (-1, 1):
        # the bonnet chevron runs down over the nose and back along the front
        # wing as a white wedge, then a thin line to the front door
        pts = [sk.side_pt(side, 2.25, 0.84), sk.side_pt(side, 2.25, 0.62), sk.side_pt(side, 1.72, 0.64),
               sk.side_pt(side, 0.98, 0.8), sk.side_pt(side, 0.98, 0.86)]
        sk.paint(lambda d, pts=pts: d.polygon(pts, fill=WHITE))
        sk.side_box(side, 0.98, 0.5, 0.82, 0.845, WHITE)
        # shut lines, handles, fuel cap
        for dy in (0.98, -0.33, -1.15):
            sk.side_box(side, dy, dy - 0.013, 0.3, 0.92, shut)
        for hy in (-0.2, -0.98):
            sk.side_box(side, hy, hy + 0.11, 0.8, 0.82, BLACK)
        sk.side_box(side, -1.5, -1.6, 0.8, 0.86, shut)
        # number panel on the front door, the paint sponsor along its foot
        sk.side_box(side, 0.78, 0.18, 0.44, 0.82, BLACK)
        sk.side_box(side, 0.77, 0.19, 0.45, 0.81, WHITE)
        sk.text("2", sk.side_pt(side, 0.48, 0.69), 14, BLACK, bold=True)
        sk.text("SOLPIX", sk.side_pt(side, 0.48, 0.51), 7, BLACK, bold=True)
        # the pack logo on the rear door, works names on the quarter
        a, b = sk.side_pt(side, -0.37, 0.89), sk.side_pt(side, -0.86, 0.89)
        c, d = sk.side_pt(side, -0.86, 0.47), sk.side_pt(side, -0.37, 0.47)
        logo([a, b, c, d], abs(b[0] - a[0]), 7)
        sk.side_box(side, -1.38, -2.0, 0.855, 0.935, WHITE)
        sk.text("RALLIPIX", sk.side_pt(side, -1.69, 0.895), 7, BLACK, bold=True)
        sk.text("KARISMO", sk.side_pt(side, -1.69, 0.8), 7, WHITE, bold=True)
        # stickers behind the front wheel and on the rear bumper, tyre maker
        for i, col in enumerate((WHITE, BLACK, WHITE, rgb(0.1, 0.2, 0.6))):
            z = 0.7 - i * 0.075
            sk.side_box(side, 0.95, 0.83, z, z - 0.06, col)
        sk.side_box(side, 0.1, -0.68, 0.33, 0.41, BLACK)
        sk.text("PIXELIN", sk.side_pt(side, -0.29, 0.37), 7, WHITE)
        # crew names on the rear side windows
        sk.text("PIXINEN", sk.side_pt(side, -0.72, 1.12), 7, WHITE, "glass")
        sk.text("BYTEINEN", sk.side_pt(side, -0.72, 1.03), 7, WHITE, "glass")
        # wing end plates: the logo again, no room for the name
        a, b = sk.side_pt(side, -1.76, 1.37), sk.side_pt(side, -2.08, 1.37)
        c, d = sk.side_pt(side, -2.08, 1.12), sk.side_pt(side, -1.76, 1.12)
        logo([a, b, c, d], abs(b[0] - a[0]), 7, text=False)

    # top: the chevron over the bonnet (white, peaking back towards the
    # screen), the name across it reading from in front; roof number; the
    # logo on the wing reading from behind
    pts = [sk.px("top", (x, y, 0)) for x, y in ((-1.0, 2.3), (1.0, 2.3), (1.0, 1.55), (0.0, 1.08), (-1.0, 1.55))]
    sk.paint(lambda d: d.polygon(pts, fill=WHITE))
    sk.text("MARLOW", sk.px("top", (0.0, 1.85, 0)), 14, red, rotate=90, bold=True)
    c = sk.px("top", (0.0, -0.45, 0))
    sk.box((c[0] - 10, c[1] - 10), (c[0] + 10, c[1] + 10), BLACK)
    sk.box((c[0] - 9, c[1] - 9), (c[0] + 9, c[1] + 9), WHITE)
    sk.text("2", c, 14, BLACK, rotate=-90, bold=True)
    sk.top_box(-0.62, 0.62, -1.86, -2.1, WHITE)
    roof = [sk.px("top", (x, y, 0)) for x, y in ((-0.62, -1.86), (0.62, -1.86), (0.62, -1.99), (0.0, -1.9), (-0.62, -1.99))]
    sk.paint(lambda d: d.polygon(roof, fill=red))
    sk.text("MARLOW", sk.px("top", (0.0, -2.04, 0)), 7, BLACK, rotate=-90, bold=True)

    # front: white bonnet edge, wide headlamps either side of a slim black
    # grille, a deep bumper with a big middle intake and side intakes
    # carrying the yellow fog lamps, tyre maker on the lip
    sk.end_box(True, -1.0, 1.0, 0.7, 0.9, WHITE)
    sk.end_box(True, -0.26, 0.26, 0.58, 0.68, BLACK)
    for i in range(3):
        z = 0.6 + i * 0.025
        sk.end_box(True, -0.24, 0.24, z, z + 0.009, GREY)
    for s_ in (-1, 1):
        sk.end_box(True, s_ * 0.29, s_ * 0.78, 0.58, 0.7, BLACK)
        sk.end_box(True, s_ * 0.31, s_ * 0.6, 0.595, 0.685, rgb(1.0, 0.98, 0.86))
        sk.end_box(True, s_ * 0.62, s_ * 0.76, 0.595, 0.685, rgb(0.9, 0.9, 0.86))
        sk.end_box(True, s_ * 0.66, s_ * 0.8, 0.5, 0.54, AMBER)
        sk.end_box(True, s_ * 0.52, s_ * 0.82, 0.26, 0.44, BLACK)
        sk.disc(sk.px("front", (s_ * 0.67, 0, 0.35)), 0.07 * sk.s, GREY)
        sk.disc(sk.px("front", (s_ * 0.67, 0, 0.35)), 0.058 * sk.s, fog)
    sk.end_box(True, -0.46, 0.46, 0.25, 0.47, BLACK)
    for i in range(7):
        z = 0.27 + i * 0.027
        sk.end_box(True, -0.44, 0.44, z, z + 0.009, GREY)
    sk.end_box(True, -0.95, 0.95, 0.19, 0.23, BLACK)
    sk.end_box(True, -0.3, 0.3, 0.48, 0.565, BLACK)
    sk.text("PIXELIN", sk.px("front", (0, 0, 0.523)), 7, WHITE)

    # rear: white band across the boot lid with the name, wide red tail lights
    # with amber inners, plate in a black recess, white valance strip
    sk.end_box(False, -0.62, 0.62, 0.86, 0.97, WHITE)
    sk.text("MARLOW", sk.px("rear", (0, 0, 0.915)), 7, BLACK, bold=True)
    for s_ in (-1, 1):
        # the lenses are brighter than the paint so they read against it
        sk.end_box(False, s_ * 0.38, s_ * 0.88, 0.69, 0.86, BLACK)
        sk.end_box(False, s_ * 0.6, s_ * 0.86, 0.71, 0.84, rgb(1.0, 0.22, 0.16))
        sk.end_box(False, s_ * 0.62, s_ * 0.84, 0.81, 0.825, rgb(1.0, 0.6, 0.55))
        sk.end_box(False, s_ * 0.5, s_ * 0.585, 0.71, 0.84, AMBER)
        sk.end_box(False, s_ * 0.4, s_ * 0.485, 0.71, 0.84, rgb(0.88, 0.88, 0.86))
    sk.end_box(False, -0.3, 0.3, 0.58, 0.72, BLACK)
    sk.end_box(False, -0.24, 0.24, 0.6, 0.7, YELLOW)
    sk.text("LE 2", sk.px("rear", (0, 0, 0.65)), 7, BLACK, bold=True)
    sk.end_box(False, -0.3, 0.3, 0.44, 0.52, BLACK)
    sk.text("PIXELIN", sk.px("rear", (0, 0, 0.48)), 7, WHITE)
    sk.end_box(False, -0.95, 0.95, 0.33, 0.39, WHITE)
    sk.end_box(False, -0.95, 0.95, 0.0, 0.33, rgb(0.08, 0.08, 0.09))

    sun_strip(sk, "LANCER EVO", WHITE, red)
    finish(sk)


# --------------------------------------------------------------------------- the Celica

def paint_celica(sk):
    """Works Celica in white oil-company colours: a red swoosh edged in green
    sweeping from the nose along each flank and up over the rear quarter, the
    oil company in white inside it and big on the bonnet, yellow 5 panels on
    the doors and roof, a tiny tricolour on the roof vent (made-up KESTROL,
    TOKYO and PIXELLI)."""
    red = rgb(0.85, 0.07, 0.07)
    green = rgb(0.0, 0.52, 0.22)
    yellow = rgb(1.0, 0.82, 0.08)
    blue = rgb(0.08, 0.2, 0.62)
    shut = rgb(0.7, 0.71, 0.72)
    base(sk, WHITE)

    def swoosh_z(y):
        """Centre height of the swoosh: low along the nose and door, sweeping
        up over the rear wheel to the top of the quarter."""
        return 0.44 + 0.42 * smooth((0.6 - y) / 2.1)

    bands = [(0.075, 0.06, green), (0.055, -0.055, red), (-0.06, -0.08, green)]  # offsets from the centre, top down

    for side in (-1, 1):
        piece = "side_r" if side > 0 else "side_l"
        x0, _, x1, _ = sk.rect(piece)
        o = sk.L["pieces"][piece]["origin"]
        u = sk.L["pieces"][piece]["u"][1]

        def swoosh(d, side=side, x0=x0, x1=x1, o=o, u=u):
            for px in range(x0, x1):
                yy = o[1] + (px - x0 + 0.5) / sk.s * u
                zc = swoosh_z(yy)
                for a, b, col in bands:
                    _, pa = sk.side_pt(side, yy, zc + a)
                    _, pb = sk.side_pt(side, yy, zc + b)
                    d.line((px, round(pa), px, round(pb) - 1), fill=col)
                # a thinner green curve under it, rising from the nose up the front wing
                if yy > 0.85:
                    z2 = 0.38 + 0.3 * smooth((yy - 0.85) / 1.3)
                    _, pa = sk.side_pt(side, yy, z2 + 0.02)
                    _, pb = sk.side_pt(side, yy, z2 - 0.02)
                    d.line((px, round(pa), px, round(pb) - 1), fill=green)
        sk.paint(swoosh)
        # the oil company in white inside the red band along the door
        sk.text("KESTROL", sk.side_pt(side, 0.4, swoosh_z(0.4)), 7, WHITE, bold=True)
        # shut lines, handle, fuel cap
        for dy in (0.86, -0.32):
            sk.side_box(side, dy, dy - 0.013, 0.3, 0.85, shut)
        sk.side_box(side, -0.12, -0.24, 0.76, 0.785, BLACK)
        sk.side_box(side, -1.55, -1.65, 0.8, 0.86, shut)
        # yellow number panel on the door
        sk.side_box(side, 0.46, -0.02, 0.6, 0.81, BLACK)
        sk.side_box(side, 0.45, -0.01, 0.61, 0.8, yellow)
        sk.text("5", sk.side_pt(side, 0.22, 0.705), 14, BLACK, bold=True)
        # maker on the front wing, tyre maker on the sill, stickers behind the front wheel
        sk.text("TOKYO", sk.side_pt(side, 1.45, 0.72), 7, red, bold=True)
        sk.text("PIXELLI", sk.side_pt(side, 0.3, 0.3), 7, BLACK)
        for i, col in enumerate((red, green, BLACK)):
            yy = 0.82 - i * 0.12
            sk.side_box(side, yy, yy - 0.1, 0.35, 0.39, col)
        # driver's name on the rear side window
        sk.text("D PIXOL", sk.side_pt(side, -0.72, 1.02), 7, WHITE, "glass")

    # top: the oil company big on the bonnet reading from in front, green and
    # red curves along the wings, roof number panel, the tricolour on the
    # roof vent, the maker on the ducktail
    sk.text("KESTROL", sk.px("top", (0.0, 1.55, 0)), 14, red, rotate=90, bold=True)
    sk.top_box(-0.3, 0.3, 1.3, 1.25, green)
    for sx in (-1, 1):
        sk.top_box(sx * 0.66, sx * 0.76, 2.2, 0.9, red)
        sk.top_box(sx * 0.62, sx * 0.66, 2.2, 0.9, green)
    c = sk.px("top", (0.0, -0.58, 0))
    sk.box((c[0] - 10, c[1] - 9), (c[0] + 10, c[1] + 9), BLACK)
    sk.box((c[0] - 9, c[1] - 8), (c[0] + 9, c[1] + 8), yellow)
    sk.text("5", c, 14, BLACK, rotate=-90, bold=True)
    for i, col in enumerate((blue, WHITE, RED)):
        x = -0.075 + i * 0.05
        sk.top_box(x, x + 0.05, -0.2, -0.3, col)
    sk.text("TOKYO", sk.px("top", (0.0, -2.02, 0)), 7, red, rotate=-90, bold=True)

    # front: slim lamps on the slope of the nose either side of a narrow
    # grille slot with a red badge, deep bumper with a black intake, amber
    # corners and the swoosh starting across it
    sk.end_box(True, -0.78, 0.78, 0.565, 0.665, BLACK)
    for s_ in (-1, 1):
        sk.end_box(True, s_ * 0.33, s_ * 0.66, 0.58, 0.65, rgb(1.0, 0.98, 0.86))
        sk.end_box(True, s_ * 0.67, s_ * 0.76, 0.58, 0.65, AMBER)
    sk.disc(sk.px("front", (0, 0, 0.615)), 3, red)
    for a, b, col in ((0.475, 0.46, green), (0.46, 0.43, red), (0.43, 0.415, green)):
        sk.end_box(True, -1.0, 1.0, b, a, col)
    sk.end_box(True, -0.5, 0.5, 0.24, 0.39, BLACK)
    for i in range(5):
        z = 0.26 + i * 0.024
        sk.end_box(True, -0.48, 0.48, z, z + 0.008, GREY)
    sk.end_box(True, -0.95, 0.95, 0.18, 0.23, BLACK)
    sk.text("KESTROL", sk.px("front", (0, 0, 0.205)), 7, WHITE)

    # rear: full-width red tail light bar across the hatch base with the
    # maker in the dark middle, yellow plate on the bumper, black diffuser
    sk.end_box(False, -0.9, 0.9, 0.7, 0.88, BLACK)
    for s_ in (-1, 1):
        sk.end_box(False, s_ * 0.36, s_ * 0.86, 0.72, 0.86, RED)
        sk.end_box(False, s_ * 0.38, s_ * 0.84, 0.83, 0.845, rgb(1.0, 0.45, 0.4))
        sk.end_box(False, s_ * 0.36, s_ * 0.46, 0.72, 0.86, AMBER)
    sk.end_box(False, -0.34, 0.34, 0.73, 0.85, rgb(0.5, 0.06, 0.06))
    sk.text("TOKYO", sk.px("rear", (0, 0, 0.79)), 7, rgb(0.78, 0.8, 0.83), bold=True)
    for a, b, col in ((0.62, 0.6, green), (0.6, 0.56, red), (0.56, 0.54, green)):
        sk.end_box(False, -1.0, 1.0, b, a, col)
    sk.end_box(False, -0.24, 0.24, 0.39, 0.5, YELLOW)
    sk.text("TC 5", sk.px("rear", (0, 0, 0.445)), 7, BLACK, bold=True)
    sk.end_box(False, -0.95, 0.95, 0.0, 0.33, rgb(0.08, 0.08, 0.09))

    sun_strip(sk, "KESTROL", red, WHITE)
    finish(sk, wheels=(1.3, -1.23))


def smooth(t):
    t = min(max(t, 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


PAINTERS = {"martello": paint_martello, "pleiad": paint_pleiad, "veloce": paint_veloce, "balear": paint_balear, "swamp": paint_swamp,
            "bellatrix": paint_bellatrix, "niva": paint_niva, "cavalier": paint_cavalier,
            "degaulle": paint_degaulle, "lancer": paint_lancer, "celica": paint_celica}


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
