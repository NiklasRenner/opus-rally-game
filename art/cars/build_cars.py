"""Builds the low-poly rally cars for Retro Rally in Blender and exports them.

Run inside Blender (Scripting tab, or exec(open(path).read())). Each car is
lofted from side-profile keys like the game's own CarModel, but with more
cross-section points, wheel arches and separate parts that the game can dent
or knock off. Front is +Y, up is +Z and the ground is at z = 0; glTF export
turns that into Godot's -Z forward.

Every painted face gets UVs into a 512x512 skin made of separate panel
pieces (each side, top, front, back, windscreen), each projected straight
onto its own panel. The builder writes <car>_layout.json with every face's
outline in the skin; paint_skin.py paints the pieces from it (or you paint
them by hand) and combines them into models/<car>_skin.png.
"""
import json
import bpy, bmesh, math, os
from mathutils import Vector, Matrix


SKIN = 512  # skin size in pixels for cars painted in pieces
PX_M = 75.0  # skin pixels per metre, unless the car says otherwise (px_m)


def pieces(c):
    """Panel pieces of the skin: pixel rect and the projection onto it. Sides
    and top cover the car's length (2 x half_len), front and back 2 m of
    width, everything 1.6 m of height, at px_m pixels per metre."""
    L, S = c.get("half_len", 2.25), c.get("px_m", PX_M)
    lw, h, w = round(2 * L * S), round(1.6 * S), round(2 * S)
    out = {
        "side_r": dict(rect=[0, 0, lw, h], origin=[0, -L, 1.6], u=[0, 1, 0], v=[0, 0, -1]),
        "side_l": dict(rect=[0, h, lw, h], origin=[0, L, 1.6], u=[0, -1, 0], v=[0, 0, -1]),
        "top": dict(rect=[0, 2 * h, lw, w], origin=[-1.0, -L, 0], u=[0, 1, 0], v=[1, 0, 0]),
        "front": dict(rect=[lw, 0, w, h], origin=[1.0, 0, 1.6], u=[-1, 0, 0], v=[0, 0, -1]),
        "rear": dict(rect=[lw, h, w, h], origin=[-1.0, 0, 1.6], u=[1, 0, 0], v=[0, 0, -1]),
        "under": dict(rect=[496, 496, 16, 16], origin=[0, 0, 0], u=[0, 0, 0], v=[0, 0, 0]),
    }
    if "screen" in c:
        (sy0, sz0), (sy1, sz1) = c["screen"]
        sl = math.hypot(sy1 - sy0, sz1 - sz0)
        down = ((sy0 - sy1) / sl, (sz0 - sz1) / sl)  # from the screen top towards its base
        out["screen"] = dict(rect=[lw, 2 * h, w, round(0.88 * S)], origin=[1.0, sy1, sz1], u=[-1, 0, 0],
                             v=[0, down[0], down[1]])
    return out


def piece_for(n, key):
    if key == "Glass" and n.y > 0.3 and n.z > 0.3:
        return "screen"
    ax = max(range(3), key=lambda i: abs(n[i]))
    if ax == 0:
        return "side_r" if n.x > 0 else "side_l"
    if ax == 2:
        return "top" if n.z > 0 else "under"
    return "front" if n.y > 0 else "rear"


def piece_px(pc, p, s=PX_M):
    r, o, u, v = pc["rect"], pc["origin"], pc["u"], pc["v"]
    d = (p[0] - o[0], p[1] - o[1], p[2] - o[2])
    if not any(u):
        return (r[0] + r[2] / 2, r[1] + r[3] / 2)
    return (r[0] + (d[0] * u[0] + d[1] * u[1] + d[2] * u[2]) * s,
            r[1] + (d[0] * v[0] + d[1] * v[1] + d[2] * v[2]) * s)


def smoothstep(e0, e1, x):
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


# --------------------------------------------------------------------------- materials

def material(name, rgb, rough=0.6, metal=0.0, emit=False):
    """Material "<kind>.<car>"; the game paints by the part before the dot."""
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    b = next(n for n in m.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        for k in ("Emission Color", "Emission"):
            if k in b.inputs:
                b.inputs[k].default_value = (*rgb, 1)
                break
        b.inputs["Emission Strength"].default_value = 1.5
    m.diffuse_color = (*rgb, 1)
    return m


# --------------------------------------------------------------------------- mesh helpers

class G:
    """Collects geometry for one object in world coordinates."""

    def __init__(self):
        self.bm = bmesh.new()
        self.mats = []

    def mi(self, key):
        if key not in self.mats:
            self.mats.append(key)
        return self.mats.index(key)

    def _merge(self, t, key):
        idx = self.mi(key)
        for f in t.faces:
            f.material_index = idx
        me = bpy.data.meshes.new("tmp")
        t.to_mesh(me)
        t.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)

    def hull(self, pts, key):
        t = bmesh.new()
        vs = [t.verts.new(p) for p in pts]
        r = bmesh.ops.convex_hull(t, input=vs)
        bmesh.ops.delete(t, geom=list(dict.fromkeys(r["geom_interior"] + r["geom_unused"])), context="VERTS")
        bmesh.ops.dissolve_limit(t, angle_limit=math.radians(1), verts=t.verts[:], edges=t.edges[:])
        self._merge(t, key)

    def box(self, c, s, key):
        self.hull([(c[0] + sx * s[0] / 2, c[1] + sy * s[1] / 2, c[2] + sz * s[2] / 2)
                   for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], key)

    def cyl(self, c, axis, r, depth, key, segs=12, r2=None):
        t = bmesh.new()
        rot = {"X": Matrix.Rotation(math.pi / 2, 4, "Y"), "Y": Matrix.Rotation(math.pi / 2, 4, "X"),
               "Z": Matrix()}[axis]
        bmesh.ops.create_cone(t, cap_ends=True, segments=segs, radius1=r, radius2=r if r2 is None else r2,
                              depth=depth, matrix=Matrix.Translation(c) @ rot)
        self._merge(t, key)

    def faces(self, verts, faces, keys):
        t = bmesh.new()
        vs = [t.verts.new(v) for v in verts]
        made = []
        for f in faces:
            try:
                made.append(t.faces.new([vs[i] for i in f]))
            except ValueError:
                made.append(None)
        me = bpy.data.meshes.new("tmp")
        for f, k in zip(made, keys):
            if f:
                f.material_index = self.mi(k)
        t.to_mesh(me)
        t.free()
        self.bm.from_mesh(me)
        bpy.data.meshes.remove(me)


class Builder:
    def __init__(self, coll, c=None):
        self.col = coll
        self.world = {}
        self.pieces = pieces(c) if c else None
        self.px_m = c.get("px_m", PX_M) if c else PX_M
        self.layout = []  # painted faces: piece, material, outline in skin pixels

    def make(self, name, g, origin, parent=None, mats=None):
        origin = Vector(origin)
        bmesh.ops.remove_doubles(g.bm, verts=g.bm.verts[:], dist=1e-5)
        bmesh.ops.recalc_face_normals(g.bm, faces=g.bm.faces[:])
        self.uv(g, origin)
        bmesh.ops.translate(g.bm, vec=-origin, verts=g.bm.verts[:])
        me = bpy.data.meshes.new(name)
        g.bm.to_mesh(me)
        g.bm.free()
        for k in g.mats:
            me.materials.append(mats[k])
        ob = bpy.data.objects.new(name, me)
        self.col.objects.link(ob)
        self.place(ob, origin, parent)
        return ob

    def uv(self, g, origin):
        lay = g.bm.loops.layers.uv.verify()
        for f in g.bm.faces:
            key = g.mats[f.material_index]
            n = f.normal
            if key == "Rim":  # disc across the wheel face, centred on the hub
                c = f.calc_center_median()
                r = max((v.co - c).length for v in f.verts)
                for l in f.loops:
                    d = l.vert.co - c
                    s = 1.0 if n.x > 0 else -1.0
                    l[lay].uv = (0.5 + s * d.y / (2 * r), 0.5 + d.z / (2 * r))
                continue
            if key == "Tyre":  # tread runs round the tyre
                for l in f.loops:
                    d = l.vert.co - origin
                    l[lay].uv = (math.atan2(d.z, d.y) / math.tau * 8, d.x * 4)
                continue
            if self.pieces:
                piece = piece_for(n, key)
                pts = [piece_px(self.pieces[piece], l.vert.co, self.px_m) for l in f.loops]
                for l, (px, py) in zip(f.loops, pts):
                    l[lay].uv = (px / SKIN, 1.0 - py / SKIN)
                if key in ("Livery", "Glass"):
                    self.layout.append({"piece": piece, "mat": key, "poly": [[round(x, 2), round(y, 2)] for x, y in pts]})


    def place(self, ob, origin, parent):
        self.world[ob.name] = Vector(origin)
        if parent:
            ob.parent = parent
            ob.location = Vector(origin) - self.world[parent.name]
        else:
            ob.location = origin

    def empty(self, name, origin, parent=None, size=0.5):
        ob = bpy.data.objects.new(name, None)
        ob.empty_display_size = size
        self.col.objects.link(ob)
        self.place(ob, origin, parent)
        return ob


# --------------------------------------------------------------------------- the body

class Body:
    """Side profile + plan of one car (Blender space, front +Y)."""

    def __init__(self, c):
        self.c = c

    def keys(self):
        return self.c["profile"]  # (y, top, belt) front to back

    def profile(self, y):
        k = self.keys()
        if y >= k[0][0]:
            return k[0][1], k[0][2]
        for a, b in zip(k, k[1:]):
            if y >= b[0]:
                t = (a[0] - y) / (a[0] - b[0])
                return lerp(a[1], b[1], t), lerp(a[2], b[2], t)
        return k[-1][1], k[-1][2]

    def front(self):
        return self.keys()[0][0]

    def rear(self):
        return self.keys()[-1][0]

    def arch_r(self):
        return self.c["wheel_r"] + 0.07

    def half_width(self, y, flares=True):
        c = self.c
        w = c["hw"]
        for wy in (c["wheel_y"] if flares else ()):
            dy = abs(y - wy)
            if c.get("box_flare"):
                w += c["flare"] * min(max(1.0 - (dy - self.arch_r() * 0.95) / 0.06, 0.0), 1.0)
            else:
                w += c["flare"] * min(max(1.0 - (dy - self.arch_r() * 0.7) / 0.3, 0.0), 1.0)
        end = min(self.front() - y, y - self.rear())
        return w * lerp(c.get("nose_round", 0.86), 1.0, smoothstep(0.0, 0.32, end))

    def heights(self, y):
        top, belt = self.profile(y)
        c = self.c
        # the tail sits up off the road so the tyres and diffuser show from behind
        bot = c["bottom"] + 0.11 * (1.0 - smoothstep(0.0, 0.55, y - self.rear()))
        ar = self.arch_r()
        for wy in c["wheel_y"]:
            dy = abs(y - wy)
            if dy < ar:
                bot = max(bot, c["wheel_r"] + math.sqrt(ar * ar - dy * dy))
        bot = min(bot, belt - 0.2)
        sill = min(bot + 0.07, belt - 0.14)
        shoulder = belt - 0.05
        return [bot, sill, lerp(sill, shoulder, 0.55), shoulder, belt, max(top, belt + 0.02)]

    def cab(self, y):
        h = self.heights(y)
        return smoothstep(0.08, 0.3, h[5] - h[4])

    def ring(self, y):
        h = self.heights(y)
        w = self.half_width(y)
        # boxy flares are bolted onto the lower body; the shoulder stays slim
        w0 = self.half_width(y, False) if self.c.get("box_flare") else w
        cab = self.cab(y)
        roof = lerp(w0 * 0.93, self.c["roof_hw"], cab)
        right = [(w * 0.84, h[0]), (w, h[1]), (w + 0.012, h[2]), (lerp(w0, w, 0.5), h[3]), (w0 * 0.965, h[4]),
                 (roof, h[5] - 0.05 * cab - 0.012), (roof * 0.86, h[5]), (roof * 0.42, h[5] + 0.018)]
        return [(x, z) for x, z in right] + [(-x, z) for x, z in reversed(right)]

    def stations(self):
        ys = [k[0] for k in self.keys()]
        y = self.front()
        while y > self.rear():
            ys.append(y)
            y -= 0.1
        for wy in self.c["wheel_y"]:
            ys += [wy - self.arch_r(), wy + self.arch_r(), wy]
        for bp in self.pillars():
            ys += [bp - 0.05, bp + 0.05]
        ys = sorted({round(v, 4) for v in ys if self.rear() - 1e-4 <= v <= self.front() + 1e-4}, reverse=True)
        out = []
        for v in ys:
            if not out or out[-1] - v > 0.03:
                out.append(v)
        return out

    def pillars(self):
        return self.c.get("pillars", [self.c["b_pillar"]])

    def build(self, g):
        ys = self.stations()
        rings = [self.ring(y) for y in ys]
        n = len(rings[0])
        verts = []
        for y, r in zip(ys, rings):
            verts += [(x, y, z) for x, z in r]
        faces, keys = [], []
        for j in range(len(ys) - 1):
            yc = (ys[j] + ys[j + 1]) / 2
            cab = self.cab(yc)
            for e in range(n):
                e2 = (e + 1) % n
                a, b, c, d = j * n + e, j * n + e2, (j + 1) * n + e2, (j + 1) * n + e
                key = "Livery"
                if e == n - 1:
                    key = "Trim"  # underside
                elif e in (4, n - 6):  # side window band
                    if cab > 0.55 and min(abs(yc - bp) for bp in self.pillars()) > 0.05 \
                            and self.c["glass_y"][1] < yc < self.c["glass_y"][0]:
                        key = "Glass"
                elif 5 <= e <= n - 7:  # roof: screens where it slopes
                    p = [Vector(verts[i]) for i in (a, b, c)]
                    nr = (p[1] - p[0]).cross(p[2] - p[0]).normalized()
                    if abs(nr.y) > 0.3 and cab > 0.3:
                        key = "Glass"
                faces.append((a, b, c, d))
                keys.append(key)
        # nose and tail caps
        for j, sign in ((0, 1), (len(ys) - 1, -1)):
            r = rings[j]
            cz = sum(z for _, z in r) / n
            ci = len(verts)
            verts.append((0.0, ys[j], cz))
            for e in range(n):
                faces.append((j * n + e, j * n + (e + 1) % n, ci))
                keys.append("Livery")
        g.faces(verts, faces, keys)


# --------------------------------------------------------------------------- one car

def build_car(c):
    name = c["name"]
    coll = bpy.data.collections.get(name) or bpy.data.collections.new(name)
    if coll.name not in bpy.context.scene.collection.children:
        bpy.context.scene.collection.children.link(coll)
    for o in list(coll.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    M = {
        "Livery": material("Livery." + name, c["paint"], 0.35),
        "Glass": material("Glass." + name, (0.05, 0.07, 0.12), 0.1),
        "Trim": material("Trim." + name, (0.06, 0.06, 0.07), 0.7),
        "Chrome": material("Chrome." + name, (0.7, 0.7, 0.72), 0.25, 1.0),
        "Lamp": material("Lamp." + name, (1.0, 0.95, 0.75), 0.2, emit=True),
        "Flap": material("Flap." + name, c["flaps"], 0.9),
        "Tyre": material("Tyre." + name, (0.05, 0.05, 0.05), 0.95),
        "Rim": material("Rim." + name, c["rims"], 0.4, 0.6),
        "Tail": material("Tail." + name, (0.9, 0.08, 0.05), 0.3, emit=True),
    }
    B = Builder(coll, c)
    root = B.empty(name, (0, 0, 0))
    if c.get("kind") == "f1":
        f1_parts(B, c, root, M)
    else:
        saloon_parts(B, c, root, M)
    make_wheels(B, c, root, M)
    if B.pieces:
        c["layout"] = {"size": SKIN, "px_per_m": B.px_m, "pieces": B.pieces, "faces": B.layout}
    return coll


def saloon_parts(B, c, root, M):
    """Lofted body, bumpers, mirrors, wing, light pod, mud flaps, exhaust."""
    body = Body(c)

    g = G()
    body.build(g)
    for extra in c.get("body_extras", []):
        extra(g, body)
    hull = B.make("Body", g, (0, 0, 0.6), root, M)

    fy, ry = body.front(), body.rear()
    hwf, hwr = body.half_width(fy - 0.15), body.half_width(ry + 0.15)
    # bumpers: chamfered blocks wrapping the nose and tail
    bt = c["bumper_top"]
    g = G()
    g.hull([(sx * x, y, z) for sx in (-1, 1) for (x, y, z) in [
        (hwf + 0.015, fy - 0.42, 0.2), (hwf + 0.015, fy - 0.42, bt[0]), (hwf * 0.9, fy + 0.03, 0.22),
        (hwf * 0.9, fy + 0.03, bt[0] - 0.02), (hwf * 0.98, fy - 0.12, bt[0]), (hwf * 0.95, fy - 0.05, 0.19)]], "Livery")
    g.box((0, fy + 0.035, 0.27), (hwf * 1.3, 0.02, 0.08), "Trim")  # splitter lip
    B.make("Bumper_F", g, (0, fy - 0.15, 0.36), hull, M)
    g = G()
    g.hull([(sx * x, y, z) for sx in (-1, 1) for (x, y, z) in [
        (hwr + 0.015, ry + 0.38, 0.27), (hwr + 0.015, ry + 0.38, bt[1]), (hwr * 0.92, ry - 0.03, 0.33),
        (hwr * 0.92, ry - 0.03, bt[1] - 0.02), (hwr * 0.98, ry + 0.1, bt[1]), (hwr * 0.95, ry + 0.05, 0.3)]], "Livery")
    B.make("Bumper_R", g, (0, ry + 0.15, 0.36), hull, M)

    # mirrors on the doors just behind the A-pillar
    my = c["mirror_y"]
    mh = body.heights(my)[4]
    for s, n in ((-1, "L"), (1, "R")):
        g = G()
        x = body.half_width(my)
        g.hull([(s * (x + dx), my + dy, mh + dz) for (dx, dy, dz) in [
            (0.04, -0.02, 0.05), (0.04, -0.02, 0.15), (0.17, -0.06, 0.06), (0.17, -0.06, 0.15),
            (0.04, 0.07, 0.07), (0.04, 0.07, 0.14), (0.17, 0.05, 0.08), (0.17, 0.05, 0.14)]], "Livery")
        g.box((s * (x + 0.11), my - 0.065, mh + 0.105), (0.11, 0.01, 0.07), "Chrome")
        B.make("Mirror_" + n, g, (s * (x + 0.1), my, mh + 0.1), hull, M)

    # spoiler / wing
    if c.get("wing"):
        g = G()
        c["wing"](g, body)
        wy = c["wing_y"]
        B.make("Spoiler", g, (0, wy, body.heights(wy)[5] + 0.1), hull, M)

    # bonnet light pod
    if c.get("pod", 0):
        g = G()
        k = c["pod"]
        py = fy - 0.22
        pz = body.heights(py)[5] + 0.03
        span = k * 0.25 + 0.06
        g.box((0, py, pz + 0.09), (span, 0.12, 0.2), "Trim")
        for i in range(k):
            x = (i - (k - 1) / 2) * 0.25
            g.cyl((x, py + 0.07, pz + 0.09), "Y", 0.1, 0.04, "Chrome", segs=10)
            g.cyl((x, py + 0.09, pz + 0.09), "Y", 0.085, 0.02, "Lamp", segs=10)
        for s in (-1, 1):
            g.box((s * span * 0.3, py - 0.05, pz + 0.01), (0.04, 0.12, 0.04), "Trim")
        B.make("LightPod", g, (0, py, pz + 0.09), hull, M)

    # mud flaps behind every wheel, exhaust
    g = G()
    for wy in c["wheel_y"]:
        for s in (-1, 1):
            g.box((s * (c["wheel_x"] - 0.02), wy - body.arch_r() + 0.03, 0.17), (0.3, 0.015, 0.26), "Flap")
    B.make("MudFlaps", g, (0, 0, 0.17), hull, M)
    g = G()
    g.cyl((c["exhaust_x"], ry + 0.0, 0.26), "Y", 0.045, 0.22, "Chrome", segs=8)
    g.cyl((c["exhaust_x"], ry - 0.11, 0.26), "Y", 0.035, 0.01, "Trim", segs=8)
    B.make("Exhaust", g, (c["exhaust_x"], ry, 0.26), hull, M)



def make_wheels(B, c, root, M):
    """Tyre tread, inner sidewall and a textured rim face on the outside.
    wheel_r and wheel_w can be one size or (front, rear)."""
    for i, (wy, front) in enumerate(((c["wheel_y"][0], "F"), (c["wheel_y"][1], "R"))):
        r = c["wheel_r"][i] if isinstance(c["wheel_r"], tuple) else c["wheel_r"]
        w = c["wheel_w"][i] if isinstance(c["wheel_w"], tuple) else c["wheel_w"]
        for s, side in ((-1, "L"), (1, "R")):
            g = G()
            x = s * c["wheel_x"]
            segs = 14
            verts, faces, keys = [], [], []
            for i in range(segs):
                a = math.tau * i / segs
                for dx in (-w / 2, w / 2):
                    verts.append((x + dx, wy + r * math.cos(a), r + r * math.sin(a)))
            for i in range(segs):
                j = (i + 1) % segs
                faces.append((2 * i, 2 * j, 2 * j + 1, 2 * i + 1))
                keys.append("Tyre")
            out = [2 * i + (1 if s > 0 else 0) for i in range(segs)]
            inn = [2 * i + (0 if s > 0 else 1) for i in range(segs)]
            faces += [tuple(out), tuple(reversed(inn))]
            keys += ["Rim", "Trim"]
            g.faces(verts, faces, keys)
            B.make("Wheel_" + front + side, g, (x, wy, r), root, M)


# --------------------------------------------------------------------------- the cars

def subaru_extras(g, body):
    # bonnet scoop and roof vent
    y = 1.05
    z = body.heights(y)[5]
    g.hull([(sx * x, y + dy, z + dz) for sx in (-1, 1) for (x, dy, dz) in [
        (0.3, 0.25, -0.01), (0.3, -0.2, -0.01), (0.24, 0.22, 0.07), (0.24, -0.2, 0.08)]], "Livery")
    g.box((0, y + 0.235, z + 0.035), (0.44, 0.02, 0.06), "Trim")
    y = 0.0
    z = body.heights(y)[5]
    g.hull([(sx * x, y + dy, z + dz) for sx in (-1, 1) for (x, dy, dz) in [
        (0.14, 0.1, -0.005), (0.14, -0.25, -0.005), (0.11, 0.08, 0.06), (0.11, -0.25, 0.04)]], "Livery")
    g.box((0, y + 0.09, z + 0.03), (0.2, 0.02, 0.04), "Trim")


def subaru_wing(g, body):
    # two-tier WRC wing: a lower blade on the boot lid and the main plane above
    y = -1.88
    z = body.heights(y)[5]
    for s in (-1, 1):
        g.hull([(s * x, y + dy, z + dz) for x in (0.52, 0.56) for (dy, dz) in [
            (0.12, -0.01), (-0.12, -0.01), (0.02, 0.26), (-0.14, 0.26)]], "Livery")
    g.hull([(sx * 0.8, y + dy, z + dz) for sx in (-1, 1) for (dy, dz) in [
        (0.12, 0.27), (-0.24, 0.31), (-0.24, 0.26), (0.1, 0.24)]], "Livery")
    g.hull([(sx * 0.66, y + dy, z + dz) for sx in (-1, 1) for (dy, dz) in [
        (0.08, 0.11), (-0.18, 0.13), (-0.18, 0.1), (0.07, 0.09)]], "Livery")
    for s in (-1, 1):
        g.box((s * 0.805, y - 0.06, z + 0.26), (0.02, 0.42, 0.16), "Trim")


def delta_extras(g, body):
    # bonnet vents
    y = 1.25
    z = body.heights(y)[5]
    for sx in (-1, 1):
        g.box((sx * 0.4, y, z + 0.012), (0.28, 0.24, 0.02), "Trim")


def delta_lamps(g, body):
    # four round headlamps in the black band across the nose: big outer, small inner
    y = body.front() - 0.005
    for sx in (-1, 1):
        for x, r in ((0.6, 0.085), (0.38, 0.068)):
            g.cyl((sx * x, y, 0.625), "Y", r + 0.014, 0.03, "Chrome", segs=10)
            g.cyl((sx * x, y + 0.016, 0.625), "Y", r, 0.012, "Lamp", segs=10)


def delta_wing(g, body):
    # roof spoiler along the top edge of the hatch, on two small feet
    y = -1.43
    z = body.heights(y)[5]
    g.hull([(sx * x, y + dy, z + dz) for sx in (-1, 1) for (x, dy, dz) in [
        (0.64, 0.02, 0.0), (0.64, 0.02, 0.035), (0.64, -0.3, -0.07), (0.64, -0.3, -0.04)]], "Livery")
    for sx in (-1, 1):
        g.box((sx * 0.45, y - 0.08, z - 0.01), (0.05, 0.12, 0.04), "Trim")


def rod(g, a, b, t, key):
    """A thin square bar from a to b."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    side = d.cross(Vector((0, 0, 1)))
    if side.length < 1e-3:
        side = Vector((1, 0, 0))
    side = side.normalized() * t / 2
    up = side.cross(d).normalized() * t / 2
    g.hull([p + sx * side + sz * up for p in (a, b) for sx in (-1, 1) for sz in (-1, 1)], key)


def f1_parts(B, c, root, M):
    """Modern single-seater: needle nose, tub with a halo, airbox, undercut
    sidepods, floor, multi-element front wing, tall rear wing with a beam
    wing, pushrod-style wishbones. Low-poly convex pieces."""
    g = G()
    # nose and tub
    g.hull([(sx * x, y, z) for sx in (-1, 1) for (x, y, z) in [
        (0.06, 2.5, 0.19), (0.06, 2.5, 0.28), (0.12, 1.95, 0.2), (0.12, 1.95, 0.42),
        (0.2, 1.3, 0.18), (0.2, 1.3, 0.52)]], "Livery")
    g.hull([(sx * x, y, z) for sx in (-1, 1) for (x, y, z) in [
        (0.2, 1.3, 0.16), (0.2, 1.3, 0.52), (0.33, 0.3, 0.15), (0.33, 0.3, 0.62),
        (0.33, -0.45, 0.15), (0.33, -0.45, 0.62)]], "Livery")
    g.box((0, -0.08, 0.62), (0.42, 0.72, 0.03), "Trim")  # cockpit opening
    # engine cover with the airbox over the roll hoop, tapering to the gearbox
    g.hull([(sx * x, y, z) for sx in (-1, 1) for (x, y, z) in [
        (0.32, -0.42, 0.16), (0.3, -0.42, 0.63), (0.12, -0.48, 0.96), (0.12, -0.66, 0.95),
        (0.2, -1.2, 0.16), (0.18, -1.2, 0.62), (0.12, -1.9, 0.18), (0.1, -1.9, 0.42),
        (0.07, -2.05, 0.24), (0.06, -2.05, 0.36)]], "Livery")
    g.box((0, -0.455, 0.865), (0.17, 0.03, 0.13), "Trim")  # airbox mouth
    g.box((0, -2.06, 0.32), (0.08, 0.02, 0.06), "Tail")  # rain light
    # floor with edge fences
    g.hull([(sx * x, y, z) for sx in (-1, 1) for (x, y, z) in [
        (0.45, 1.15, 0.05), (0.45, 1.15, 0.08), (0.8, 0.6, 0.05), (0.8, 0.6, 0.08),
        (0.8, -1.05, 0.05), (0.8, -1.05, 0.08), (0.5, -1.75, 0.06), (0.5, -1.75, 0.09)]], "Trim")
    # halo: centre post and the hoop round the cockpit
    rod(g, (0, 0.33, 0.6), (0, 0.24, 0.8), 0.05, "Livery")
    rod(g, (-0.22, 0.2, 0.8), (0.22, 0.2, 0.8), 0.05, "Livery")
    for sx in (-1, 1):
        rod(g, (sx * 0.22, 0.2, 0.8), (sx * 0.29, -0.15, 0.78), 0.05, "Livery")
        rod(g, (sx * 0.29, -0.15, 0.78), (sx * 0.31, -0.42, 0.62), 0.05, "Livery")
    # wishbones and pushrods from the tub to the hubs
    for i, (wy, r, w) in enumerate(zip(c["wheel_y"], c["wheel_r"], c["wheel_w"])):
        hx = c["wheel_x"] - w / 2
        for sx in (-1, 1):
            hub = Vector((sx * hx, wy, r))
            inner_x = sx * (0.17 if i == 0 else 0.2)
            for dz, z_in in ((0.07, 0.42), (-0.06, 0.22)):
                rod(g, hub + Vector((0, 0, dz)), (inner_x, wy + 0.18, z_in), 0.03, "Trim")
                rod(g, hub + Vector((0, 0, dz)), (inner_x, wy - 0.18, z_in), 0.03, "Trim")
    hull = B.make("Body", g, (0, 0, 0.35), root, M)

    # undercut sidepods with dark inlets
    for sx, n in ((-1, "L"), (1, "R")):
        g = G()
        g.hull([(sx * x, y, z) for (x, y, z) in [
            (0.36, 0.22, 0.34), (0.72, 0.22, 0.34), (0.36, 0.22, 0.58), (0.7, 0.22, 0.56),
            (0.42, 0.12, 0.2), (0.6, 0.12, 0.22), (0.34, -0.45, 0.18), (0.72, -0.45, 0.24),
            (0.34, -0.45, 0.58), (0.7, -0.45, 0.52), (0.26, -1.3, 0.17), (0.4, -1.3, 0.2),
            (0.24, -1.3, 0.36), (0.36, -1.3, 0.32)]], "Livery")
        g.box((sx * 0.54, 0.225, 0.45), (0.3, 0.02, 0.18), "Trim")
        B.make("Sidepod_" + n, g, (sx * 0.5, -0.5, 0.38), hull, M)
        g = G()
        rod(g, (sx * 0.31, 0.32, 0.62), (sx * 0.48, 0.36, 0.7), 0.025, "Trim")
        g.hull([(sx * x, y, z) for (x, y, z) in [
            (0.46, 0.4, 0.66), (0.6, 0.4, 0.66), (0.46, 0.4, 0.75), (0.6, 0.4, 0.75),
            (0.47, 0.32, 0.67), (0.59, 0.32, 0.67), (0.47, 0.32, 0.74), (0.59, 0.32, 0.74)]], "Livery")
        g.box((sx * 0.53, 0.315, 0.705), (0.1, 0.01, 0.06), "Chrome")
        B.make("Mirror_" + n, g, (sx * 0.5, 0.36, 0.7), hull, M)

    # front wing: three elements rising towards the endplates, nose pillars
    g = G()
    g.hull([(sx * x, y, z) for sx in (-1, 1) for (x, y, z) in [
        (0.95, 2.56, 0.06), (0.95, 2.56, 0.085), (0.95, 2.26, 0.07), (0.95, 2.26, 0.095)]], "Livery")
    for sx in (-1, 1):
        g.hull([(sx * x, y, z) for (x, y, z) in [
            (0.12, 2.36, 0.11), (0.12, 2.24, 0.12), (0.12, 2.36, 0.13), (0.12, 2.24, 0.14),
            (0.94, 2.38, 0.15), (0.94, 2.24, 0.17), (0.94, 2.38, 0.17), (0.94, 2.24, 0.19)]], "Livery")
        g.hull([(sx * x, y, z) for (x, y, z) in [
            (0.3, 2.28, 0.17), (0.3, 2.2, 0.18), (0.3, 2.28, 0.19), (0.3, 2.2, 0.2),
            (0.94, 2.3, 0.23), (0.94, 2.2, 0.25), (0.94, 2.3, 0.25), (0.94, 2.2, 0.27)]], "Livery")
        g.box((sx * 0.96, 2.4, 0.17), (0.02, 0.42, 0.25), "Livery")
        g.box((sx * 0.06, 2.36, 0.16), (0.02, 0.14, 0.12), "Trim")
    B.make("FrontWing", g, (0, 2.38, 0.15), hull, M)

    # rear wing: endplates, main plane and flap, beam wing, centre pylon
    g = G()
    for sx in (-1, 1):
        g.box((sx * 0.53, -2.08, 0.72), (0.025, 0.45, 0.6), "Livery")
    g.hull([(sx * 0.52, y, z) for sx in (-1, 1) for (y, z) in [
        (-1.95, 0.86), (-1.95, 0.89), (-2.2, 0.9), (-2.2, 0.93)]], "Livery")
    g.hull([(sx * 0.52, y, z) for sx in (-1, 1) for (y, z) in [
        (-2.12, 0.96), (-2.12, 0.98), (-2.28, 1.0), (-2.28, 1.02)]], "Livery")
    g.hull([(sx * 0.46, y, z) for sx in (-1, 1) for (y, z) in [
        (-1.95, 0.44), (-1.95, 0.47), (-2.14, 0.46), (-2.14, 0.49)]], "Livery")
    g.box((0, -2.05, 0.66), (0.04, 0.1, 0.42), "Trim")
    B.make("RearWing", g, (0, -2.08, 0.75), hull, M)


CARS = [
    dict(name="Pleiad", file="pleiad", paint=(0.1, 0.22, 0.66), flaps=(0.95, 0.95, 0.95), rims=(0.85, 0.68, 0.22),
         hw=0.865, roof_hw=0.62, flare=0.075, bottom=0.2, nose_round=0.84,
         # compact '97 saloon: low roof, raked screen, short boot carrying the wing
         profile=[(2.18, 0.6, 0.56), (2.08, 0.74, 0.7), (1.6, 0.82, 0.78), (0.92, 0.88, 0.84), (0.12, 1.37, 0.92),
                  (-0.78, 1.37, 0.94), (-1.45, 1.0, 0.96), (-2.02, 1.02, 0.98), (-2.18, 0.86, 0.84)],
         glass_y=(0.95, -1.15), pillars=[-0.35], b_pillar=-0.35, mirror_y=0.72,
         wheel_y=(1.32, -1.28), wheel_x=0.82, wheel_r=0.34, wheel_w=0.26,
         bumper_top=(0.56, 0.62), exhaust_x=-0.55, pod=4, wing_y=-1.88,
         body_extras=[subaru_extras], wing=subaru_wing,
         screen=((0.92, 0.88), (0.12, 1.37))),
    dict(name="Martello", file="martello", paint=(0.95, 0.95, 0.94), flaps=(0.08, 0.2, 0.62), rims=(0.92, 0.92, 0.9),
         hw=0.835, roof_hw=0.665, flare=0.11, box_flare=True, bottom=0.2, nose_round=0.93,
         # short upright Delta hatch: flat bonnet with a slight wedge, steep screen,
         # long flat roof, near-vertical hatch over a tall tail panel
         profile=[(2.02, 0.54, 0.5), (2.0, 0.71, 0.67), (1.95, 0.75, 0.71), (1.4, 0.8, 0.76), (0.88, 0.86, 0.82),
                  (0.25, 1.36, 0.86), (-1.45, 1.35, 0.9), (-1.72, 0.96, 0.9), (-1.95, 0.62, 0.58)],
         glass_y=(0.85, -1.32), pillars=[-0.33, -1.0], b_pillar=-0.33, mirror_y=0.78,
         wheel_y=(1.32, -1.28), wheel_x=0.82, wheel_r=0.34, wheel_w=0.26,
         bumper_top=(0.52, 0.58), exhaust_x=-0.5, pod=4, wing_y=-1.43,
         body_extras=[delta_extras, delta_lamps], wing=delta_wing,
         screen=((0.88, 0.86), (0.25, 1.36))),
    dict(name="Veloce", file="veloce", kind="f1", paint=(0.09, 0.11, 0.24), flaps=(0.1, 0.1, 0.1),
         rims=(0.08, 0.08, 0.09), half_len=2.45, px_m=70.0,
         wheel_y=(1.72, -1.42), wheel_x=0.84, wheel_r=(0.32, 0.35), wheel_w=(0.3, 0.42)),
]


def export(coll, path):
    bpy.ops.object.select_all(action="DESELECT")
    for o in coll.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=False, export_cameras=False, export_lights=False, export_animations=False)


def reset_scene():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for data in (bpy.data.meshes, bpy.data.materials, bpy.data.collections):
        for d in list(data):
            data.remove(d)


def build_all(repo):
    """Each car gets its own .blend in art/cars and a .glb in models/."""
    for c in CARS:
        reset_scene()
        coll = build_car(c)
        export(coll, os.path.join(repo, "models", c["file"] + ".glb"))
        if "layout" in c:
            with open(os.path.join(repo, "art", "cars", c["file"] + "_layout.json"), "w", newline="\n") as f:
                json.dump(c.pop("layout"), f)
        blend = os.path.join(repo, "art", "cars", c["file"] + ".blend")
        bpy.ops.wm.save_as_mainfile(filepath=blend, compress=True)
        if os.path.exists(blend + "1"):
            os.remove(blend + "1")


if __name__ == "__main__":
    build_all(os.path.normpath(os.path.join(os.path.dirname(bpy.data.filepath), "..", "..")))
