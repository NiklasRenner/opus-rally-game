class_name Cars
extends RefCounted
## The cars you can pick in the menu. Each one is a side profile that
## CarModel lofts into a low-poly body, a livery, some bolt-on details and
## a few small handling tweaks (kept close so records stay comparable).
##
## profile : [z, roof/bonnet height, belt line height] keyframes front (-Z)
##           to back. Where the top is well above the belt it is glass.
## taper   : roof width as a fraction of body width (tumblehome)
## flare   : extra half-width over the wheel arches
## b_pillar: z of the pillar between the side windows
## livery  : kind (bands, split, nose, stripes) + colours
## wing    : [z, height above the body, chord] or [] for none
## pod     : number of spot lamps on the nose pod (0 for none)
## plate, banner (windscreen strip), sponsor (rear quarter sticker): decal text
## stats   : power, grip and steer multipliers, mass in kg (the tank adds a few more)
## type    : "car" (default), "kart", "f1" or "tank"
## wheels  : optional layout {x, zf, zr, rf, rr, wf, wr}: track half-width,
##           front/rear axle z, visual tyre radius and width per axle
## plan    : optional [z, width] keys for bodies that aren't one width (F1 tub)
## bottom  : optional underside height of the lofted shell (default -0.24)
## glass   : false for open cockpits (tall parts of the profile stay painted)
## Extra stats: gearing (final drive multiplier, >1 = shorter gears / lower top
## speed), drag, downforce, inertia (yaw inertia vs a saloon), pitch (engine note).
## Chassis forces (springs, brakes, yaw assists) scale with mass so light and
## heavy vehicles handle alike; engine power does not, so mass still counts.

const LIST := [
	{
		"id": "martello",
		"name": "MARTELLO HF",
		"blurb": "Boxy hatch, all-rounder",
		"number": "4",
		"plate": "MH 4",
		"banner": ["RALLYE", Color(1, 1, 1), Color(0.08, 0.20, 0.62)],
		"sponsor": ["PIXEL OIL", Color(0.86, 0.10, 0.10), Color(0.97, 0.97, 0.95)],
		"width": 1.76,
		"profile": [[-1.98, 0.14, 0.08], [-1.86, 0.25, 0.19], [-0.85, 0.37, 0.31], [-0.15, 0.93, 0.36],
			[1.22, 0.93, 0.38], [1.80, 0.62, 0.40], [1.98, 0.52, 0.40]],
		"taper": 0.80,
		"flare": 0.06,
		"a_pillar": -0.85,
		"b_pillar": 0.45,
		"lights": "square",
		"livery": {"kind": "bands", "base": Color(0.95, 0.95, 0.94), "a": Color(0.08, 0.20, 0.62), "b": Color(0.86, 0.10, 0.10)},
		"roof": Color(0.95, 0.95, 0.94),
		"trim": Color(0.12, 0.12, 0.14),
		"rims": Color(0.92, 0.92, 0.90),
		"flaps": Color(0.08, 0.20, 0.62),
		"wing": [1.20, 0.05, 0.32],
		"pod": 4,
		"scoop": 0.0,
		"stats": {"power": 1.0, "grip": 1.0, "steer": 1.0, "mass": 1200.0},
	},
	{
		"id": "pleiad",
		"name": "PLEIAD 555",
		"blurb": "Grippy saloon, gold wheels",
		"number": "5",
		"plate": "PL 555",
		"banner": ["PLEIAD", Color(1.0, 0.82, 0.08), Color(0.10, 0.22, 0.66)],
		"sponsor": ["STAR 7", Color(0.10, 0.22, 0.66), Color(1.0, 0.82, 0.08)],
		"width": 1.74,
		"profile": [[-2.02, 0.15, 0.06], [-1.90, 0.25, 0.18], [-0.78, 0.37, 0.31], [-0.05, 0.89, 0.34],
			[0.95, 0.89, 0.36], [1.45, 0.49, 0.40], [1.95, 0.47, 0.40], [2.02, 0.38, 0.32]],
		"taper": 0.82,
		"flare": 0.05,
		"a_pillar": -0.78,
		"b_pillar": 0.42,
		"lights": "square",
		"livery": {"kind": "split", "base": Color(0.10, 0.22, 0.66), "a": Color(0.10, 0.22, 0.66), "b": Color(1.0, 0.82, 0.08)},
		"roof": Color(0.10, 0.22, 0.66),
		"trim": Color(0.12, 0.12, 0.14),
		"rims": Color(0.85, 0.68, 0.22),
		"flaps": Color(0.95, 0.95, 0.95),
		"wing": [1.80, 0.20, 0.34],
		"pod": 4,
		"scoop": -1.30,
		"stats": {"power": 0.97, "grip": 1.04, "steer": 0.98, "mass": 1230.0},
	},
	{
		"id": "kaze",
		"name": "KAZE GT4",
		"blurb": "Fastback coupe, most power",
		"number": "1",
		"plate": "GT 4",
		"banner": ["KAZE", Color(1, 1, 1), Color(0.88, 0.10, 0.08)],
		"sponsor": ["TURBO", Color(1, 1, 1), Color(0.10, 0.10, 0.12)],
		"width": 1.74,
		"profile": [[-2.05, 0.13, 0.04], [-1.92, 0.21, 0.14], [-0.70, 0.33, 0.27], [0.0, 0.85, 0.32],
			[0.70, 0.85, 0.34], [1.85, 0.51, 0.38], [2.05, 0.45, 0.36]],
		"taper": 0.80,
		"flare": 0.04,
		"a_pillar": -0.70,
		"b_pillar": 0.55,
		"lights": "round",
		"livery": {"kind": "split", "base": Color(0.88, 0.10, 0.08), "a": Color(0.10, 0.10, 0.12), "b": Color(0.96, 0.96, 0.96)},
		"roof": Color(0.96, 0.96, 0.96),
		"trim": Color(0.10, 0.10, 0.12),
		"rims": Color(0.95, 0.95, 0.95),
		"flaps": Color(0.88, 0.10, 0.08),
		"wing": [1.92, 0.12, 0.30],
		"pod": 2,
		"scoop": 0.0,
		"stats": {"power": 1.05, "grip": 0.97, "steer": 0.96, "mass": 1260.0},
	},
	{
		"id": "falke",
		"name": "FALKE RS",
		"blurb": "Big whale-tail wing, stable",
		"number": "7",
		"plate": "RS 77",
		"banner": ["FALKE", Color(1, 1, 1), Color(0.10, 0.25, 0.75)],
		"sponsor": ["BYTE", Color(1, 1, 1), Color(0.86, 0.10, 0.10)],
		"width": 1.78,
		"profile": [[-2.00, 0.15, 0.08], [-1.88, 0.27, 0.21], [-0.82, 0.39, 0.33], [-0.15, 0.95, 0.37],
			[0.90, 0.95, 0.39], [1.35, 0.53, 0.43], [1.94, 0.51, 0.43], [2.00, 0.41, 0.35]],
		"taper": 0.83,
		"flare": 0.07,
		"a_pillar": -0.82,
		"b_pillar": 0.38,
		"lights": "round",
		"livery": {"kind": "stripes", "base": Color(0.95, 0.95, 0.94), "a": Color(0.10, 0.25, 0.75), "b": Color(0.86, 0.10, 0.10)},
		"roof": Color(0.95, 0.95, 0.94),
		"trim": Color(0.12, 0.12, 0.14),
		"rims": Color(0.92, 0.92, 0.90),
		"flaps": Color(0.86, 0.10, 0.10),
		"wing": [1.66, 0.34, 0.52],
		"pod": 4,
		"scoop": 0.0,
		"stats": {"power": 0.99, "grip": 1.02, "steer": 1.0, "mass": 1220.0},
	},
	{
		"id": "cuneo",
		"name": "CUNEO STRADALE",
		"blurb": "Short wedge, twitchy and quick",
		"number": "2",
		"plate": "CU 2",
		"banner": ["CUNEO", Color(1, 1, 1), Color(0.10, 0.55, 0.25)],
		"sponsor": ["VOLT", Color(0.86, 0.10, 0.10), Color(0.97, 0.97, 0.95)],
		"width": 1.82,
		"profile": [[-1.88, 0.13, 0.05], [-1.74, 0.19, 0.11], [-0.85, 0.30, 0.22], [-0.30, 0.80, 0.25],
			[0.40, 0.82, 0.27], [1.05, 0.45, 0.37], [1.84, 0.45, 0.37], [1.88, 0.37, 0.31]],
		"taper": 0.76,
		"flare": 0.06,
		"a_pillar": -0.85,
		"b_pillar": 0.25,
		"lights": "square",
		"livery": {"kind": "nose", "base": Color(0.95, 0.95, 0.94), "a": Color(0.10, 0.55, 0.25), "b": Color(0.86, 0.10, 0.10)},
		"roof": Color(0.95, 0.95, 0.94),
		"trim": Color(0.12, 0.12, 0.14),
		"rims": Color(0.80, 0.80, 0.82),
		"flaps": Color(0.10, 0.55, 0.25),
		"wing": [1.80, 0.10, 0.36],
		"pod": 5,
		"scoop": 0.0,
		"stats": {"power": 1.02, "grip": 0.96, "steer": 1.08, "mass": 1100.0},
	},
	{
		"id": "kart",
		"type": "kart",
		"name": "KART 125",
		"blurb": "Tiny and twitchy, flat out everywhere",
		"number": "12",
		"plate": "K 12",
		"sponsor": ["ZIPPY", Color(0.05, 0.05, 0.07), Color(1.0, 0.82, 0.08)],
		"width": 1.2,
		"profile": [[-0.9, -0.4, -0.45], [0.8, -0.4, -0.45]],
		"taper": 1.0,
		"flare": 0.0,
		"arches": false,
		"a_pillar": -0.9,
		"b_pillar": 0.0,
		"lights": "round",
		"livery": {"kind": "split", "base": Color(1.0, 0.80, 0.06), "a": Color(0.08, 0.08, 0.10), "b": Color(0.86, 0.10, 0.10)},
		"roof": Color(0.95, 0.95, 0.94),
		"trim": Color(0.12, 0.12, 0.14),
		"rims": Color(0.85, 0.85, 0.88),
		"flaps": Color(0.1, 0.1, 0.1),
		"wing": [],
		"pod": 0,
		"scoop": 0.0,
		"wheels": {"x": 0.6, "zf": -0.58, "zr": 0.52, "rf": 0.13, "rr": 0.145, "wf": 0.14, "wr": 0.2},
		"stats": {"power": 0.2, "grip": 1.12, "steer": 1.3, "mass": 300.0,
			"gearing": 1.9, "drag": 0.6, "inertia": 0.7, "pitch": 1.7},
		"shapes": [[Vector3(1.3, 0.25, 1.85), Vector3(0, -0.375, 0)], [Vector3(0.5, 0.65, 0.55), Vector3(0, 0.0, 0.2)]],
	},
	{
		"id": "f1",
		"type": "f1",
		"name": "VELOCE F1",
		"blurb": "V10 single-seater, huge downforce",
		"number": "27",
		"sponsor": ["VELOCE", Color(1, 1, 1), Color(0.85, 0.08, 0.08)],
		"width": 0.8,
		"plan": [[-2.45, 0.24], [-1.7, 0.36], [-0.85, 0.6], [-0.3, 0.76], [0.5, 0.72], [1.4, 0.5], [2.05, 0.42]],
		"profile": [[-2.45, -0.36, -0.40], [-1.7, -0.2, -0.26], [-0.85, 0.0, -0.08], [-0.3, 0.06, -0.02],
			[0.1, 0.08, 0.0], [0.2, 0.32, 0.0], [0.6, 0.3, -0.02], [1.4, 0.02, -0.18], [2.05, -0.24, -0.34]],
		"bottom": -0.6,
		"glass": false,
		"taper": 0.8,
		"flare": 0.0,
		"arches": false,
		"a_pillar": -0.85,
		"b_pillar": -0.3,
		"lights": "none",
		"livery": {"kind": "nose", "base": Color(0.96, 0.96, 0.95), "a": Color(0.85, 0.08, 0.08), "b": Color(0.85, 0.08, 0.08)},
		"roof": Color(0.96, 0.96, 0.95),
		"trim": Color(0.10, 0.10, 0.12),
		"rims": Color(0.80, 0.80, 0.84),
		"flaps": Color(0.1, 0.1, 0.1),
		"helmet": Color(1.0, 0.85, 0.1),
		"wing": [],
		"pod": 0,
		"scoop": 0.0,
		"wheels": {"x": 0.84, "zf": -1.72, "zr": 1.42, "rf": 0.32, "rr": 0.35, "wf": 0.3, "wr": 0.42},
		"stats": {"power": 2.0, "grip": 1.1, "steer": 0.95, "mass": 800.0,
			"gearing": 0.78, "drag": 0.7, "downforce": 3.5, "inertia": 0.85, "pitch": 1.45},
		"shapes": [[Vector3(2.0, 0.26, 4.7), Vector3(0, -0.30, -0.15)], [Vector3(0.7, 0.4, 1.2), Vector3(0, 0.0, 0.4)]],
	},
	{
		"id": "tank",
		"type": "tank",
		"name": "TANK T-98",
		"blurb": "Just for fun. Slow, heavy, pivots on the spot",
		"number": "98",
		"width": 2.0,
		"profile": [[-2.15, 0.0, -0.08], [-1.55, 0.24, 0.13], [1.9, 0.28, 0.17], [2.12, 0.12, 0.03]],
		"taper": 0.9,
		"flare": 0.0,
		"arches": false,
		"a_pillar": -1.0,
		"b_pillar": 0.0,
		"lights": "round",
		"livery": {"kind": "camo", "base": Color(0.38, 0.42, 0.24), "a": Color(0.22, 0.27, 0.15), "b": Color(0.45, 0.36, 0.22)},
		"roof": Color(0.38, 0.42, 0.24),
		"trim": Color(0.22, 0.24, 0.15),
		"rims": Color(0.3, 0.32, 0.2),
		"flaps": Color(0.1, 0.1, 0.1),
		"wing": [],
		"pod": 0,
		"scoop": 0.0,
		# drag: extra air resistance (lower top speed), pivot: skid-steer turn on
		# the spot, armour: damage taken, pitch: engine note
		"stats": {"power": 0.85, "grip": 1.15, "steer": 0.9, "mass": 1700.0,
			"drag": 1.9, "pivot": 1.0, "armour": 0.3, "pitch": 0.45},
		# collision boxes [size, centre]: wider hull and a turret
		"shapes": [[Vector3(2.0, 0.62, 4.3), Vector3(0, 0.0, 0)], [Vector3(1.3, 0.45, 1.6), Vector3(0, 0.5, 0.2)]],
	},
	{
		"id": "pardel",
		"type": "tank",
		"name": "KPZ PARDEL",
		"blurb": "Boxy German heavy. Wedge turret, stabilised gun",
		"number": "211",
		# modelled in Blender (art/tank) instead of lofted from a profile; the
		# profile here only marks the nose and tail for lights and the camera
		"mesh": "res://models/leopard.glb",
		"width": 2.2,
		"profile": [[-2.28, 0.34, 0.1], [2.22, 0.3, 0.1]],
		"taper": 0.9,
		"flare": 0.0,
		"arches": false,
		"a_pillar": -1.0,
		"b_pillar": 0.0,
		"lights": "round",
		"livery": {"kind": "camo", "base": Color(0.21, 0.26, 0.15), "a": Color(0.31, 0.23, 0.15), "b": Color(0.09, 0.09, 0.08)},
		"roof": Color(0.21, 0.26, 0.15),
		"trim": Color(0.12, 0.14, 0.09),
		"rims": Color(0.21, 0.26, 0.15),
		"flaps": Color(0.1, 0.1, 0.1),
		"wing": [],
		"pod": 0,
		"scoop": 0.0,
		"stats": {"power": 0.95, "grip": 1.15, "steer": 0.9, "mass": 1800.0,
			"drag": 1.8, "pivot": 1.0, "armour": 0.25, "pitch": 0.4},
		"shapes": [[Vector3(2.1, 0.6, 4.4), Vector3(0, 0.03, 0)], [Vector3(1.6, 0.42, 2.4), Vector3(0, 0.57, 0.15)]],
	},
]


const WHEELS := {"x": 0.82, "zf": -1.32, "zr": 1.28, "rf": 0.34, "rr": 0.34, "wf": 0.26, "wr": 0.26}
const REF_MASS := 1200.0
const WHEEL_RADIUS := 0.34  # every wheel's physics radius; small tyres are drawn lower
const ATTACH_Y := -0.05  # height of the suspension attach points


## Wheel layout for a spec, filled in with the saloon defaults.
static func wheels(spec: Dictionary) -> Dictionary:
	var w := WHEELS.duplicate()
	w.merge(spec.get("wheels", {}), true)
	return w


## Suspension attach points from the spec's wheel layout: FL, FR, RL, RR.
static func wheel_positions(s: Dictionary) -> Array[Vector3]:
	var wl := wheels(s)
	var x: float = wl["x"]
	var out: Array[Vector3] = [Vector3(-x, ATTACH_Y, wl["zf"]), Vector3(x, ATTACH_Y, wl["zf"]),
		Vector3(-x, ATTACH_Y, wl["zr"]), Vector3(x, ATTACH_Y, wl["zr"])]
	return out


static func get_car(id: String) -> Dictionary:
	return LIST[index_of(id)]


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return 0
