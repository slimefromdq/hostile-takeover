class_name WeaponSpec
extends Resource

# A gun: a primary or a sidearm in a loadout (scripts/loadout.gd), data in resources/weapons/*.tres.

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
@export var ricochet: bool = false  # a shot that hits geometry bounces once for the remaining reach

enum FireMode { HITSCAN, PROJECTILE }
enum AltMode { ADS, DETONATE, DOUBLE_BLAST }
@export var fire_mode: FireMode = FireMode.HITSCAN
@export var alt_mode: AltMode = AltMode.ADS
@export var projectile_speed: float = 0.0
@export var projectile_radius: float = 0.06
@export var projectile_gravity: float = 0.0
@export var projectile_lift: float = 0.0
@export var projectile_fuse: float = 0.0
@export var projectile_bounces: int = 0
@export var bounce_retention: float = 1.0
@export var splash_radius: float = 0.0
@export var splash_damage: float = 0.0
@export var splash_min: float = 0.0
@export var alt_pellets: int = 0
@export var alt_ammo: int = 0
@export var alt_recoil: float = 0.0

func uses_ads() -> bool:
	return alt_mode == AltMode.ADS

# Damage multiplier for a pellet that travelled `dist` metres.
func falloff_at(dist: float) -> float:
	if falloff_end <= falloff_start or dist <= falloff_start:
		return 1.0
	var t := clampf((dist - falloff_start) / (falloff_end - falloff_start), 0.0, 1.0)
	return lerpf(1.0, falloff_min, t)

func damage_at(dist: float) -> float:
	return damage * falloff_at(dist)

# Seconds to kill a target with body shots at `dist`, with every pellet landing (firing cadence plus any reload).
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
