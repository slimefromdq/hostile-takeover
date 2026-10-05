class_name MapLayout
extends RefCounted

# Civic Dividend: Downtown. Authored for the west half and mirrored across x=0 (Helix west, Monarch east).
# x runs west to east, z runs north (-) to south (+), y is up. All coordinates snap to 0.25 m in MapBuilder.
#
# Tiers: trench y=-4 | street y=0 | roofs/skybridges y=+6 | south perches y=+9.
# Rows (z): rear towers -60..-36 | north alley -36..-30 | north front blocks -30..-12 (roof route)
#           | boulevard -12..12 | rail 12..13 | sunken transit trench 13..29 | south blocks 29..35
#           | south alley 35..41 | rear towers 41..60.
# Columns (x): depot -91..-83 | runway -82..-79 | cross streets (12 m) at x=-64,-32,0 (and mirrors).

const BOUNDS := Rect2(-92, -60, 184, 120)
const POINT_X: Array[float] = [-64.0, -32.0, 0.0, 32.0, 64.0]
const SPAWN_X := 86.0
const DEPOT_LIMIT := 83.0
const TEST_LANE := Vector3(-20, 0.05, 0)
const CROSS_HALF := 6.0

const ROAD := Color("5c656f")
const PAVE := Color("78818a")
const ROOF := Color("737b84")
const TRENCH := Color("4f5963")
const COOL := Color("3a5a78")
const WARM := Color("7d4f48")
const NEUTRAL := Color("5d6270")
const COVER := Color("b3a27c")
const TOWER_COOL := Color("2f4458")
const TOWER_WARM := Color("5e3f3d")
const RAIL := Color("c9d0d4")

static func points() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for x in POINT_X:
		out.append(Vector3(x, 0, 0))
	return out

# Block intervals between cross streets (west half). Lobbies are 6 m cut-throughs at street level.
const INTERVALS := [[-82.0, -70.0, 0.0, 0.0], [-58.0, -38.0, -51.0, -45.0], [-26.0, -6.0, -20.0, -14.0]]

static func build(b: MapBuilder) -> void:
	_floors(b)
	_end_blocks(b)
	_north_band(b)
	_south_band(b)
	_towers(b)
	_boulevard(b)
	_trench(b)
	_decals(b)

# ---- floors -----------------------------------------------------------------

static func _floors(b: MapBuilder) -> void:
	b.block(-82, -60, 82, 13, -5, 0, "walk", ROAD, "floor_n")
	b.block(-82, 29, 82, 60, -5, 0, "walk", ROAD, "floor_s")
	b.block(-82, 13, 82, 29, -5, -4, "walk", TRENCH, "floor_trench")
	b.sunken.append(Rect2(-82, 13, 164, 16))

# ---- end blocks, depots and the gate vestibule --------------------------------

static func _end_blocks(b: MapBuilder) -> void:
	# Solid HQ masses so x>83 is only ever the sealed depot room.
	b.pair(-92, -60, -82, -13, -5, 30, "tower", TOWER_COOL, "end_n", TOWER_WARM)
	b.pair(-92, 13, -82, 60, -5, 30, "tower", TOWER_COOL, "end_s", TOWER_WARM)
	b.pair(-92, -13, -91, 13, -5, 30, "tower", TOWER_COOL, "depot_back", TOWER_WARM)
	b.pair(-91, -13, -82, 13, -5, 0, "walk", PAVE, "depot_floor", PAVE)
	b.pair(-91, -13, -82, 13, 6, 30, "tower", TOWER_COOL, "depot_roof", TOWER_WARM)
	# East wall of the depot with two 6 m gates (z -11..-5 and 5..11); lintels above.
	b.pair(-83, -13, -82, -11, 0, 6, "wall", COOL, "gate_wall_a", WARM)
	b.pair(-83, -5, -82, 5, 0, 6, "wall", COOL, "gate_wall_b", WARM)
	b.pair(-83, 11, -82, 13, 0, 6, "wall", COOL, "gate_wall_c", WARM)
	b.pair(-83, -11, -82, -5, 4, 6, "wall", COOL, "gate_lintel_n", WARM)
	b.pair(-83, 5, -82, 11, 4, 6, "wall", COOL, "gate_lintel_s", WARM)
	# Baffles stop the spawn having a straight line onto the boulevard; exits are 3 m / 6 m / 3 m.
	b.pair(-79, -9, -77, -3, 0, 3.5, "wall", COOL, "baffle_n", WARM)
	b.pair(-79, 3, -77, 9, 0, 3.5, "wall", COOL, "baffle_s", WARM)

# ---- north front blocks: rooftop route -----------------------------------------

static func _north_band(b: MapBuilder) -> void:
	for iv in INTERVALS:
		var x0: float = iv[0]
		var x1: float = iv[1]
		var l0: float = iv[2]
		var l1: float = iv[3]
		if l1 > l0:
			b.pair(x0, -30, l0, -12, 0, 5.5, "tower", COOL, "nb", WARM)
			b.pair(l1, -30, x1, -12, 0, 5.5, "tower", COOL, "nb", WARM)
		else:
			b.pair(x0, -30, x1, -12, 0, 5.5, "tower", COOL, "nb", WARM)
		b.pair(x0, -30, x1, -12, 5.5, 6, "walk", ROOF, "roof_n", ROOF)
		b.pair(x0, -12.5, x1, -12, 6, 7.1, "wall", RAIL, "parapet_s")
		b.pair(x0, -30, x1, -29.5, 6, 7.1, "wall", RAIL, "parapet_n")
	# Cross-street roof ramps (5 m wide; 7 m of street stays free) and skybridge decks.
	b.ramp_pair(-70, -27, -65, -12, 0, 0, 6, "-z", "walk", PAVE, "roof_ramp_A")
	b.ramp_pair(-38, -27, -33, -12, 0, 0, 6, "-z", "walk", PAVE, "roof_ramp_B")
	b.ramp(-6, -27, -2, -12, 0, 0, 6, "-z", "walk", PAVE, "roof_ramp_C_w")
	b.ramp(2, -27, 6, -12, 0, 0, 6, "-z", "walk", PAVE, "roof_ramp_C_e")
	b.pair(-70, -30, -58, -27, 5.25, 6, "walk", ROOF, "deck_A", ROOF)
	b.pair(-38, -30, -26, -27, 5.25, 6, "walk", ROOF, "deck_B", ROOF)
	b.block(-6, -30, 6, -27, 5.25, 6, "walk", ROOF, "deck_C")
	b.pair(-70, -30, -58, -29.5, 6, 7.1, "wall", RAIL, "deck_parapet_A")
	b.pair(-38, -30, -26, -29.5, 6, 7.1, "wall", RAIL, "deck_parapet_B")
	b.block(-6, -30, 6, -29.5, 6, 7.1, "wall", RAIL, "deck_parapet_C")
	# Rooftop penthouses alternate between the north and south halves of the roof so no straight line
	# runs the length of the route; the open half is the walking lane.
	b.pair(-79.5, -29.5, -75.5, -20.5, 6, 8.8, "cover", COVER, "penthouse")
	b.pair(-56, -29.5, -52, -20.5, 6, 8.8, "cover", COVER, "penthouse")
	b.pair(-42, -21.5, -39, -12.5, 6, 8.8, "cover", COVER, "penthouse")
	b.pair(-24, -21.5, -20, -12.5, 6, 8.8, "cover", COVER, "penthouse")
	b.pair(-13, -29.5, -10, -20.5, 6, 8.8, "cover", COVER, "penthouse")

# ---- south front blocks: parkour perches over the trench --------------------------

static func _south_band(b: MapBuilder) -> void:
	for iv in INTERVALS:
		b.pair(iv[0], 29, iv[1], 35, 0, 8.5, "tower", COOL, "sb", WARM)
		b.pair(iv[0], 29, iv[1], 35, 8.5, 9, "walk", ROOF, "roof_s", ROOF)

# ---- rear towers (solid skyline that closes the playable volume) -------------------

static func _towers(b: MapBuilder) -> void:
	var north := [[-82.0, -62.0, 24.0], [-62.0, -42.0, 34.0], [-42.0, -22.0, 20.0], [-22.0, 0.0, 30.0]]
	var south := [[-82.0, -60.0, 28.0], [-60.0, -40.0, 22.0], [-40.0, -20.0, 36.0], [-20.0, 0.0, 26.0]]
	for t in north:
		b.pair(t[0], -60, t[1], -36, 0, t[2], "tower", TOWER_COOL, "tower_n", TOWER_WARM)
	for t in south:
		b.pair(t[0], 41, t[1], 60, 0, t[2], "tower", TOWER_COOL, "tower_s", TOWER_WARM)
	# Service blocks (transformers, dumpster stacks) alternate sides of each alley so no line runs it end to end.
	for x in [[-80.0, -77.0], [-57.0, -54.0], [-25.0, -22.0]]:
		b.pair(x[0], -36, x[1], -33, 0, 2.6, "cover", COVER, "alley_n")
		b.pair(x[0], 38, x[1], 41, 0, 2.6, "cover", COVER, "alley_s")
	for x in [[-43.0, -40.0], [-12.0, -9.0]]:
		b.pair(x[0], -33, x[1], -30, 0, 2.6, "cover", COVER, "alley_n")
		b.pair(x[0], 35, x[1], 38, 0, 2.6, "cover", COVER, "alley_s")

# ---- boulevard: A dock, B hub, C plaza ---------------------------------------------

static func _boulevard(b: MapBuilder) -> void:
	# A: dock ledges (1.2 m vault high ground) and east barriers shielding the capture bowl.
	b.pair(-72, -7, -68, -4, 0, 1.2, "cover", COVER, "dock_n")
	b.pair(-72, 4, -68, 7, 0, 1.2, "cover", COVER, "dock_s")
	b.pair(-57, -9, -55.5, -4, 0, 2.4, "cover", COVER, "barrier_n")
	b.pair(-57, 4, -55.5, 9, 0, 2.4, "cover", COVER, "barrier_s")
	# Tram portals: two offset 2.6 m walls 3 m apart. Wall 1 is open at z -9..-3 and 3..9, wall 2 is solid
	# there and open elsewhere, so no straight line crosses a portal and the boulevard is split into rooms.
	_portal(b, -44, -40)
	_portal(b, -26, -22)
	# B: a booth and cover that leave the capture disc open.
	b.pair(-37, 6, -34, 9, 0, 2.4, "cover", COVER, "booth")
	# C: kiosks flank the centre line; low planters ring the disc; gallery ledges give a 3 m high ground.
	b.pair(-12, 1.5, -9, 4.5, 0, 2.4, "cover", COVER, "kiosk")
	b.pair(-12, -4.5, -9, -1.5, 0, 2.4, "cover", COVER, "kiosk")
	b.pair(-10, 9, -7, 12, 0, 2.6, "cover", COVER, "kiosk_edge")
	b.pair(-8, 6, -4, 7, 0, 1.2, "cover", COVER, "planter")
	b.pair(-8, -7, -4, -6, 0, 1.2, "cover", COVER, "planter")
	b.pair(-20, -12, -12, -8, 2.6, 3.0, "walk", ROOF, "gallery_ledge")
	b.pair(-12.75, -9, -12, -8, 0, 2.6, "wall", RAIL, "gallery_post")
	b.ramp_pair(-12, -12, -4, -8, 0, 0, 3, "-x", "walk", PAVE, "gallery_ramp")
	b.pair(-20, -8.25, -12, -8, 3, 4.1, "wall", RAIL, "gallery_rail")

static func _portal(b: MapBuilder, x1: float, x2: float) -> void:
	var h := 2.6
	b.pair(x1, -12, x1 + 1, -9, 0, h, "cover", COVER, "portal1")
	b.pair(x1, -3, x1 + 1, 3, 0, h, "cover", COVER, "portal1")
	b.pair(x1, 9, x1 + 1, 12, 0, h, "cover", COVER, "portal1")
	b.pair(x2, -9, x2 + 1, -3, 0, h, "cover", COVER, "portal2")
	b.pair(x2, 3, x2 + 1, 9, 0, h, "cover", COVER, "portal2")

# ---- sunken transit trench -----------------------------------------------------------

static func _trench(b: MapBuilder) -> void:
	# Rail along the boulevard edge with gaps at cross streets and ramps.
	var gaps := [[-82.0, -82.0], [-78.0, -72.0], [-70.0, -58.0], [-50.0, -44.0], [-38.0, -26.0], [-20.0, -14.0], [-6.0, 6.0], [14.0, 20.0], [26.0, 38.0], [44.0, 50.0], [58.0, 70.0], [72.0, 78.0]]
	var cursor := -82.0
	for g in gaps:
		if g[0] > cursor + 0.01:
			b.block(cursor, 12, g[0], 13, 0, 1.1, "wall", RAIL, "rail")
		cursor = maxf(cursor, g[1])
	if cursor < 82.0:
		b.block(cursor, 12, 82, 13, 0, 1.1, "wall", RAIL, "rail")
	# Descent ramps (10 m run, 4 m drop) leave 6 m of trench floor beside them.
	b.ramp_pair(-78, 13, -72, 23, -4, -4, 0, "-z", "walk", PAVE, "trench_ramp_A")
	b.ramp_pair(-50, 13, -44, 23, -4, -4, 0, "-z", "walk", PAVE, "trench_ramp_B")
	b.ramp_pair(-20, 13, -14, 23, -4, -4, 0, "-z", "walk", PAVE, "trench_ramp_C")
	# Street-level bridges carry the cross streets over the trench; tunnels read as roofed segments.
	b.pair(-70, 13, -58, 29, -0.75, 0, "walk", PAVE, "bridge_A", PAVE)
	b.pair(-38, 13, -26, 29, -0.75, 0, "walk", PAVE, "bridge_B", PAVE)
	b.block(-6, 13, 6, 29, -0.75, 0, "walk", PAVE, "bridge_C")
	b.pair(-65, 20, -63, 22, -4, -0.75, "wall", RAIL, "pier_A")
	b.pair(-33, 20, -31, 22, -4, -0.75, "wall", RAIL, "pier_B")
	b.block(-1, 20, 1, 22, -4, -0.75, "wall", RAIL, "pier_C")
	# Parked tram cars: south-side cover that leaves 12 m of open floor on the north side.
	b.pair(-45, 26, -39, 29, -4, -1, "cover", COVER, "tram_car")
	b.pair(-13, 26, -7, 29, -4, -1, "cover", COVER, "tram_car")
	# Chicane baffles: two offset walls so no straight line runs the length of the trench.
	b.pair(-61, 13, -60, 22, -4, -1, "cover", COVER, "baffle_a")
	b.pair(-57, 20, -56, 29, -4, -1, "cover", COVER, "baffle_b")
	b.pair(-29, 13, -28, 22, -4, -1, "cover", COVER, "baffle_c")
	b.pair(-25, 20, -24, 29, -4, -1, "cover", COVER, "baffle_d")

# ---- flush decals ---------------------------------------------------------------------

static func _decals(b: MapBuilder) -> void:
	# Lane dashes on the boulevard (4 cm proud of the road so they never z-fight).
	var x := -80.0
	while x < 80.0:
		b.decor_block(x, -0.1, x + 3, 0.1, 0.0, 0.04, "accent", Color("e8e4d0"), "flush", "dash")
		x += 8.0
	# Trench wall light strips 4 cm proud of the retaining walls, split around ramps.
	var ramps := [[-78.0, -72.0], [-50.0, -44.0], [-20.0, -14.0], [14.0, 20.0], [44.0, 50.0], [72.0, 78.0]]
	var cursor := -82.0
	for r in ramps:
		b.decor_block(cursor, 13.0, r[0], 13.04, -3.0, -2.8, "accent", Color("ffd36b"), "flush", "trench_strip_n")
		cursor = r[1]
	b.decor_block(cursor, 13.0, 82, 13.04, -3.0, -2.8, "accent", Color("ffd36b"), "flush", "trench_strip_n")
	b.decor_block(-82, 28.96, 82, 29.0, -3.0, -2.8, "accent", Color("ffd36b"), "flush", "trench_strip_s")


# ---- waypoint graph for bots ---------------------------------------------------------------
# Authored for the west half; east nodes are generated with an "e_" prefix. Edges are walk/ramp only
# (bots never need jumps). Tags choose the route family: blv, roof, trn, aln.

const NODES := {
	"S": Vector3(-86, 0, 0), "gN": Vector3(-82.5, 0, -8), "gS": Vector3(-82.5, 0, 8),
	"rN": Vector3(-80.5, 0, -8), "rC": Vector3(-80.5, 0, 0), "rS": Vector3(-80.5, 0, 8),
	"rNn": Vector3(-80.5, 0, -10.5), "rSs": Vector3(-80.5, 0, 10.5),
	"xN": Vector3(-76, 0, -10.5), "xC": Vector3(-75, 0, 0), "xS": Vector3(-76, 0, 10.5),
	"A": Vector3(-64, 0, 0), "a1": Vector3(-52, 0, 0), "B": Vector3(-32, 0, 0), "C": Vector3(0, 0, 0),
	"pa": Vector3(-47, 0, -6), "w1": Vector3(-43.5, 0, -6), "g1": Vector3(-41.5, 0, -6), "g2": Vector3(-41.5, 0, 0), "w2": Vector3(-38, 0, 0),
	"pb": Vector3(-28.5, 0, -6), "w3": Vector3(-25.5, 0, -6), "g3": Vector3(-23.5, 0, -6), "g4": Vector3(-23.5, 0, 0), "w4": Vector3(-19, 0, 0), "b2": Vector3(-14, 0, 0),
	"lAb": Vector3(-61.5, 0, -10), "lAm": Vector3(-61.5, 0, -20), "lAn": Vector3(-61.5, 0, -33),
	"aN1": Vector3(-48, 0, -32), "lBn": Vector3(-29.5, 0, -33), "aN3": Vector3(-17, 0, -32),
	"n1": Vector3(-58.5, 0, -31.5), "n2": Vector3(-52.5, 0, -31.5), "q1": Vector3(-44.5, 0, -34.5), "q2": Vector3(-38.5, 0, -34.5), "n4": Vector3(-35, 0, -33),
	"s1": Vector3(-26.5, 0, -31.5), "s2": Vector3(-20.5, 0, -31.5), "u1": Vector3(-13.5, 0, -34.5), "u2": Vector3(-7.5, 0, -34.5),
	"lBm": Vector3(-29.5, 0, -20), "lBb": Vector3(-29.5, 0, -10),
	"blN": Vector3(-48, 0, -10.5), "lobN1": Vector3(-48, 0, -20), "lobN2": Vector3(-48, 0, -29),
	"blM": Vector3(-17, 0, -10.5), "lobM1": Vector3(-17, 0, -20), "lobM2": Vector3(-17, 0, -29),
	"cNb": Vector3(0, 0, -10), "cNm": Vector3(0, 0, -20), "cNn": Vector3(0, 0, -33),
	"sA0": Vector3(-64, 0, 11), "sA1": Vector3(-64, 0, 20), "sA2": Vector3(-64, 0, 32), "sA3": Vector3(-64, 0, 38), "v1": Vector3(-58.5, 0, 36.5), "v2": Vector3(-52.5, 0, 36.5), "v3": Vector3(-48, 0, 38), "z1": Vector3(-44.5, 0, 39.5), "z2": Vector3(-38.5, 0, 39.5), "y1": Vector3(-26.5, 0, 36.5), "y2": Vector3(-20.5, 0, 36.5), "y3": Vector3(-14.5, 0, 39.5), "y4": Vector3(-7.5, 0, 39.5),
	"sB0": Vector3(-32, 0, 11), "sB1": Vector3(-32, 0, 20), "sB2": Vector3(-32, 0, 32), "sB3": Vector3(-32, 0, 38),
	"sC0": Vector3(0, 0, 11), "sC1": Vector3(0, 0, 20), "sC2": Vector3(0, 0, 32), "sC3": Vector3(0, 0, 38),
	"tAt": Vector3(-75, 0, 11.5), "tAr": Vector3(-75, 0, 13), "tAq": Vector3(-75, -4, 23), "tAb": Vector3(-75, -4, 24),
	"t1": Vector3(-67, -4, 24), "t1b": Vector3(-62.5, -4, 24), "c1": Vector3(-58.5, -4, 24), "c2": Vector3(-58.5, -4, 17),
	"c3": Vector3(-54, -4, 17), "c4": Vector3(-50.5, -4, 24),
	"tBb": Vector3(-47, -4, 24), "tBq": Vector3(-47, -4, 23), "tBr": Vector3(-47, 0, 13), "tBt": Vector3(-47, 0, 11.5),
	"t3": Vector3(-38, -4, 24), "t4": Vector3(-32, -4, 24), "d0": Vector3(-30, -4, 24), "d1": Vector3(-26.5, -4, 24), "d2": Vector3(-26.5, -4, 17), "d3": Vector3(-22.5, -4, 17), "t5": Vector3(-21.5, -4, 24),
	"tCb": Vector3(-17, -4, 24), "tCq": Vector3(-17, -4, 23), "tCr": Vector3(-17, 0, 13), "tCt": Vector3(-17, 0, 11.5),
	"t6": Vector3(-8, -4, 24), "tC": Vector3(0, -4, 24),
	"rAb": Vector3(-67.5, 0, -12), "rAt": Vector3(-67.5, 6, -27), "dkA": Vector3(-64, 6, -28.5),
	"r2a": Vector3(-57, 6, -28.5), "r2b": Vector3(-57, 6, -17), "r2c": Vector3(-48, 6, -17), "r2c2": Vector3(-45, 6, -25), "r2d": Vector3(-39.5, 6, -25),
	"r2e": Vector3(-37, 6, -28), "dkB": Vector3(-32, 6, -28.5), "dkBe": Vector3(-27.5, 6, -28.5),
	"rBt": Vector3(-35.5, 6, -27), "rBb": Vector3(-35.5, 0, -12),
	"r3a": Vector3(-25, 6, -28.5), "r3b": Vector3(-25, 6, -25), "r3c": Vector3(-17, 6, -25), "r3c2": Vector3(-15, 6, -17), "r3d": Vector3(-9, 6, -17), "r3e": Vector3(-7, 6, -28.5),
	"cBt": Vector3(-4, 6, -27), "cBb": Vector3(-4, 0, -12), "dkC": Vector3(0, 6, -28.5),
}

const LINKS := [
	["S", "gN", "blv"], ["S", "gS", "blv"], ["gN", "rN", "blv"], ["gS", "rS", "blv"], ["rN", "rC", "blv"], ["rC", "rS", "blv"],
	["rN", "rNn", "blv"], ["rS", "rSs", "blv"], ["rNn", "xN", "blv"], ["rSs", "xS", "blv"], ["rC", "xC", "blv"],
	["xC", "A", "blv"], ["xN", "lAb", "blv"], ["A", "lAb", "blv"], ["A", "a1", "blv"],
	["a1", "pa", "blv"], ["pa", "w1", "blv"], ["w1", "g1", "blv"], ["g1", "g2", "blv"], ["g2", "w2", "blv"], ["w2", "B", "blv"],
	["B", "pb", "blv"], ["pb", "w3", "blv"], ["w3", "g3", "blv"], ["g3", "g4", "blv"], ["g4", "w4", "blv"], ["w4", "b2", "blv"], ["b2", "C", "blv"],
	["lAb", "lAm", "aln"], ["lAm", "lAn", "aln"], ["lAn", "n1", "aln"], ["n1", "n2", "aln"], ["n2", "aN1", "aln"], ["aN1", "q1", "aln"], ["q1", "q2", "aln"], ["q2", "n4", "aln"], ["n4", "lBn", "aln"], ["lBn", "s1", "aln"], ["s1", "s2", "aln"], ["s2", "aN3", "aln"], ["aN3", "u1", "aln"], ["u1", "u2", "aln"], ["u2", "cNn", "aln"],
	["lBn", "lBm", "aln"], ["lBm", "lBb", "aln"], ["lBb", "B", "blv"],
	["blN", "a1", "blv"], ["blN", "lobN1", "aln"], ["lobN1", "lobN2", "aln"], ["lobN2", "aN1", "aln"],
	["blM", "b2", "blv"], ["blM", "lobM1", "aln"], ["lobM1", "lobM2", "aln"], ["lobM2", "aN3", "aln"],
	["C", "cNb", "blv"], ["cNb", "cNm", "aln"], ["cNm", "cNn", "aln"],
	["A", "sA0", "blv"], ["sA0", "sA1", "aln"], ["sA1", "sA2", "aln"], ["sA2", "sA3", "aln"],
	["B", "sB0", "blv"], ["sB0", "sB1", "aln"], ["sB1", "sB2", "aln"], ["sB2", "sB3", "aln"],
	["C", "sC0", "blv"], ["sC0", "sC1", "aln"], ["sC1", "sC2", "aln"], ["sC2", "sC3", "aln"],
	["sA3", "v1", "aln"], ["v1", "v2", "aln"], ["v2", "v3", "aln"], ["v3", "z1", "aln"], ["z1", "z2", "aln"], ["z2", "sB3", "aln"], ["sB3", "y1", "aln"], ["y1", "y2", "aln"], ["y2", "y3", "aln"], ["y3", "y4", "aln"], ["y4", "sC3", "aln"],
	["xS", "tAt", "trn"], ["tAt", "tAr", "trn"], ["tAr", "tAq", "trn"], ["tAq", "tAb", "trn"], ["tAb", "t1", "trn"], ["t1", "t1b", "trn"],
	["t1b", "c1", "trn"], ["c1", "c2", "trn"], ["c2", "c3", "trn"], ["c3", "c4", "trn"], ["c4", "tBb", "trn"],
	["tBb", "t3", "trn"], ["t3", "t4", "trn"], ["t4", "d0", "trn"], ["d0", "d1", "trn"], ["d1", "d2", "trn"], ["d2", "d3", "trn"], ["d3", "t5", "trn"], ["t5", "tCb", "trn"], ["tCb", "t6", "trn"], ["t6", "tC", "trn"],
	["tBb", "tBq", "trn"], ["tBq", "tBr", "trn"], ["tBr", "tBt", "trn"], ["tBt", "a1", "blv"],
	["tCb", "tCq", "trn"], ["tCq", "tCr", "trn"], ["tCr", "tCt", "trn"], ["tCt", "b2", "blv"],
	["A", "rAb", "blv"], ["rAb", "rAt", "roof"], ["rAt", "dkA", "roof"], ["dkA", "r2a", "roof"], ["r2a", "r2b", "roof"], ["r2b", "r2c", "roof"], ["r2c", "r2c2", "roof"],
	["r2c2", "r2d", "roof"], ["r2d", "r2e", "roof"], ["r2e", "dkB", "roof"], ["dkB", "dkBe", "roof"], ["dkBe", "r3a", "roof"], ["r3a", "r3b", "roof"],
	["r3b", "r3c", "roof"], ["r3c", "r3c2", "roof"], ["r3c2", "r3d", "roof"], ["r3d", "r3e", "roof"], ["r3e", "dkC", "roof"], ["dkC", "cBt", "roof"], ["cBt", "cBb", "roof"], ["cBb", "C", "blv"],
	["r2e", "rBt", "roof"], ["rBt", "rBb", "roof"], ["rBb", "B", "blv"],
]

static func _mirror_name(n: String) -> String:
	return n if NODES[n].x == 0.0 else "e_" + n

# Full graph (both teams): {"nodes": {name: Vector3}, "links": [[a, b, tag], ...]}.
static func graph() -> Dictionary:
	var nodes := {}
	var links: Array = []
	for n in NODES:
		var v: Vector3 = NODES[n]
		nodes[n] = v
		if v.x != 0.0:
			nodes["e_" + n] = Vector3(-v.x, v.y, v.z)
	for l in LINKS:
		links.append([l[0], l[1], l[2]])
		var a := _mirror_name(l[0])
		var b := _mirror_name(l[1])
		if a != l[0] or b != l[1]:
			links.append([a, b, l[2]])
	return {"nodes": nodes, "links": links}
