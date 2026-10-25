class_name Maps
extends RefCounted
## Stage definitions. TrackBuilder turns one of these into a world.
##
## points    : route (x, z) in metres, start line first, heading -Z (on a
##             point-to-point stage the finish line is the last point)
## sections  : [lap fraction, surface] where each surface starts
## elevation : [lap fraction, metres] keyframes, smoothly interpolated
## jumps     : [lap fraction, height, half-length in metres] crests
## village   : [from, to] lap fractions lined with houses (or a list of them)
## forest    : tree count multiplier
## optional  : point_to_point (start and finish in different places, no
##             laps; fractions then run from the start to the finish),
##             theme ("wasteland", "jungle", "circuit", "moon", "city" or
##             "alpine": then cliffs [[from, to, side]], valley_floor,
##             massif [x, slope], waterfall and snow_line, see CliffRoad),
##             geo (a stage baked from a real road and its terrain: then no
##             points or elevation, see GeoStage; snow_line, forest_band),
##             tunnel [from, to], water [[x0, z0, x1, z1], ...] with water_level
##             (a route section on "ford" dips under it, one on "wood" becomes a
##             bridge over it), landmark [x, z, size] (the jungle pyramid),
##             gravity (m/s^2, default Earth's), no_rain, width (road width
##             multiplier), and on the Moon
##             craters [[x, z, radius, depth], ...], crater_field (how many
##             small random ones) and base [[from, to], ...] lined with modules

const LIST := [
	{
		"id": "col_de_pixel",
		"name": "COL DE PIXEL",
		"blurb": "Mixed. Village, forest jump, mountain hairpins",
		"seed": 1998,
		"points": [
			Vector2(0, 0), Vector2(0, -180), Vector2(8, -235), Vector2(45, -262),
			Vector2(180, -262), Vector2(215, -280), Vector2(222, -330), Vector2(245, -372),
			Vector2(218, -412), Vector2(238, -452), Vector2(290, -478), Vector2(380, -470),
			Vector2(450, -430), Vector2(520, -458), Vector2(590, -425), Vector2(636, -394),
			Vector2(676, -362), Vector2(676, -312), Vector2(632, -300), Vector2(585, -260),
			Vector2(565, -180), Vector2(580, -100), Vector2(618, -40), Vector2(602, 15),
			Vector2(540, 40), Vector2(460, 30), Vector2(400, 70), Vector2(330, 52),
			Vector2(282, 68), Vector2(240, 78), Vector2(226, 104), Vector2(252, 124),
			Vector2(320, 126), Vector2(356, 136), Vector2(350, 170), Vector2(300, 176),
			Vector2(200, 172), Vector2(130, 160), Vector2(70, 120), Vector2(25, 70),
		],
		"sections": [[0.00, "asphalt"], [0.25, "gravel"], [0.60, "asphalt"], [0.86, "gravel"], [0.96, "asphalt"]],
		"elevation": [[0.00, 0.0], [0.12, 0.0], [0.22, 4.0], [0.30, 10.0], [0.38, 6.0], [0.45, 12.0],
			[0.52, 13.0], [0.57, 8.0], [0.63, 12.0], [0.70, 22.0], [0.78, 17.0], [0.86, 6.0], [0.93, 1.0]],
		"jumps": [[0.525, 1.1, 14.0]],
		"village": [0.07, 0.22],
		"forest": 1.0,
	},
	{
		"id": "aquila_pass",
		"name": "AQUILA PASS",
		"blurb": "Point to point. Cliff road, hairpins, 130 m climb",
		"seed": 1203,
		# a proper rally stage, from the valley to the col: along the river,
		# up a road cut into the cliffs over the gorge (a waterfall spills
		# across it), four gravel hairpins up the face, then the summit road
		# along the top of the drop and onto the ice below the pass
		"point_to_point": true,
		"points": [
			Vector2(0, 0), Vector2(0, -110), Vector2(12, -170), Vector2(40, -215), Vector2(48, -270), Vector2(35, -330),
			Vector2(25, -400), Vector2(30, -480), Vector2(15, -550), Vector2(25, -630), Vector2(45, -700), Vector2(38, -770),
			Vector2(20, -822), Vector2(14, -844), Vector2(0, -852), Vector2(-14, -844), Vector2(-20, -822), Vector2(-22, -760),
			Vector2(-20, -680), Vector2(-26, -656), Vector2(-40, -648), Vector2(-54, -656), Vector2(-60, -680), Vector2(-62, -770),
			Vector2(-60, -840), Vector2(-66, -864), Vector2(-80, -872), Vector2(-94, -864), Vector2(-100, -840), Vector2(-102, -740),
			Vector2(-100, -660), Vector2(-106, -636), Vector2(-120, -628), Vector2(-134, -636), Vector2(-140, -660), Vector2(-142, -760),
			Vector2(-148, -860), Vector2(-150, -960), Vector2(-132, -1040), Vector2(-150, -1120), Vector2(-185, -1185), Vector2(-182, -1265),
			Vector2(-205, -1330), Vector2(-245, -1365), Vector2(-290, -1372),
		],
		"sections": [[0.00, "asphalt"], [0.255, "wet"], [0.285, "asphalt"], [0.352, "gravel"], [0.72, "asphalt"],
			[0.885, "ice"], [0.99, "asphalt"]],
		"elevation": [[0.00, 0.0], [0.05, 1.0], [0.14, 4.0], [0.35, 38.0], [0.378, 41.0], [0.436, 50.0], [0.47, 54.0],
			[0.535, 65.0], [0.57, 69.0], [0.643, 81.0], [0.678, 85.0], [0.72, 93.0], [0.80, 108.0], [0.87, 116.0],
			[0.93, 124.0], [0.98, 128.0]],
		"jumps": [[0.105, 1.0, 13.0]],
		"village": [[0.0, 0.07]],
		"forest": 1.3,
		"theme": "alpine",
		# [from, to, side the drop is on: 1 right, -1 left]; rock wall on the other
		"cliffs": [[0.14, 0.352, 1], [0.38, 0.443, -1], [0.472, 0.543, 1], [0.573, 0.650, -1], [0.68, 0.965, 1]],
		"valley_floor": -32.0,
		"massif": [0.0, 0.6],  # the mountain rises west of x = 0, 0.6 m per metre
		"waterfall": 0.27,
		"snow_line": 112.0,
		"water": [[100, -1700, 128, 400]],
		"water_level": -34.5,
	},
	{
		"id": "turini",
		"name": "TURINI",
		"blurb": "Point to point. A real road: 8 hairpins, 500 m climb",
		"seed": 1973,
		# the climb from La Bollene-Vesubie towards the Col de Turini in the
		# Alpes-Maritimes, lifted from OpenStreetMap with the real mountains
		# round it (data/stages/turini, see tools/real_stage); 1.3x life size.
		# A wet patch in the shady gully, and ice up near the snow line.
		"geo": "turini",
		"point_to_point": true,
		"sections": [[0.00, "asphalt"], [0.47, "wet"], [0.53, "asphalt"], [0.87, "ice"], [0.95, "asphalt"]],
		"village": [],
		"forest": 1.4,
		"forest_band": 3200,
		"theme": "alpine",
		"snow_line": 480.0,
		"width": 0.8,
	},
	{
		"id": "city",
		"name": "DOWNTOWN GP",
		"blurb": "Tarmac and cobbles. Walled streets, square corners",
		"seed": 2001,
		# a street circuit round the blocks: down the main avenue, a chicane on
		# the riverside road, the cobbled old square and back along the boulevard.
		# The corners are true arcs (radius 36-50 m) on wider streets, so the
		# walls stay off the racing line
		"points": [
			Vector2(0, 0), Vector2(0, -55), Vector2(0, -110), Vector2(0, -165), Vector2(0, -219), Vector2(0, -274),
			Vector2(0, -329), Vector2(0, -384), Vector2(1, -393), Vector2(4, -402), Vector2(8, -410), Vector2(13, -417),
			Vector2(20, -422), Vector2(28, -426), Vector2(37, -429), Vector2(46, -430), Vector2(94, -430), Vector2(142, -430),
			Vector2(189, -430), Vector2(200, -431), Vector2(209, -436), Vector2(241, -456), Vector2(250, -461), Vector2(261, -462),
			Vector2(309, -462), Vector2(320, -461), Vector2(329, -456), Vector2(361, -436), Vector2(370, -431), Vector2(381, -430),
			Vector2(418, -430), Vector2(454, -430), Vector2(463, -429), Vector2(472, -426), Vector2(480, -422), Vector2(487, -417),
			Vector2(492, -410), Vector2(496, -402), Vector2(499, -393), Vector2(500, -384), Vector2(500, -334), Vector2(500, -283),
			Vector2(500, -232), Vector2(500, -182), Vector2(499, -173), Vector2(496, -164), Vector2(491, -156), Vector2(484, -149),
			Vector2(476, -144), Vector2(467, -141), Vector2(458, -140), Vector2(411, -140), Vector2(364, -140), Vector2(355, -139),
			Vector2(346, -136), Vector2(338, -131), Vector2(331, -124), Vector2(326, -116), Vector2(323, -107), Vector2(322, -98),
			Vector2(322, -48), Vector2(322, 1), Vector2(322, 51), Vector2(321, 61), Vector2(318, 70), Vector2(312, 78),
			Vector2(305, 85), Vector2(297, 91), Vector2(288, 94), Vector2(278, 95), Vector2(221, 95), Vector2(164, 95),
			Vector2(107, 95), Vector2(50, 95), Vector2(40, 94), Vector2(31, 91), Vector2(22, 87), Vector2(15, 80),
			Vector2(8, 73), Vector2(4, 64), Vector2(1, 55), Vector2(0, 45),
		],
		"sections": [[0.00, "asphalt"], [0.55, "cobbles"], [0.66, "asphalt"]],
		"elevation": [[0.00, 0.0], [0.20, 1.0], [0.40, 3.0], [0.55, 4.0], [0.70, 2.0], [0.85, 0.5]],
		"jumps": [],
		"village": [],
		"forest": 0.4,
		"theme": "city",
		"width": 1.25,
	},
	{
		"id": "jungle",
		"name": "JUNGLE TEMPLE",
		"blurb": "Gravel and mud. River ford, bridge, ruins",
		"seed": 2077,
		# a loop through the rainforest: over the river on a plank bridge, round
		# the lagoon and past the old temples, then back through the ford
		"points": [
			Vector2(0, 0), Vector2(0, -120), Vector2(-20, -200), Vector2(10, -270), Vector2(60, -300), Vector2(110, -330),
			Vector2(150, -375), Vector2(192, -392), Vector2(240, -400), Vector2(300, -395), Vector2(340, -440), Vector2(350, -510),
			Vector2(320, -570), Vector2(360, -620), Vector2(430, -610), Vector2(470, -560), Vector2(450, -490), Vector2(480, -430),
			Vector2(520, -380), Vector2(510, -300), Vector2(460, -250), Vector2(400, -260), Vector2(350, -220), Vector2(330, -150),
			Vector2(280, -110), Vector2(240, -80), Vector2(192, -66), Vector2(150, -55), Vector2(110, -20), Vector2(90, 40),
			Vector2(50, 80), Vector2(10, 60),
		],
		"sections": [[0.00, "gravel"], [0.10, "mud"], [0.16, "gravel"], [0.226, "wood"], [0.26, "gravel"], [0.40, "mud"],
			[0.47, "gravel"], [0.66, "mud"], [0.72, "gravel"], [0.824, "ford"], [0.86, "mud"], [0.90, "gravel"]],
		"elevation": [[0.00, 1.0], [0.10, 3.0], [0.19, 2.5], [0.222, 3.0], [0.262, 3.0], [0.30, 5.0], [0.36, 9.0],
			[0.43, 14.0], [0.50, 10.0], [0.56, 12.0], [0.63, 7.0], [0.70, 4.0], [0.78, 2.5], [0.805, 1.0],
			[0.833, -1.85], [0.852, -1.85], [0.875, 0.5], [0.92, 1.5]],
		"jumps": [[0.535, 0.9, 12.0]],
		"village": [[0.30, 0.36], [0.60, 0.70]],
		"forest": 3.2,
		"theme": "jungle",
		# the river and a lagoon
		"water": [[178, -900, 206, 400], [375, -575, 440, -515]],
		"water_level": -1.5,
		"landmark": [262, -235, 34],
	},
	{
		"id": "monaco_ruins",
		"name": "MONACO RUINS",
		"blurb": "The old GP circuit after the bombs fell",
		"seed": 1945,
		# the Monaco street circuit, roughly to scale: Sainte Devote, Beau
		# Rivage up to Casino Square, Mirabeau, the Grand Hotel hairpin,
		# Portier, the tunnel, the chicane, Tabac, the swimming pool,
		# La Rascasse and Anthony Noghes
		"points": [
			Vector2(0, 0), Vector2(10, -175), Vector2(22, -300), Vector2(40, -356), Vector2(69, -381), Vector2(119, -394),
			Vector2(250, -431), Vector2(400, -481), Vector2(525, -538), Vector2(588, -588), Vector2(612, -650), Vector2(638, -700),
			Vector2(681, -731), Vector2(750, -731), Vector2(812, -700), Vector2(856, -656), Vector2(862, -600), Vector2(831, -550),
			Vector2(788, -515), Vector2(745, -505), Vector2(722, -482), Vector2(740, -452), Vector2(800, -442), Vector2(856, -431),
			Vector2(881, -388), Vector2(890, -338), Vector2(869, -294), Vector2(800, -244), Vector2(700, -188), Vector2(588, -144),
			Vector2(488, -125), Vector2(412, -120), Vector2(381, -110), Vector2(356, -125), Vector2(325, -125), Vector2(256, -122),
			Vector2(225, -106), Vector2(200, -78), Vector2(172, -65), Vector2(150, -38), Vector2(140, 0), Vector2(125, 50),
			Vector2(119, 138), Vector2(106, 188), Vector2(81, 215), Vector2(50, 212), Vector2(28, 181), Vector2(12, 125),
		],
		# rubble across Casino Square and the tunnel exit, the pool has flooded
		"sections": [[0.00, "asphalt"], [0.33, "gravel"], [0.37, "asphalt"], [0.72, "gravel"], [0.76, "asphalt"],
			[0.82, "wet"], [0.87, "asphalt"]],
		"elevation": [[0.00, 0.5], [0.09, 1.0], [0.115, 3.0], [0.18, 10.0], [0.30, 30.0], [0.355, 36.0], [0.42, 32.0],
			[0.485, 24.0], [0.54, 16.0], [0.575, 9.0], [0.62, 6.0], [0.72, 5.0], [0.745, 1.5], [0.80, 0.8], [0.95, 0.5]],
		"jumps": [],
		"village": [[0.02, 0.60], [0.86, 0.99]],
		"forest": 0.5,
		"theme": "wasteland",
		"tunnel": [0.612, 0.715],
		# [x0, z0, x1, z1]: Port Hercule and the sea
		"water": [[188, -375, 662, -156], [375, -75, 1700, 900]],
		"water_level": -1.5,
	},
	{
		"id": "pine_forest",
		"name": "PINE FOREST",
		"blurb": "Gravel. Fast, flowing, two crests",
		"seed": 4242,
		"points": [
			Vector2(0, 0), Vector2(0, -140), Vector2(30, -210), Vector2(90, -240),
			Vector2(150, -220), Vector2(190, -260), Vector2(260, -270), Vector2(320, -230),
			Vector2(330, -160), Vector2(290, -110), Vector2(300, -50), Vector2(360, -20),
			Vector2(400, 40), Vector2(380, 110), Vector2(310, 140), Vector2(240, 120),
			Vector2(190, 150), Vector2(120, 170), Vector2(60, 130), Vector2(20, 70),
		],
		"sections": [[0.00, "asphalt"], [0.06, "gravel"], [0.95, "asphalt"]],
		"elevation": [[0.00, 0.0], [0.10, 2.0], [0.20, 8.0], [0.30, 5.0], [0.40, 12.0], [0.50, 9.0],
			[0.60, 4.0], [0.70, 10.0], [0.80, 6.0], [0.90, 2.0]],
		"jumps": [[0.49, 1.0, 13.0], [0.875, 1.2, 14.0]],
		"village": [],
		"forest": 1.6,
	},
	{
		"id": "old_town",
		"name": "OLD TOWN",
		"blurb": "Tarmac. Tight town corners between walls",
		"seed": 777,
		"points": [
			Vector2(0, 0), Vector2(0, -160), Vector2(10, -190), Vector2(40, -200),
			Vector2(140, -200), Vector2(170, -190), Vector2(180, -160), Vector2(180, -100),
			Vector2(195, -75), Vector2(230, -65), Vector2(300, -65), Vector2(325, -50),
			Vector2(330, -20), Vector2(320, 10), Vector2(290, 20), Vector2(200, 20),
			Vector2(170, 35), Vector2(160, 70), Vector2(140, 95), Vector2(100, 100),
			Vector2(40, 100), Vector2(12, 85), Vector2(0, 60),
		],
		"sections": [[0.00, "asphalt"]],
		"elevation": [[0.00, 0.0], [0.30, 2.0], [0.55, 4.0], [0.80, 1.0]],
		"jumps": [],
		"village": [0.03, 0.97],
		"forest": 0.5,
	},
	{
		"id": "spa",
		"name": "SPA F1",
		"blurb": "Tarmac. Eau Rouge, Kemmel, Pouhon, Blanchimont",
		"seed": 1921,
		# Spa-Francorchamps, roughly to scale: La Source hairpin, down to Eau
		# Rouge and up Raidillon, the Kemmel straight to Les Combes, Malmedy,
		# Bruxelles, the Pouhon double left (where it always rains), Fagnes,
		# Stavelot, Blanchimont and the Bus Stop chicane
		"points": [
			Vector2(0, 0), Vector2(27, -108), Vector2(54, -194), Vector2(76, -225), Vector2(104, -220), Vector2(112, -194),
			Vector2(108, -108), Vector2(104, -18), Vector2(99, 72), Vector2(112, 126), Vector2(104, 180), Vector2(122, 234),
			Vector2(180, 342), Vector2(297, 504), Vector2(396, 648), Vector2(421, 688), Vector2(412, 720), Vector2(432, 747),
			Vector2(468, 774), Vector2(477, 837), Vector2(468, 864), Vector2(450, 891), Vector2(418, 878), Vector2(378, 864),
			Vector2(342, 891), Vector2(297, 954), Vector2(243, 999), Vector2(180, 999), Vector2(126, 972), Vector2(81, 954),
			Vector2(54, 972), Vector2(9, 990), Vector2(-36, 1008), Vector2(-63, 981), Vector2(-72, 900), Vector2(-54, 720),
			Vector2(-45, 540), Vector2(-63, 360), Vector2(-54, 225), Vector2(-27, 135), Vector2(-11, 104), Vector2(-23, 79),
			Vector2(-11, 56), Vector2(-4, 32),
		],
		"sections": [[0.00, "asphalt"], [0.53, "wet"], [0.60, "asphalt"]],
		"elevation": [[0.00, 10.0], [0.077, 12.0], [0.18, -2.0], [0.23, 14.0], [0.33, 26.0], [0.392, 30.0], [0.43, 28.0],
			[0.484, 20.0], [0.548, 10.0], [0.626, 7.0], [0.681, 0.0], [0.78, 2.0], [0.88, 5.0], [0.964, 9.0]],
		"jumps": [],
		"village": [[0.0, 0.03], [0.97, 1.0]],
		"forest": 1.3,
		"theme": "circuit",
	},
	{
		"id": "moon",
		"name": "LUNA BASE",
		"blurb": "Regolith and dust. Low gravity, long jumps, craters",
		"seed": 1969,
		# out from the base across the mare, round the rim of a big crater and
		# down through two crater floors of loose dust, then back past the
		# landing pads; a quarter of Earth's gravity, so the crests launch you
		"points": [
			Vector2(0, 0), Vector2(0, -195), Vector2(-20, -338), Vector2(-78, -442), Vector2(-182, -494), Vector2(-299, -481),
			Vector2(-390, -416), Vector2(-429, -312), Vector2(-403, -208), Vector2(-338, -143), Vector2(-325, -52), Vector2(-377, 26),
			Vector2(-455, 78), Vector2(-494, 182), Vector2(-455, 286), Vector2(-364, 338), Vector2(-247, 325), Vector2(-156, 260),
			Vector2(-78, 208), Vector2(13, 221), Vector2(104, 273), Vector2(195, 260), Vector2(247, 182), Vector2(234, 104),
			Vector2(156, 78), Vector2(78, 104), Vector2(26, 78),
		],
		"sections": [[0.00, "regolith"], [0.30, "dust"], [0.38, "regolith"], [0.66, "dust"], [0.74, "regolith"]],
		"elevation": [[0.00, 0.0], [0.10, 1.0], [0.20, 4.0], [0.27, 2.0], [0.31, -5.0], [0.36, -5.0], [0.40, 1.0],
			[0.48, 6.0], [0.56, 3.0], [0.63, 2.0], [0.67, -4.5], [0.72, -4.5], [0.76, 1.0], [0.85, 3.0], [0.93, 0.5]],
		"jumps": [[0.205, 1.4, 14.0], [0.555, 1.6, 15.0], [0.85, 1.3, 13.0]],
		"village": [],
		"forest": 1.0,
		"theme": "moon",
		"gravity": 4.0,
		"no_rain": true,
		"craters": [],
		"crater_field": 110,
		"base": [[0.02, 0.10], [0.47, 0.52], [0.90, 0.98]],
	},
]


## The map for an id; unknown ids fall back to the first map.
static func get_map(id: String) -> Dictionary:
	return LIST[index_of(id)]


static func index_of(id: String) -> int:
	for i in LIST.size():
		if LIST[i]["id"] == id:
			return i
	return 0
