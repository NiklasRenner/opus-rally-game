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
## mesh    : a model built in Blender (art/) instead of the lofted body; the
##           profile then only marks the nose. Modelled cars wear a "skin"
##           painted in pieces by art/cars/paint_skin.py; spokes: rim spokes.
## dents, parts: mesh nodes that dent, and [node, zone, threshold] bolt-ons
##           that fall off (cars default to body and bumpers / bumpers, wing,
##           light pod and mirrors)
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
		"mesh": "res://models/martello.glb",
		"profile": [[-2.01, 0.04, 0.0]],
		# skin painted in pieces by art/cars/paint_skin.py
		"skin": "res://models/martello_skin.png",
		"spokes": 8,
		"rims": Color(0.92, 0.92, 0.90),
		"flaps": Color(0.08, 0.20, 0.62),
		"stats": {"power": 1.0, "grip": 1.0, "steer": 1.0, "mass": 1200.0},
	},
	{
		"id": "pleiad",
		"name": "PLEIAD 555",
		"blurb": "Grippy saloon, gold wheels",
		"number": "5",
		"plate": "PL 555",
		"mesh": "res://models/pleiad.glb",
		"profile": [[-2.21, 0.04, 0.0]],
		"skin": "res://models/pleiad_skin.png",
		"spokes": 8,
		"rims": Color(0.85, 0.68, 0.22),
		"flaps": Color(0.95, 0.95, 0.95),
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
		"blurb": "Hybrid single-seater, huge downforce",
		"number": "1",
		"mesh": "res://models/veloce.glb",
		"profile": [[-2.62, 0.04, 0.0]],
		"skin": "res://models/veloce_skin.png",
		"rims": Color(0.08, 0.08, 0.09),
		"spokes": 0,  # flat wheel covers
		"rim_ring": Color(0.85, 0.08, 0.1),
		"flaps": Color(0.1, 0.1, 0.1),
		"helmet": Color(0.1, 0.1, 0.12),
		"helmet_pos": Vector3(0, -0.02, 0.05),
		"dents": ["Body", "Sidepod_L", "Sidepod_R"],
		# carbon fibre: wings snap off at a touch, sidepods soon after
		"parts": [["FrontWing", "front", 0.12], ["RearWing", "rear", 0.2], ["Sidepod_L", "left", 0.3],
			["Sidepod_R", "right", 0.3], ["Mirror_L", "left", 0.1], ["Mirror_R", "right", 0.1]],
		"wheels": {"x": 0.84, "zf": -1.72, "zr": 1.42, "rf": 0.32, "rr": 0.35, "wf": 0.3, "wr": 0.42},
		"stats": {"power": 2.0, "grip": 1.1, "steer": 0.95, "mass": 800.0,
			"gearing": 0.78, "drag": 0.7, "downforce": 3.5, "inertia": 0.85, "pitch": 1.45, "armour": 1.8},
		"shapes": [[Vector3(2.0, 0.26, 4.7), Vector3(0, -0.30, -0.15)], [Vector3(0.7, 0.4, 1.2), Vector3(0, 0.0, 0.4)]],
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
		# drag: extra air resistance (lower top speed), pivot: skid-steer turn on
		# the spot, armour: damage taken, pitch: engine note
		"stats": {"power": 0.95, "grip": 1.15, "steer": 0.9, "mass": 1800.0,
			"drag": 1.8, "pivot": 1.0, "armour": 0.25, "pitch": 0.4},
		"dents": ["Hull", "Turret", "SideSkirt_L", "SideSkirt_R", "SkirtArmor_L", "SkirtArmor_R"],
		"parts": [["SideSkirt_L", "left", 0.45], ["SideSkirt_R", "right", 0.45], ["SkirtArmor_L", "left", 0.7],
			["SkirtArmor_R", "right", 0.7], ["Headlight_L", "front", 0.3], ["Headlight_R", "front", 0.3],
			["TailLight_L", "rear", 0.3], ["TailLight_R", "rear", 0.3], ["StowageBasket", "rear", 0.35],
			["Antenna_1", "rear", 0.5], ["Antenna_2", "rear", 0.6], ["SmokeLauncher_L", "left", 0.6],
			["SmokeLauncher_R", "right", 0.6], ["MG_Loader", "front", 0.75]],
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
