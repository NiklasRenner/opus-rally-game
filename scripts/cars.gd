class_name Cars
extends RefCounted
## The cars you can pick in the menu: models built in Blender (art/) with
## a few small handling tweaks (kept close so records stay comparable).
##
## type    : "car" (default), "f1", "truck" or "tank"
## class   : racing class (see CLASSES); records and ghosts are kept per class
## ground_y: ground level in car space for the model (default -0.72)
## frame   : tube frame colour (the truck)
## mesh    : the model in models/; nose: z of its nose in car space
## skin    : its painted skin (art/cars/paint_skin.py); the tank is painted in code
## rims, spokes, rim_ring: wheel face colour, spoke count (0 = cover), tyre ring
## flaps   : mud flap colour
## number, plate: race number and number plate (also painted on the skin)
## dents, parts: mesh nodes that dent, and [node, zone, threshold] bolt-ons
##           that fall off (cars default to body and bumpers / bumpers, wing,
##           light pod and mirrors)
## helmet, helmet_pos: the F1 driver's helmet
## stats   : power, grip and steer multipliers, mass in kg (the tank adds a few more)
## wheels  : optional layout {x, zf, zr, rf, rr, wf, wr}: track half-width,
##           front/rear axle z, visual tyre radius and width per axle
## shapes  : optional collision boxes [size, centre]
## gears   : forward gear ratios, first to top (default GEARS); spaced so top
##           speed comes near the redline in top gear
## Extra stats: gearing (final drive multiplier, >1 = shorter gears / lower top
## speed), shift (gear change time vs a rally box), drag, downforce, inertia (yaw inertia vs a saloon), pitch (engine note).
## Chassis forces (springs, brakes, yaw assists) scale with mass so light and
## heavy vehicles handle alike; engine power does not, so mass still counts.

const LIST := [
	{
		"id": "martello",
		"class": "A",
		"name": "MARTELLO HF",
		"blurb": "Boxy hatch, all-rounder",
		"number": "4",
		"plate": "MH 4",
		"mesh": "res://models/martello.glb",
		"nose": -2.01,
		# skin painted in pieces by art/cars/paint_skin.py
		"skin": "res://models/martello_skin.png",
		"spokes": 8,
		"rims": Color(0.92, 0.92, 0.90),
		"flaps": Color(0.08, 0.20, 0.62),
		"gears": [3.3, 2.56, 2.05, 1.7, 1.45],
		"stats": {"power": 1.0, "grip": 1.0, "steer": 1.0, "mass": 1200.0},
	},
	{
		"id": "pleiad",
		"class": "A",
		"name": "PLEIAD 555",
		"blurb": "Grippy saloon, gold wheels",
		"number": "5",
		"plate": "PL 555",
		"mesh": "res://models/pleiad.glb",
		"nose": -2.21,
		"skin": "res://models/pleiad_skin.png",
		"spokes": 8,
		"rims": Color(0.85, 0.68, 0.22),
		"flaps": Color(0.95, 0.95, 0.95),
		"gears": [3.3, 2.5, 2.02, 1.72, 1.5, 1.32],
		"stats": {"power": 0.97, "grip": 1.04, "steer": 0.98, "mass": 1230.0},
	},
	{
		"id": "balear",
		"class": "A",
		"name": "BALEAR KIT",
		"blurb": "Little yellow kit car, quick to turn",
		"number": "15",
		"plate": "BK 15",
		"mesh": "res://models/balear.glb",
		"nose": -2.01,
		"skin": "res://models/balear_skin.png",
		"spokes": 6,
		"rims": Color(0.95, 0.95, 0.93),
		"flaps": Color(0.08, 0.20, 0.62),
		"gears": [3.3, 2.5, 2.0, 1.7, 1.48, 1.32],
		"stats": {"power": 0.98, "grip": 1.0, "steer": 1.05, "mass": 1120.0},
	},
	{
		"id": "f1",
		"class": "S",
		"type": "f1",
		"name": "VELOCE F1",
		"blurb": "Hybrid single-seater, huge downforce",
		"number": "1",
		"mesh": "res://models/veloce.glb",
		"nose": -2.62,
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
		# out-pulls the hypercar to 200 km/h; the wings' drag holds its top speed below it
		# eight-speed seamless-shift box, like the real thing
		"gears": [3.3, 2.68, 2.22, 1.87, 1.6, 1.39, 1.22, 1.09],
		"stats": {"power": 2.5, "grip": 1.1, "steer": 0.95, "mass": 800.0,
			"gearing": 0.78, "drag": 1.1, "downforce": 3.5, "inertia": 0.85, "pitch": 1.45, "armour": 1.8,
			"shift": 0.4},
		"shapes": [[Vector3(2.0, 0.26, 4.7), Vector3(0, -0.30, -0.15)], [Vector3(0.7, 0.4, 1.2), Vector3(0, 0.0, 0.4)]],
	},
	{
		"id": "bellatrix",
		"class": "S",
		"name": "BELLATRIX 16",
		"blurb": "Quad-turbo hypercar, blue and gunmetal",
		"number": "16",
		"plate": "BX 16",
		"mesh": "res://models/bellatrix.glb",
		"nose": -2.33,
		"skin": "res://models/bellatrix_skin.png",
		"spokes": 10,
		"rims": Color(0.22, 0.23, 0.25),
		"flaps": Color(0.1, 0.1, 0.1),
		# carbon splitter and diffuser go first, the light bar and flush spoiler after
		"parts": [["Bumper_F", "front", 0.3], ["Bumper_R", "rear", 0.35], ["Spoiler", "rear", 0.45],
			["LightBar", "rear", 0.6], ["Mirror_L", "left", 0.2], ["Mirror_R", "right", 0.2]],
		"wheels": {"x": 0.87, "zf": -1.4, "zr": 1.32, "rf": 0.36, "rr": 0.36, "wf": 0.3, "wr": 0.36},
		# heavy but brutally quick: behind the F1 up to 200 km/h, a little faster
		# flat out; lazy turn-in and less downforce, so it slides more in corners
		# seven-speed twin-clutch
		"gears": [3.3, 2.74, 2.29, 1.92, 1.62, 1.38, 1.18],
		"stats": {"power": 4.0, "grip": 1.04, "steer": 0.92, "mass": 1700.0,
			"gearing": 0.7, "drag": 0.7, "downforce": 1.8, "inertia": 1.35, "pitch": 0.85, "shift": 0.5},
		"shapes": [[Vector3(1.95, 0.57, 4.6), Vector3(0, -0.085, 0)], [Vector3(1.2, 0.26, 2.0), Vector3(0, 0.33, 0.2)]],
	},
	{
		"id": "swamp",
		"type": "truck",
		"class": "X",
		"name": "SWAMP KING",
		"blurb": "Monster truck: bouncy, soaks up the rough",
		"number": "7",
		"plate": "SK 7",
		"mesh": "res://models/swamp.glb",
		"nose": -2.45,
		# the wheels hang a long way below the chassis, so the ground is lower in car space
		"ground_y": -1.03,
		"skin": "res://models/swamp_skin.png",
		"rims": Color(1.0, 0.5, 0.05),
		"spokes": 8,
		"frame": Color(0.95, 0.12, 0.08),
		"tread": "chevron",
		"flaps": Color(0.1, 0.1, 0.1),
		"dents": ["Body"],
		"parts": [["LightBar", "front", 0.35], ["Mirror_L", "left", 0.25], ["Mirror_R", "right", 0.25]],
		"wheels": {"x": 1.05, "zf": -1.45, "zr": 1.45, "rf": 0.75, "rr": 0.75, "wf": 0.8, "wr": 0.8},
		# travel, spring, damper: long soft suspension that keeps bouncing;
		# bump_soak: how much rough ground still shakes it; roll_tame: lower lets it lean
		# three-speed slushbox: short first to heave the weight, big gaps after
		"gears": [3.5, 2.43, 1.79],
		"stats": {"power": 1.6, "grip": 1.06, "steer": 0.85, "mass": 2000.0, "gearing": 0.85, "drag": 1.5,
			"armour": 0.6, "travel": 2.0, "spring": 0.45, "damper": 0.35, "bump_soak": 0.35, "roll_tame": 0.3,
			"pitch": 0.7, "shift": 1.5},
		"shapes": [[Vector3(1.7, 0.45, 4.6), Vector3(0, 0.2, 0)], [Vector3(1.85, 0.62, 4.2), Vector3(0, 0.66, 0)],
			[Vector3(1.6, 0.44, 1.15), Vector3(0, 1.19, -0.22)], [Vector3(1.5, 0.6, 1.3), Vector3(0, 1.26, 1.22)]],
	},
	{
		"id": "pardel",
		"class": "X",
		"type": "tank",
		"name": "KPZ PARDEL",
		"blurb": "Boxy German heavy. Wedge turret, stabilised gun",
		"number": "211",
		"mesh": "res://models/leopard.glb",
		"nose": -2.28,
		# drag: extra air resistance (lower top speed), pivot: skid-steer turn on
		# the spot, armour: damage taken, pitch: engine note
		# four forward gears like the real tank's box, slow to change
		"gears": [3.5, 2.62, 2.08, 1.73],
		"stats": {"power": 0.95, "grip": 1.02, "steer": 0.9, "mass": 1800.0,
			"drag": 1.8, "pivot": 1.0, "armour": 0.25, "pitch": 0.4, "shift": 1.75},
		"dents": ["Hull", "Turret", "SideSkirt_L", "SideSkirt_R", "SkirtArmor_L", "SkirtArmor_R"],
		"parts": [["SideSkirt_L", "left", 0.45], ["SideSkirt_R", "right", 0.45], ["SkirtArmor_L", "left", 0.7],
			["SkirtArmor_R", "right", 0.7], ["Headlight_L", "front", 0.3], ["Headlight_R", "front", 0.3],
			["TailLight_L", "rear", 0.3], ["TailLight_R", "rear", 0.3], ["StowageBasket", "rear", 0.35],
			["Antenna_1", "rear", 0.5], ["Antenna_2", "rear", 0.6], ["SmokeLauncher_L", "left", 0.6],
			["SmokeLauncher_R", "right", 0.6], ["MG_Loader", "front", 0.75]],
		"shapes": [[Vector3(2.1, 0.6, 4.4), Vector3(0, 0.03, 0)], [Vector3(1.6, 0.42, 2.4), Vector3(0, 0.57, 0.15)]],
	},
]


const GEARS := [3.3, 2.2, 1.65, 1.3, 1.06]  # a spec without its own "gears"
const WHEELS := {"x": 0.82, "zf": -1.32, "zr": 1.28, "rf": 0.34, "rr": 0.34, "wf": 0.26, "wr": 0.26}
const REF_MASS := 1200.0
const WHEEL_RADIUS := 0.34  # every wheel's physics radius; small tyres are drawn lower
const ATTACH_Y := -0.05  # height of the suspension attach points


## Forward gear ratios for a spec, first gear first.
static func gears(spec: Dictionary) -> Array:
	return spec.get("gears", GEARS)


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


## Cars that have left the garage, so old records still show what they were set in.
const RETIRED := {"kaze": "KAZE GT4", "falke": "FALKE RS", "cuneo": "CUNEO STRADALE", "kart": "KART 125",
	"tank": "TANK T-98"}


## Racing classes, fastest first. Each keeps its own highscores, best laps and
## ghosts, so a rally car never chases an F1 time.
const CLASSES := {
	"S": {"name": "SUPER", "col": Color(0.95, 0.15, 0.1)},
	"A": {"name": "RALLY", "col": Color(1.0, 0.84, 0.1)},
	"X": {"name": "EXTREME", "col": Color(0.45, 0.75, 0.3)},
}
const DEFAULT_CLASS := "A"
## Classes of retired cars, for sorting their old records into the right table.
const RETIRED_CLASS := {"tank": "X"}


## Class letter for a car id, including retired cars.
static func class_of(id: String) -> String:
	if RETIRED.has(id):
		return RETIRED_CLASS.get(id, DEFAULT_CLASS)
	return get_car(id).get("class", DEFAULT_CLASS)


## Display name for a car id, including retired cars.
static func name_of(id: String) -> String:
	if RETIRED.has(id):
		return RETIRED[id]
	return get_car(id)["name"]


## The car for an id; unknown or retired ids fall back to the first car.
static func get_car(id: String) -> Dictionary:
	return LIST[index_of(id)]


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return 0
