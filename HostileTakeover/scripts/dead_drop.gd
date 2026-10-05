extends Node3D

var game: Node3D
var source_id: int
var source_team: int
var source_rid: RID
var velocity: Vector3
var age := 0.0

func configure(g: Node3D, p: Fighter) -> void:
	game = g
	source_id = p.fighter_id
	source_team = p.team
	source_rid = p.get_rid()
	velocity = p.direction() * 22 + Vector3.UP * 3
	var visual := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.12
	sphere.height = 0.24
	visual.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("ffe2a3")
	mat.emission_enabled = true
	mat.emission = mat.albedo_color
	visual.material_override = mat
	add_child(visual)

func _physics_process(dt: float) -> void:
	if not game.authoritative or game.match_state.winner != -2:
		queue_free()
		return
	age += dt
	velocity += Vector3.DOWN * 15 * dt
	var next := global_position + velocity * dt
	var hit: Dictionary = game.ray(global_position, next, [source_rid])
	game.show_trace(global_position, next, Color("ffde8d"))
	global_position = next if hit.is_empty() else hit.position
	if not hit.is_empty() or age > 3:
		for target in game.fighters.values():
			if target.team == source_team or target.hp <= 0 or target.global_position.distance_to(global_position) >= 2.5:
				continue
			var sight: Dictionary = game.ray(global_position + Vector3.UP * 0.05, target.global_position + Vector3.UP, [source_rid])
			if sight.is_empty() or sight.collider == target:
				var direct: bool = not hit.is_empty() and hit.collider == target
				game.damage_fighter(target, 35 if direct else 15, source_id)
		game.show_trace(global_position, global_position + Vector3.UP * 2.5, Color.WHITE)
		game.play_cue_at(global_position, 150)
		queue_free()
