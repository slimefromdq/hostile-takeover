class_name Loadout
extends RefCounted

# Every fighter has the same body (Fighter.MAX_HEALTH, the shared movement) and no abilities; what differs is the
# loadout, four items picked in the start menu: a primary, a sidearm (quick swap, its own magazine), a utility on Q
# and a melee on F. Pure data plus the packing rules; combat lives in game.gd (use_utility, use_melee).
# A loadout travels as one int (4 bits per slot) in join/loadout RPCs and the snapshot ("lo").

const PRIMARIES = [preload("res://resources/weapons/shotgun.tres"), preload("res://resources/weapons/rifle.tres"), preload("res://resources/weapons/smg.tres")]
const SIDEARMS = [preload("res://resources/weapons/pistol.tres"), preload("res://resources/weapons/burst_pistol.tres"), preload("res://resources/weapons/revolver.tres")]

enum Utility { GRAPPLE, FRAG_GRENADE, SMOKE_GRENADE, LAUNCH_PAD, SENTRY_TURRET, BARRICADE, BREACH_CHARGE }
const UTILITIES := [
	{"name": "Grapple", "cooldown": 7.0, "blurb": "Hook aimed geometry within 28 m and reel in; Q again lets go. Letting go grants 2 s of extra air control."},
	{"name": "Frag Grenade", "cooldown": 9.0, "blurb": "Arcing grenade: 35 on a direct hit, 15 splash within 2.5 m."},
	{"name": "Smoke Grenade", "cooldown": 16.0, "blurb": "Smoke at your feet and 2.5 s of concealment. Attacking ends it; damage briefly reveals you."},
	{"name": "Launch Pad", "cooldown": 10.0, "blurb": "Placed pad that throws anyone who steps on it 14.5 m/s upward. One at a time, 80 HP."},
	{"name": "Sentry Turret", "cooldown": 12.0, "blurb": "Placed turret covering a 120 degree cone to 14 m, 6 damage a shot. One at a time, 100 HP, repairs near you."},
	{"name": "Barricade", "cooldown": 14.0, "blurb": "Placed wall of cover with 180 HP that stands for 8 s."},
	{"name": "Breach Charge", "cooldown": 8.0, "blurb": "Close blast in front of you: 20 damage within 5 m, launches enemies, triple damage to deployables."},
]

enum Melee { KNIFE, SLEDGEHAMMER, SWORD }
# damage, reach (m), arc (minimum dot with the facing), recovery (s), push (m/s)
const MELEES := [
	{"name": "Knife", "damage": 35.0, "reach": 2.2, "arc": 0.5, "recovery": 0.5, "push": 1.0, "backstab": 2.0, "blurb": "Quick stab. Double damage from behind."},
	{"name": "Sledgehammer", "damage": 75.0, "reach": 3.0, "arc": 0.35, "recovery": 0.9, "push": 3.0, "backstab": 1.0, "blurb": "Slow, heavy swing that knocks enemies back."},
	{"name": "Sword", "damage": 50.0, "reach": 3.5, "arc": 0.0, "recovery": 0.75, "push": 2.0, "backstab": 1.0, "blurb": "Wide half-circle slash. A hit refills your current magazine."},
]
const BACKSTAB_DOT := 0.5  # the target faces away from the attacker by at least this much

const SLOT_NAMES := ["PRIMARY", "SIDEARM", "UTILITY", "MELEE"]
const QUIPS := ["Hold the line.", "Next.", "Point secured. Mostly.", "That one's on you.", "Clean.", "Back to spawn with you."]

static func slot_sizes() -> Array:
	return [PRIMARIES.size(), SIDEARMS.size(), UTILITIES.size(), MELEES.size()]

static func encode(primary: int, sidearm: int, utility: int, melee: int) -> int:
	var sizes := slot_sizes()
	return clampi(primary, 0, sizes[0] - 1) | clampi(sidearm, 0, sizes[1] - 1) << 4 | clampi(utility, 0, sizes[2] - 1) << 8 | clampi(melee, 0, sizes[3] - 1) << 12

# [primary, sidearm, utility, melee], each clamped into its table, so any int from the network is safe.
static func decode(code: int) -> Array:
	var sizes := slot_sizes()
	var ids := []
	for i in range(4):
		ids.append(clampi((code >> (4 * i)) & 15, 0, sizes[i] - 1))
	return ids

static func with_slot(code: int, slot: int, value: int) -> int:
	var ids := decode(code)
	ids[slot] = value
	return encode(ids[0], ids[1], ids[2], ids[3])

static func primary(code: int) -> WeaponSpec:
	return PRIMARIES[decode(code)[0]]

static func sidearm(code: int) -> WeaponSpec:
	return SIDEARMS[decode(code)[1]]

static func utility(code: int) -> int:
	return decode(code)[2]

static func melee(code: int) -> int:
	return decode(code)[3]

static func item_name(slot: int, index: int) -> String:
	match slot:
		0: return PRIMARIES[index].title
		1: return SIDEARMS[index].title
		2: return UTILITIES[index].name
		_: return MELEES[index].name

static func item_blurb(slot: int, index: int) -> String:
	match slot:
		0: return "%s\n%s" % [PRIMARIES[index].blurb, PRIMARIES[index].summary()]
		1: return "%s\n%s" % [SIDEARMS[index].blurb, SIDEARMS[index].summary()]
		2: return "%s Cooldown %d s." % [UTILITIES[index].blurb, int(UTILITIES[index].cooldown)]
		_: return MELEES[index].blurb

# "Rifle · Pistol · Grapple · Knife"
static func describe(code: int) -> String:
	var ids := decode(code)
	return " · ".join(PackedStringArray([item_name(0, ids[0]), item_name(1, ids[1]), item_name(2, ids[2]), item_name(3, ids[3])]))
