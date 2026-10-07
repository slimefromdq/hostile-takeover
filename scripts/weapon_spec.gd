class_name WeaponSpec
extends Resource

# A gun, independent of fighter class. Weapon 0 ("Signature") is synthesised from a class's own
# gun fields by from_class(); weapons 1+ come from resources/weapons/*.tres.

@export var title: String = ""
@export var blurb: String = ""
@export var damage: float = 12.0  # per pellet, before falloff and headshots
@export var pellets: int = 1
@export var spread_deg: float = 0.0  # cone half-angle; with several pellets the first flies true
@export var falloff_start: float = 0.0  # full damage up to here...
@export var falloff_end: float = 0.0  # ...scaling to falloff_min at here (0 disables falloff)
@export var falloff_min: float = 1.0
@export var interval: float = 0.4
@export var magazine: int = 24
@export var reload_time: float = 1.4
@export var reach: float = 40.0
@export var headshot_mult: float = 1.35
@export var burst: int = 1
@export var burst_gap: float = 0.07
@export var move_speed_mult: float = 1.0

static func from_class(spec: ClassSpec, class_id: int) -> WeaponSpec:
	var w := WeaponSpec.new()
	w.title = "Signature"
	w.damage = spec.damage
	w.interval = spec.interval
	w.magazine = spec.magazine
	w.reload_time = spec.reload_time
	w.reach = spec.reach
	w.pellets = spec.pellets
	w.spread_deg = spec.spread_deg
	w.falloff_start = spec.falloff_start
	w.falloff_end = spec.falloff_end
	w.falloff_min = spec.falloff_min
	w.burst = spec.burst
	w.burst_gap = spec.burst_gap
	w.headshot_mult = 1.0 if class_id == 1 else spec.headshot_mult  # the electric hose cannot headshot
	return w

# Damage multiplier for a pellet that travelled `dist` metres.
func falloff_at(dist: float) -> float:
	if falloff_end <= falloff_start or dist <= falloff_start:
		return 1.0
	var t := clampf((dist - falloff_start) / (falloff_end - falloff_start), 0.0, 1.0)
	return lerpf(1.0, falloff_min, t)

func damage_at(dist: float) -> float:
	return damage * falloff_at(dist)

# Seconds to kill a target with body shots at `dist`, with every pellet landing (same model as ClassSpec.body_ttk).
func body_ttk(target_health: float = 200.0, dist: float = 0.0) -> float:
	var per_shot := damage_at(dist) * pellets
	var rounds := int(ceil(target_health / per_shot))
	var elapsed := 0.0
	var ammo := magazine
	var in_burst := 0
	for i in range(rounds - 1):
		ammo -= 1
		in_burst += 1
		if ammo == 0:
			elapsed += reload_time
			ammo = magazine
			in_burst = 0
		elif burst > 1 and in_burst < burst:
			elapsed += burst_gap
		else:
			elapsed += interval - burst_gap * (burst - 1)
			in_burst = 0
	return elapsed

func summary() -> String:
	var per := "%d x %s" % [pellets, str(damage)] if pellets > 1 else str(damage)
	return "%s dmg · %.0f rpm · %d rounds · %d m" % [per, 60.0 / interval, magazine, int(reach)]
