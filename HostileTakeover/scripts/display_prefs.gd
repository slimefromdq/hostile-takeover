class_name DisplayPrefs
extends RefCounted

# Window/fullscreen preference, persisted next to the other display settings.
# Layout scaling itself is handled by the project's canvas_items + expand stretch mode.

const SETTINGS_PATH := "user://settings.cfg"
static var fullscreen := false

static func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		fullscreen = cfg.get_value("display", "fullscreen", false)
	apply()

# The editor's "Embed Game on Next Play" runs the game inside an editor panel, which cannot go fullscreen.
static func embedded() -> bool:
	return Engine.has_method("is_embedded_in_editor") and Engine.is_embedded_in_editor()

static func set_fullscreen(value: bool) -> void:
	if embedded():
		return
	fullscreen = value
	apply()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "fullscreen", value)
	cfg.save(SETTINGS_PATH)

static func toggle() -> void:
	set_fullscreen(not fullscreen)

static func apply() -> void:
	if DisplayServer.get_name() == "headless" or embedded():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
