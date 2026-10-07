class_name Tension
extends RefCounted

# Shared hero meter (Guilty Gear tension / Overwatch ultimate): charges over time and faster in combat, and is
# spent by ultimates at half the bar. Pure rules with no scene dependencies; game.gd applies the events.

const MAX := 100.0
const ULTIMATE_COST := 50.0
const PASSIVE_PER_SECOND := 0.8
const PER_DAMAGE_DEALT := 0.20
const PER_DAMAGE_TAKEN := 0.10
const PER_KILL := 10.0
const PER_ASSIST := 5.0
const PER_POINT_SECOND := 1.5  # standing on a contested capture point

static func add(meter: float, amount: float) -> float:
	return clampf(meter + amount, 0.0, MAX)

static func passive(meter: float, dt: float) -> float:
	return add(meter, PASSIVE_PER_SECOND * dt)

static func dealt(meter: float, damage: float) -> float:
	return add(meter, damage * PER_DAMAGE_DEALT)

static func taken(meter: float, damage: float) -> float:
	return add(meter, damage * PER_DAMAGE_TAKEN)

static func kill(meter: float) -> float:
	return add(meter, PER_KILL)

static func assist(meter: float) -> float:
	return add(meter, PER_ASSIST)

static func on_point(meter: float, dt: float) -> float:
	return add(meter, PER_POINT_SECOND * dt)

static func can_spend(meter: float, cost: float = ULTIMATE_COST) -> bool:
	return meter >= cost

# Returns the meter after paying `cost`, or the unchanged meter when it cannot be afforded.
static func spend(meter: float, cost: float = ULTIMATE_COST) -> float:
	return meter - cost if can_spend(meter, cost) else meter
