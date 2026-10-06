class_name AssetLibrary
extends RefCounted

# Single lookup point for externally authored art (e.g. Blender MCP exports).
# Every request has a procedural fallback, so the game runs with an empty assets/ folder.
# Layout and naming rules are documented in assets/README.md.

const ROOT := "res://assets/"
const MODEL_EXTENSIONS := ["glb", "gltf", "tscn"]
const TEXTURE_EXTENSIONS := ["png", "webp", "jpg"]

static var _cache: Dictionary = {}

static func find(category: String, asset_name: String, extensions: Array) -> String:
	for ext in extensions:
		var path := "%s%s/%s.%s" % [ROOT, category, asset_name, ext]
		if ResourceLoader.exists(path):
			return path
	return ""

static func has_model(category: String, asset_name: String) -> bool:
	return find(category, asset_name, MODEL_EXTENSIONS) != ""

# Returns an instanced Node3D for models/<category>/<name>, or null when none is authored.
static func model(category: String, asset_name: String) -> Node3D:
	var path := find("models/" + category, asset_name, MODEL_EXTENSIONS)
	if path == "":
		return null
	var scene = load(path)
	if scene is PackedScene:
		return scene.instantiate() as Node3D
	return null

static func texture(asset_name: String) -> Texture2D:
	if _cache.has(asset_name):
		return _cache[asset_name]
	var path := find("textures", asset_name, TEXTURE_EXTENSIONS)
	var tex: Texture2D = load(path) if path != "" else null
	_cache[asset_name] = tex
	return tex

static func clear_cache() -> void:
	_cache.clear()
