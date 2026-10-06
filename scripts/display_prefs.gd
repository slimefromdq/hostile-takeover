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

static func set_fullscreen(value: bool) -> void:
	fullscreen = value
	apply()
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("display", "fullscreen", value)
	cfg.save(SETTINGS_PATH)

static func toggle() -> void:
	set_fullscreen(not fullscreen)

static func apply() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED)
