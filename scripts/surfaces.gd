class_name Surfaces
extends RefCounted
## Driving surface table. Every road/terrain StaticBody3D carries a
## "surface" meta string that the car's wheel raycasts look up here.
##
## grip  : peak friction coefficient (most sideways force a tyre can make)
## peak  : slip angle (radians) where that grip peaks; bigger = softer, floatier
## slide : fraction of grip left deep into a slide (low = long slides, spins)
## drag  : rolling resistance coefficient (scrubs speed; high on grass)
## bump  : random vertical jitter, makes rough surfaces feel rough
## fx_always : kick up particles whenever moving, not only when sliding
## rain  : grip multiplier when it's raining (already-wet surfaces keep theirs)
## mark  : what sliding tyres leave behind: rubber, rut, mud, scrape or none

const ORDER := ["asphalt", "gravel", "wet", "ice", "grass", "mud", "ford", "wood"]

const DATA := {
	"asphalt": {"label": "ASPHALT", "peak": 0.08, "grip": 1.30, "slide": 0.80, "drag": 0.012, "bump": 0.00,
		"hud": Color(0.80, 0.80, 0.86), "fx": Color(0.85, 0.85, 0.85, 0.55), "fx_always": false,
		"rain": 0.74, "mark": "rubber"},
	"gravel": {"label": "GRAVEL", "peak": 0.15, "grip": 0.82, "slide": 0.82, "drag": 0.040, "bump": 0.035,
		"hud": Color(0.95, 0.72, 0.40), "fx": Color(0.78, 0.64, 0.44, 0.85), "fx_always": true,
		"rain": 0.9, "mark": "rut"},
	"wet": {"label": "WET", "peak": 0.09, "grip": 0.78, "slide": 0.50, "drag": 0.022, "bump": 0.00,
		"hud": Color(0.40, 0.62, 1.00), "fx": Color(0.80, 0.86, 0.95, 0.55), "fx_always": true,
		"rain": 0.95, "mark": "rubber"},
	"ice": {"label": "ICE", "peak": 0.08, "grip": 0.28, "slide": 0.62, "drag": 0.006, "bump": 0.00,
		"hud": Color(0.72, 0.96, 1.00), "fx": Color(0.95, 0.98, 1.00, 0.70), "fx_always": false,
		"rain": 0.9, "mark": "scrape"},
	"grass": {"label": "GRASS", "peak": 0.16, "grip": 0.62, "slide": 0.72, "drag": 0.110, "bump": 0.070,
		"hud": Color(0.45, 0.88, 0.32), "fx": Color(0.55, 0.50, 0.32, 0.55), "fx_always": true,
		"rain": 0.85, "mark": "mud"},
	"mud": {"label": "MUD", "peak": 0.17, "grip": 0.66, "slide": 0.74, "drag": 0.060, "bump": 0.050,
		"hud": Color(0.66, 0.46, 0.26), "fx": Color(0.36, 0.25, 0.14, 0.9), "fx_always": true,
		"rain": 0.85, "mark": "mud"},
	"ford": {"label": "RIVER", "peak": 0.12, "grip": 0.60, "slide": 0.62, "drag": 0.130, "bump": 0.025,
		"hud": Color(0.45, 0.80, 0.85), "fx": Color(0.88, 0.94, 0.98, 0.8), "fx_always": true,
		"rain": 1.0, "mark": "none"},
	"wood": {"label": "BRIDGE", "peak": 0.10, "grip": 1.00, "slide": 0.72, "drag": 0.016, "bump": 0.012,
		"hud": Color(0.80, 0.62, 0.38), "fx": Color(0.70, 0.62, 0.50, 0.5), "fx_always": false,
		"rain": 0.7, "mark": "rubber"},
}


static func get_surface(id: String) -> Dictionary:
	if DATA.has(id):
		return DATA[id]
	return DATA["grass"]
