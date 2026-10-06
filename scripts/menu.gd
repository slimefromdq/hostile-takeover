class_name GameMenu
extends PanelContainer

# Start/pause menu: class cards with rotating rig portraits, mode buttons and a controls panel.

var game: Node3D
var status: Label
var address: LineEdit
var cards: Array[Button] = []
var spinners: Array[Node3D] = []
var controls_panel: Label
var display_button: Button
var map_button: Button
var weapon_buttons: Array[Button] = []
var weapon_blurb: Label

func setup(owner_game: Node3D) -> void:
	game = owner_game
	size = Vector2(980, 724)
	# The cut-corner panel is drawn in _draw(); the stylebox only supplies padding.
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 18
	style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	add_child(column)
	column.add_child(_label("HOSTILE TAKEOVER", 40))
	var rule := ColorRect.new()
	rule.color = UiStyle.ACCENT
	rule.custom_minimum_size = Vector2(120, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	column.add_child(_label("CIVIC DIVIDEND  /  ACQUISITION  ·  Four classes. Five points. Questionable employment.", 15, UiStyle.TEXT_MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	column.add_child(row)
	var group := ButtonGroup.new()
	for i in range(Fighter.SPECS.size()):
		var card := _make_card(i, group)
		row.add_child(card)
		cards.append(card)
	cards[game.selected_class].button_pressed = true
	var weapon_row := HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 10)
	column.add_child(weapon_row)
	weapon_row.add_child(_label("WEAPON", 15, UiStyle.ACCENT))
	var weapon_group := ButtonGroup.new()
	for i in range(Fighter.WEAPONS.size()):
		var button := Button.new()
		button.toggle_mode = true
		button.button_group = weapon_group
		button.text = "Signature (class gun)" if i == 0 else Fighter.WEAPONS[i].title
		button.tooltip_text = "Each class's own gun, with its special behaviour." if i == 0 else "%s\n%s" % [Fighter.WEAPONS[i].blurb, Fighter.WEAPONS[i].summary()]
		button.custom_minimum_size = Vector2(150, 30)
		UiStyle.style_button(button, false)
		button.pressed.connect(func():
			game.selected_weapon = i
			weapon_blurb.text = _weapon_blurb(i))
		weapon_row.add_child(button)
		weapon_buttons.append(button)
	weapon_buttons[game.selected_weapon].button_pressed = true
	weapon_blurb = _label(_weapon_blurb(game.selected_weapon), 13, Color(1, 1, 1, 0.75))
	column.add_child(weapon_blurb)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for pair in [["Play offline · 10v10 bots", "offline"], ["Explore map · free roam", "explore"], ["Host LAN · UDP 27847", "host"], ["Join server", "join"], ["Apply class / Resume", "resume"], ["Restart round · host / offline", "restart"]]:
		var button := Button.new()
		button.text = pair[0]
		button.custom_minimum_size = Vector2(290, 38)
		UiStyle.style_button(button, pair[1] == "offline")
		grid.add_child(button)
		button.pressed.connect(game.start_game.bind(pair[1]))
	address = LineEdit.new()
	address.text = "127.0.0.1"
	address.placeholder_text = "Server IP"
	address.custom_minimum_size = Vector2(290, 38)
	address.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.SLOT, 0.95), Color(UiStyle.ACCENT, 0.45), 1))
	address.add_theme_stylebox_override("focus", UiStyle.box(Color(UiStyle.SLOT, 0.95), UiStyle.ACCENT, 2))
	grid.add_child(address)
	status = _label("Godot 4.7 prototype", 15, Color(1, 1, 1, 0.7))
	grid.add_child(status)
	var options := HBoxContainer.new()
	options.add_theme_constant_override("separation", 16)
	column.add_child(options)
	var toggle := Button.new()
	toggle.text = "Controls ▾"
	toggle.flat = true
	toggle.alignment = HORIZONTAL_ALIGNMENT_LEFT
	toggle.add_theme_color_override("font_color", UiStyle.ACCENT)
	toggle.add_theme_color_override("font_hover_color", UiStyle.TEXT)
	options.add_child(toggle)
	map_button = Button.new()
	map_button.flat = true
	map_button.add_theme_color_override("font_color", UiStyle.ACCENT)
	map_button.add_theme_color_override("font_hover_color", UiStyle.TEXT)
	map_button.pressed.connect(_cycle_map)
	options.add_child(map_button)
	_refresh_map_button()
	display_button = Button.new()
	display_button.flat = true
	display_button.add_theme_color_override("font_color", UiStyle.ACCENT)
	display_button.add_theme_color_override("font_hover_color", UiStyle.TEXT)
	display_button.pressed.connect(func():
		DisplayPrefs.toggle()
		refresh_display_button())
	options.add_child(display_button)
	refresh_display_button()
	var sens_row := HBoxContainer.new()
	sens_row.add_theme_constant_override("separation", 10)
	var sens_label := Label.new()
	sens_label.add_theme_color_override("font_color", UiStyle.ACCENT)
	sens_row.add_child(sens_label)
	var sens_slider := HSlider.new()
	sens_slider.min_value = DisplayPrefs.SENS_MIN
	sens_slider.max_value = DisplayPrefs.SENS_MAX
	sens_slider.step = 0.05
	sens_slider.value = DisplayPrefs.sensitivity
	sens_slider.custom_minimum_size = Vector2(220, 0)
	sens_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sens_slider.focus_mode = Control.FOCUS_CLICK
	sens_label.text = "Aim sensitivity: %.2f" % sens_slider.value
	sens_slider.value_changed.connect(func(v: float):
		DisplayPrefs.set_sensitivity(v)
		sens_label.text = "Aim sensitivity: %.2f" % v)
	sens_row.add_child(sens_slider)
	column.add_child(sens_row)
	controls_panel = _label("WASD move / aim with mouse · LMB primary · RMB alternate · SPACE jump, again in the air to double jump or at a wall to kick, walk into a ledge to mantle (S or SHIFT drops from a hang)\n1 air dash (independent of the double jump; sprint is automatic) · strafe to steer in the air · SHIFT slide, SPACE out of it to slide-jump · run along a wall to wall run · Q / E / F abilities · R reload · V shoulder · TAB scoreboard\nF1 hide hints · F2 colour-blind palette · F11 fullscreen · ESC menu · Capture the centre, then advance; the final point wins.", 14, Color(1, 1, 1, 0.8))
	controls_panel.visible = false
	column.add_child(controls_panel)
	toggle.pressed.connect(func():
		controls_panel.visible = not controls_panel.visible
		toggle.text = "Controls ▴" if controls_panel.visible else "Controls ▾")

func _ready() -> void:
	get_viewport().size_changed.connect(_center)
	resized.connect(_center)
	_center()

func _current_map_index() -> int:
	var maps := BlockoutImporter.catalog()
	var path := BlockoutImporter.active_path()
	for i in range(maps.size()):
		if maps[i].path == path:
			return i
	return 0

func _refresh_map_button() -> void:
	var maps := BlockoutImporter.catalog()
	var override := FileAccess.file_exists(BlockoutImporter.ACTIVE_PATH)
	var title: String = "maps/blockout.json override" if override else maps[_current_map_index()].title
	map_button.text = "Map: %s ▸ click to switch (everyone in a match must pick the same)" % title
	map_button.disabled = override

# Selecting a map saves the choice and reloads the scene, so the whole world rebuilds cleanly.
func _cycle_map() -> void:
	var maps := BlockoutImporter.catalog()
	var next: int = (_current_map_index() + 1) % maps.size()
	BlockoutImporter.select(maps[next].path)
	game.get_tree().reload_current_scene()

# Keep the panel centred whatever the window or fullscreen aspect ratio is.
func _center() -> void:
	position = ((get_viewport_rect().size - size) / 2.0).round()

func refresh_display_button() -> void:
	if DisplayPrefs.embedded():
		display_button.text = "Display: Windowed · embedded in editor"
		display_button.tooltip_text = "Fullscreen needs a standalone window: turn off Embed Game on Next Play in the editor, or run the exported game."
		return
	display_button.text = "Display: %s · F11" % ("Fullscreen" if DisplayPrefs.fullscreen else "Windowed")

func _label(value: String, font_size: int, color: Color = Color("eef0e5")) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _weapon_blurb(index: int) -> String:
	if index == 0:
		return "Each class keeps its own gun and its quirks."
	var w: WeaponSpec = Fighter.WEAPONS[index]
	return "%s  (%s)" % [w.blurb, w.summary()]

func _make_card(index: int, group: ButtonGroup) -> Button:
	var spec: ClassSpec = Fighter.SPECS[index]
	var card := Button.new()
	card.toggle_mode = true
	card.button_group = group
	card.custom_minimum_size = Vector2(212, 352)
	card.pressed.connect(func(): game.selected_class = index)
	var chosen := UiStyle.box(Color(UiStyle.PANEL_RAISED, 0.95), UiStyle.ACCENT, 3, 0.0)
	card.add_theme_stylebox_override("normal", UiStyle.box(Color(UiStyle.SLOT, 0.9), Color(UiStyle.ACCENT, 0.3), 1, 0.0))
	card.add_theme_stylebox_override("hover", UiStyle.box(Color(UiStyle.PANEL_RAISED, 0.7), Color(UiStyle.ACCENT, 0.7), 1, 0.0))
	card.add_theme_stylebox_override("pressed", chosen)
	card.add_theme_stylebox_override("hover_pressed", chosen)
	card.add_theme_stylebox_override("focus", UiStyle.box(Color(0, 0, 0, 0), UiStyle.HIGHLIGHT, 2, 0.0))
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(196, 150)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(container)
	container.add_child(_make_portrait(index))
	box.add_child(_label(spec.title.to_upper(), 18, UiStyle.ACCENT))
	box.add_child(_label("HP %d  ·  %.1fs to kill" % [int(spec.health), spec.body_ttk()], 13, Color(1, 1, 1, 0.8)))
	var keys := ["Q", "E", "F"]
	for i in range(3):
		box.add_child(_label("%s  %s" % [keys[i], spec.abilities[i]], 13))
	var passive := _label(spec.passive, 11, Color(1, 1, 1, 0.65))
	passive.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	passive.custom_minimum_size.x = 190
	box.add_child(passive)
	return card

func _make_portrait(index: int) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(196, 190)
	viewport.own_world_3d = true
	viewport.transparent_bg = true
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("9fb4d6")
	environment.ambient_light_energy = 0.8
	var world_env := WorldEnvironment.new()
	world_env.environment = environment
	world.add_child(world_env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -30, 0)
	light.light_energy = 1.2
	world.add_child(light)
	var spinner := Node3D.new()
	world.add_child(spinner)
	var outlines: Array = []
	CharacterRig.build(spinner, index, Visuals.team_color(0), outlines)
	for outline in outlines:
		outline.set_shader_parameter("outline_color", Visuals.ALLY_OUTLINE)
	spinners.append(spinner)
	var camera := Camera3D.new()
	camera.fov = 38
	world.add_child(camera)
	camera.position = Vector3(0, 1.05, 3.7)
	camera.look_at_from_position(camera.position, Vector3(0, 0.95, 0))
	return viewport

func _draw() -> void:
	UiStyle.draw_panel(self, Rect2(Vector2.ZERO, size), Color(UiStyle.PANEL, 0.97), Color(UiStyle.ACCENT, 0.85), 18.0, 2.0)

func _process(dt: float) -> void:
	if not visible:
		return
	for spinner in spinners:
		spinner.rotation.y += dt * 0.9
