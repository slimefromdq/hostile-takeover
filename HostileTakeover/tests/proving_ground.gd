class_name ProvingGround
extends RefCounted

# Open-floor fixtures for physics tests, far outside the playable map (z=300; x stays inside the depot-protection limit so damage tests work) so real geometry never
# interferes: a floor, a 1.2 m crate (mantle), an end wall (wall kick) and a solid block (swap blocking).
const ORIGIN := Vector3(0, 0, 300)

static func build(root: Node3D) -> void:
	var b := MapBuilder.new()
	var o := ORIGIN
	var grey := Color("6b747d")
	b.block(o.x - 100, o.z - 40, o.x + 100, o.z + 40, -5, 0, "walk", grey, "pg_floor")
	b.block(o.x + 89.5, o.z - 30, o.x + 91, o.z + 30, 0, 9, "wall", grey, "pg_wall")
	b.block(o.x - 4.5, o.z + 4, o.x - 1.5, o.z + 6, 0, 1.2, "cover", grey, "pg_crate")
	b.block(o.x + 5, o.z - 17, o.x + 13, o.z - 9, 0, 5, "tower", grey, "pg_block")
	b.finalize(root)
