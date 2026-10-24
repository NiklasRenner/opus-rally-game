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
    # base coats
    sk.paint(lambda d: d.rectangle((0, 0, sk.size, sk.size), fill=WHITE), "body")
    sk.paint(lambda d: d.rectangle((0, 0, sk.size, sk.size), fill=GLASS), "glass")

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
            sk.side_box(side, yy, yy - 0.11, 0.42, 0.47, col)

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

    # windscreen sun strip and glass glints
    x0, y0, x1, y1 = sk.rect("screen")
    sk.box((x0, y0), (x1, y0 + 0.15 * sk.s), DARK_BLUE, "glass")
    sk.text("PIXEL RACING", ((x0 + x1) / 2, y0 + 0.075 * sk.s), 0.08 * sk.s, WHITE, "glass", bold=True)

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
            for wy0 in (1.32, -1.28):
                r = math.hypot(wy - wy0, z - 0.34)
                if 0.4 < r < 0.52 and z > 0.2:
                    v *= 0.78 + 0.22 * (r - 0.4) / 0.12
            return v
        sk.shade(piece, k)
    for piece in ("front", "rear"):
        sk.shade(piece, lambda x, y: (1.04 - 0.24 * max(abs(x / 80.0 - 1.0) - 0.6, 0.0) / 0.4)
                 * (0.86 + 0.14 * min(max((1.6 - y / 80.0 - 0.2) / 0.5, 0.0), 1.0)))
    sk.shade("top", lambda x, y: 1.02 - 0.12 * max(abs(y / 80.0 - 1.0) - 0.5, 0.0) / 0.5)
    sk.outline_glass(BLACK)
    x0, y0, x1, y1 = sk.rect("under")
    sk.img.paste(rgb(0.08, 0.08, 0.09), (x0, y0, x1, y1))


PAINTERS = {"martello": paint_martello}


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
