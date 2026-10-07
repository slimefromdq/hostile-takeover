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
	var pod := CapsuleMesh.new()
	pod.radius = 0.14
	pod.height = 0.5
	pod.radial_segments = 12
	pod.rings = 3
	visual.mesh = pod
	visual.rotation.x = PI / 2
	visual.material_override = Visuals.glow(Color("ffe2a3"), 2.5)
	add_child(visual)
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.16
	band_mesh.bottom_radius = 0.16
	band_mesh.height = 0.06
	band_mesh.radial_segments = 12
	band.mesh = band_mesh
	band.rotation.x = PI / 2
	band.material_override = Visuals.glow(Visuals.team_color(source_team), 3.0)
	add_child(band)

func _physics_process(dt: float) -> void:
	if not game.authoritative or game.match_state.winner != -2:
		queue_free()
		return
	age += dt
	velocity += Vector3.DOWN * 15 * dt
	var next := global_position + velocity * dt
	var hit: Dictionary = game.ray(global_position, next, [source_rid])
	game.show_trace(global_position, next, Color("ffde8d"), Vfx.Style.CAPSULE)
	global_position = next if hit.is_empty() else hit.position
	if velocity.length() > 0.1 and absf(velocity.normalized().y) < 0.99:
		look_at(global_position + velocity, Vector3.UP)
	if not hit.is_empty() or age > 3:
		for target in game.fighters.values():
			if target.team == source_team or target.hp <= 0 or target.global_position.distance_to(global_position) >= 2.5:
				continue
			var sight: Dictionary = game.ray(global_position + Vector3.UP * 0.05, target.global_position + Vector3.UP, [source_rid])
			if sight.is_empty() or sight.collider == target:
				var direct: bool = not hit.is_empty() and hit.collider == target
				game.damage_fighter(target, 35 if direct else 15, source_id, global_position)
		game.show_ring(global_position, 2.5, Color("ffde8d"))
		game.show_trace(global_position, global_position + Vector3.UP * 2.5, Color.WHITE, Vfx.Style.LINE, true)
		game.play_sfx(global_position, Sfx.Kind.EXPLODE)
		queue_free()
