class_name ClassSpec
extends Resource

@export var title: String = ""  # role line; heroes with a hero_name show that first
@export var hero_name: String = ""
@export var epithet: String = ""
@export var tagline: String = ""
@export var ultimate: String = ""  # empty = no ultimate; recharges over ultimate_cooldown
@export var ultimate_cooldown: float = 45.0
@export var health: float = 200.0
@export var damage: float = 12.0
@export var interval: float = 0.4
@export var magazine: int = 24
@export var reload_time: float = 1.4
@export var reach: float = 40.0
@export var pellets: int = 1
@export var spread_deg: float = 0.0
@export var falloff_start: float = 0.0
@export var falloff_end: float = 0.0
@export var falloff_min: float = 1.0
@export var headshot_mult: float = 1.35
@export var burst: int = 1
@export var burst_gap: float = 0.07
@export var abilities: PackedStringArray = []
@export var cooldowns: PackedFloat32Array = []
@export var passive: String = ""
@export var quips: PackedStringArray = []

# The name shown in the HUD, kill feed and scoreboard.
func display_name() -> String:
	return hero_name if hero_name != "" else title

# Summary line for the menu card and scoreboard footer: "Hero, Epithet" or just the class title.
func headline() -> String:
	if hero_name == "":
		return title
	return "%s, %s" % [hero_name, epithet] if epithet != "" else hero_name

func body_ttk(target_health: float = 200.0) -> float:
	var rounds := int(ceil(target_health / (damage * pellets)))
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
