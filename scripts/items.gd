class_name Items
extends RefCounted

# Map-placed timed pickups (blockout `pickup` features with kind "bubble" | "armor1" | "armor2"). Pure data plus the
# two rules every item shares; game.gd runs the timers. The older health pack ("healpack") keeps its own constants.
# Armor values stack with kill-drop armor up to Fighter.ARMOR_MAX.

const KINDS := {
	"bubble": {"heal": 15.0, "armor": 0.0, "respawn": 10.0, "color": Color("3dff7a"), "sound": Sfx.Kind.ITEM_BUBBLE},
	"armor1": {"heal": 0.0, "armor": 50.0, "respawn": 30.0, "color": Color("5ab8ff"), "sound": Sfx.Kind.ITEM_ARMOR1},
	"armor2": {"heal": 0.0, "armor": 100.0, "respawn": 45.0, "color": Color("ffc83d"), "sound": Sfx.Kind.ITEM_ARMOR2},
	"power": {"heal": 0.0, "armor": 0.0, "respawn": 90.0, "color": Color("c36bff"), "sound": Sfx.Kind.ITEM_POWER},
}

# The power-up: the entity's `hp` field holds which one is up (1 or 2), re-rolled each time it respawns.
const POWER_INVULNERABLE := 1
const POWER_QUAD := 2
const POWER_DURATION := 8.0
const POWER_FIRST_SPAWN := 30.0  # the first one appears this long after the match starts
const QUAD_MULTIPLIER := 3.0
const POWER_WARNING := 15.0  # the minimap flags the power-up this many seconds before it spawns
const STREAK_NAMES := {2: "DOUBLE KILL", 3: "TRIPLE KILL", 4: "QUAD KILL"}  # 5 and up: RAMPAGE

static func streak_name(kills: int) -> String:
	return "" if kills < 2 else STREAK_NAMES.get(kills, "RAMPAGE")

const POWER_NAMES := {1: "INVINCIBLE", 2: "TRIPLE DAMAGE"}
const POWER_COLORS := {1: Color("5ae6ff"), 2: Color("ff4a3a")}
const RADIUS := 1.5

# Blockout `kind` -> entity kind. Anything unknown (including the default "health") stays a health pack.
static func entity_kind(blockout_kind: String) -> String:
	return blockout_kind if KINDS.has(blockout_kind) else "healpack"

# An item is only taken when it would help: it never wastes itself on a full-health, full-armor fighter.
static func can_use(kind: String, hp: float, max_hp: float, armor: float) -> bool:
	if kind == "power":
		return true  # the holder check (one power-up at a time) lives with the fighter
	var item: Dictionary = KINDS[kind]
	return (item.heal > 0.0 and hp < max_hp) or (item.armor > 0.0 and armor < Fighter.ARMOR_MAX)

# True while a taken power-up is within POWER_WARNING seconds of coming back.
static func power_spawning_soon(used: bool, timer: float) -> bool:
	return used and timer > 0.0 and timer <= POWER_WARNING

# Which map-wide cue a taken power-up's countdown earns as its timer drops from `before` to `after`:
# a rising warning when it enters the last POWER_WARNING seconds, then a tick at 3, 2 and 1 seconds left.
static func power_cue(before: float, after: float) -> int:
	if before > POWER_WARNING and after <= POWER_WARNING:
		return Sfx.Kind.POWER_WARN
	for second in [3.0, 2.0, 1.0]:
		if before > second and after <= second:
			return Sfx.Kind.POWER_TICK
	return -1

static func apply(kind: String, p: Fighter) -> void:
	var item: Dictionary = KINDS[kind]
	p.hp = minf(p.spec.health, p.hp + item.heal)
	p.armor = minf(Fighter.ARMOR_MAX, p.armor + item.armor)
