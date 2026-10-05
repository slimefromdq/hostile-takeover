class_name ClassIdentity
extends RefCounted

# Kept for existing callers; the rig itself lives in CharacterRig.
static func build(parent: Node3D, archetype: int, team_color: Color, ghost: bool = false, outlines: Array = []) -> Node3D:
	return CharacterRig.build(parent, archetype, team_color, outlines, ghost)
