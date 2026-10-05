class_name ClassSpec
extends Resource

@export var title: String = ""
@export var health: float = 200.0
@export var damage: float = 12.0
@export var interval: float = 0.4
@export var magazine: int = 24
@export var reload_time: float = 1.4
@export var reach: float = 40.0
@export var burst: int = 1
@export var burst_gap: float = 0.07
@export var abilities: PackedStringArray = []
@export var cooldowns: PackedFloat32Array = []
@export var passive: String = ""
@export var quips: PackedStringArray = []

func body_ttk(target_health: float = 200.0) -> float:
	var rounds := int(ceil(target_health / damage))
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
