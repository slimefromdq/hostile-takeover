extends Node3D

# Reave's ultimate: a blade of fire that flies down the lane. Server-side only (like dead_drop.gd); clients see
# it through the replicated trace effects. It pierces fighters, hits each once, stops on world geometry, and is
# swallowed by an enemy Reave's guard.

const SPEED := 28.0
const RANGE := 30.0
const RADIUS := 1.6  # about 3 m wide
const DAMAGE := 70.0
const BURN_TIME := 3.0
const DEPLOYABLE_DAMAGE := 70.0
const FIRE := Color("ff7a3a")

var game: Node3D
var source_id: int
var source_team: int
var source_rid: RID
var direction: Vector3
var travelled := 0.0
var hit_ids: Array[int] = []

func configure(g: Node3D, p: Fighter) -> void:
	game = g
	source_id = p.fighter_id
	source_team = p.team
	source_rid = p.get_rid()
	direction = p.direction()

func _physics_process(dt: float) -> void:
	if not game.authoritative or game.match_state.winner != -2:
		queue_free()
		return
	var step := SPEED * dt
	var from := global_position
	var to := from + direction * step
	var world: Dictionary = game.ray(from, to, [source_rid], 1 | 4)
	var end: Vector3 = to if world.is_empty() else world.position
	game.show_trace(from, end, FIRE, Vfx.Style.SWOOSH, not world.is_empty())
	for target in game.fighters.values():
		if target.team == source_team or target.hp <= 0 or hit_ids.has(target.fighter_id):
			continue
		var centre: Vector3 = target.global_position + Vector3.UP * 0.95
		if _distance_to_segment(centre, from, end) > RADIUS:
			continue
		hit_ids.append(target.fighter_id)
		var landed: bool = game.damage_fighter(target, DAMAGE, source_id, global_position)
		if landed:
			target.burn = BURN_TIME
			target.burn_source = source_id
			game.hit_feedback(source_id, 2 if target.hp <= 0 else 0)
		else:
			# An enemy Reave's guard swallows the blade whole.
			game.show_ring(target.global_position + Vector3.UP, 1.5, FIRE)
			queue_free()
			return
	if not world.is_empty():
		var object = world.collider
		if object is Deployable and object.team != source_team:
			object.hp -= DEPLOYABLE_DAMAGE
			object.last_damage = object.age
		game.show_ring(end, 2.0, FIRE)
		game.play_sfx(end, Sfx.Kind.EXPLODE)
		queue_free()
		return
	global_position = end
	travelled += step
	if travelled >= RANGE:
		game.show_ring(end, 1.5, FIRE)
		queue_free()

static func _distance_to_segment(point: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var length_sq := ab.length_squared()
	if length_sq < 0.000001:
		return point.distance_to(a)
	var t := clampf((point - a).dot(ab) / length_sq, 0.0, 1.0)
	return point.distance_to(a + ab * t)
