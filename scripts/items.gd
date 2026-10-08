class_name Items
extends RefCounted

# Map-placed timed pickups (blockout `pickup` features with kind "bubble" | "armor1" | "armor2"). Pure data plus the
# two rules every item shares; game.gd runs the timers. The older health pack ("healpack") keeps its own constants.
# Armor values stack with kill-drop armor up to Fighter.ARMOR_MAX.

const KINDS := {
	"bubble": {"heal": 15.0, "armor": 0.0, "respawn": 10.0, "color": Color("3dff7a"), "sound": Sfx.Kind.ITEM_BUBBLE},
	"armor1": {"heal": 0.0, "armor": 50.0, "respawn": 30.0, "color": Color("5ab8ff"), "sound": Sfx.Kind.ITEM_ARMOR1},
	"armor2": {"heal": 0.0, "armor": 100.0, "respawn": 45.0, "color": Color("ffc83d"), "sound": Sfx.Kind.ITEM_ARMOR2},
}
const RADIUS := 1.5

# Blockout `kind` -> entity kind. Anything unknown (including the default "health") stays a health pack.
static func entity_kind(blockout_kind: String) -> String:
	return blockout_kind if KINDS.has(blockout_kind) else "healpack"

# An item is only taken when it would help: it never wastes itself on a full-health, full-armor fighter.
static func can_use(kind: String, hp: float, max_hp: float, armor: float) -> bool:
	var item: Dictionary = KINDS[kind]
	return (item.heal > 0.0 and hp < max_hp) or (item.armor > 0.0 and armor < Fighter.ARMOR_MAX)

static func apply(kind: String, p: Fighter) -> void:
	var item: Dictionary = KINDS[kind]
	p.hp = minf(p.spec.health, p.hp + item.heal)
	p.armor = minf(Fighter.ARMOR_MAX, p.armor + item.armor)
