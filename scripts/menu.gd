class_name GameMenu
extends PanelContainer

# Start/pause menu: a rotating portrait beside two tabs, LOADOUT (four item rows) and LOOK (the character creator:
# build, skin, eyes, hair, headgear, top, bottoms, shoes and their colours), then mode buttons and a controls panel.

var game: Node3D
var status: Label
var address: LineEdit
var item_buttons: Array = [[], [], [], []]  # per loadout slot (Loadout.SLOT_NAMES), one toggle per item
var item_blurb: Label
var loadout_summary: Label
var loadout_panel: VBoxContainer
var loadout_scroll: ScrollContainer
var look_panel: VBoxContainer
var tab_buttons: Array = []
var look_controls := {}  # Appearance field key -> Label (style cycler) or Array of swatch Buttons
var look_summary: Label
# LOOK tab layout: rows of groups; a group is one caption followed by the controls of its fields (a style and its colour).
const LOOK_ROWS := [[["body"], ["headgear"]], [["skin"], ["eyes"]], [["hair", "hair_color"]], [["top", "top_color"]], [["bottom", "bottom_color"]], [["shoes", "shoe_color"]]]
var spinner: Node3D
var controls_panel: Label
var display_button: Button
var map_button: Button

func setup(owner_game: Node3D) -> void:
	game = owner_game
	size = Vector2(980, 724)
	# The cut-corner panel is drawn in _draw(); the stylebox only supplies padding.
	var style := StyleBoxEmpty.new()
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 12
	style.content_margin_bottom = 7
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	column.add_child(_label("HOSTILE TAKEOVER", 40))
	var rule := ColorRect.new()
	rule.color = UiStyle.ACCENT
	rule.custom_minimum_size = Vector2(120, 3)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	column.add_child(_label("CIVIC DIVIDEND  /  ACQUISITION  ·  One body, your loadout. Five points.", 15, UiStyle.TEXT_MUTED))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	column.add_child(row)
	var container := SubViewportContainer.new()
	container.stretch = true
	container.custom_minimum_size = Vector2(200, 250)
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(container)
	container.add_child(_make_portrait())
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	right.add_child(_make_tabs())
	var picker := VBoxContainer.new()
	picker.add_theme_constant_override("separation", 6)
	loadout_scroll = ScrollContainer.new()
	loadout_scroll.custom_minimum_size = Vector2(640, 200)
	loadout_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(loadout_scroll)
	loadout_scroll.add_child(picker)
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	loadout_panel = picker
	look_panel = _make_look_panel()
	look_panel.visible = false
	right.add_child(look_panel)
	var ids := Loadout.decode(game.selected_loadout)
	var sizes := Loadout.slot_sizes()
	for slot in range(4):
		picker.add_child(_label(Loadout.SLOT_NAMES[slot] + ["", "  ·  2 / wheel to swap", "  ·  Q", "  ·  F"][slot], 13, UiStyle.ACCENT))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 6)
		flow.add_theme_constant_override("v_separation", 6)
		picker.add_child(flow)
		var group := ButtonGroup.new()
		for i in range(sizes[slot]):
			var button := Button.new()
			button.toggle_mode = true
			button.button_group = group
			button.text = Loadout.item_name(slot, i)
			button.tooltip_text = Loadout.item_blurb(slot, i)
			button.custom_minimum_size = Vector2(112, 28)
			UiStyle.style_button(button, false)
			button.pressed.connect(_pick.bind(slot, i))
			button.mouse_entered.connect(func(): item_blurb.text = Loadout.item_blurb(slot, i))
			flow.add_child(button)
			item_buttons[slot].append(button)
		item_buttons[slot][ids[slot]].button_pressed = true
	item_blurb = _label(Loadout.item_blurb(0, ids[0]), 12, Color(1, 1, 1, 0.75))
	item_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item_blurb.custom_minimum_size = Vector2(640, 34)
	item_blurb.size = Vector2(640, 34)
	right.add_child(item_blurb)
	loadout_summary = _label("", 13, Color(1, 1, 1, 0.85))
	loadout_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loadout_summary.custom_minimum_size = Vector2(640, 34)
	loadout_summary.size = Vector2(640, 34)
	right.add_child(loadout_summary)
	_refresh_loadout()
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	column.add_child(grid)
	for pair in [["Play offline · 5v5 bots", "offline"], ["Explore map · free roam", "explore"], ["Host LAN · UDP 27847", "host"], ["Join server", "join"], ["Apply loadout / Resume", "resume"], ["Restart round · host / offline", "restart"]]:
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
	controls_panel = _label("WASD move / aim with mouse · LMB fire · RMB aim / grenade detonate / double blast · SPACE jump, again in the air to double jump or at a wall to kick, walk into a ledge to mantle (S or SHIFT drops from a hang)\n1 air dash (independent of the double jump; sprint is automatic) · strafe to steer in the air · SHIFT slide, SPACE out of it to slide-jump · run along a wall to wall run · Q utility · F melee · 2 or mouse wheel swap primary / sidearm (faster than reloading) · R reload · V shoulder · TAB scoreboard\nF1 hide hints · F2 colour-blind palette · F11 fullscreen · ESC menu · Capture the centre, then advance; the final point wins.", 14, Color(1, 1, 1, 0.8))
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
	# Wrapped labels can briefly enlarge the panel before their width settles; allow it to shrink again.
	size = Vector2(980, 724).max(get_combined_minimum_size())
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

func _make_tabs() -> HBoxContainer:
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	var group := ButtonGroup.new()
	for i in range(2):
		var button := Button.new()
		button.text = ["LOADOUT", "LOOK"][i]
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(120, 28)
		UiStyle.style_button(button, false)
		button.pressed.connect(_show_tab.bind(i))
		tabs.add_child(button)
		tab_buttons.append(button)
	tab_buttons[0].button_pressed = true
	return tabs

func _show_tab(index: int) -> void:
	loadout_panel.visible = index == 0
	loadout_scroll.visible = index == 0
	item_blurb.visible = index == 0
	loadout_summary.visible = index == 0
	look_panel.visible = index == 1

func _make_look_panel() -> VBoxContainer:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)
	for groups in LOOK_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 24)
		panel.add_child(row)
		for keys in groups:
			var group := HBoxContainer.new()
			group.add_theme_constant_override("separation", 8)
			var caption := _label(_field_def(keys[0]).label, 12, UiStyle.ACCENT)
			caption.custom_minimum_size = Vector2(76, 0)
			caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			group.add_child(caption)
			for key in keys:
				group.add_child(_look_field(key))
			row.add_child(group)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 12)
	panel.add_child(bottom)
	var randomize := Button.new()
	randomize.text = "Randomize"
	randomize.custom_minimum_size = Vector2(120, 28)
	UiStyle.style_button(randomize, false)
	randomize.pressed.connect(func():
		var dice := RandomNumberGenerator.new()
		dice.randomize()
		_set_look(Appearance.random(dice)))
	bottom.add_child(randomize)
	look_summary = _label("", 13, Color(1, 1, 1, 0.85))
	look_summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(look_summary)
	_refresh_look_controls()
	return panel

func _field_def(key: String) -> Dictionary:
	for f in Appearance.FIELDS:
		if f.key == key:
			return f
	return {}

# One field's control: a "< name >" cycler (styles) or a row of swatches (colours).
func _look_field(key: String) -> Control:
	var def := _field_def(key)
	var count := Appearance.options(key).size()
	if def.kind == "style":
		var cycler := HBoxContainer.new()
		cycler.add_theme_constant_override("separation", 6)
		var name_label := _label("", 14)
		name_label.custom_minimum_size = Vector2(118, 0)
		name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		for step in [-1, 1]:
			var arrow := Button.new()
			arrow.text = "◀" if step < 0 else "▶"
			arrow.custom_minimum_size = Vector2(26, 24)
			UiStyle.style_button(arrow, false)
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
				var tight: StyleBox = arrow.get_theme_stylebox(state).duplicate()
				tight.content_margin_left = 4
				tight.content_margin_right = 4
				tight.content_margin_top = 2
				tight.content_margin_bottom = 2
				arrow.add_theme_stylebox_override(state, tight)
			arrow.pressed.connect(func():
				var current: int = Appearance.decode(game.selected_look)[key]
				_set_look(Appearance.with_field(game.selected_look, key, posmod(current + step, count))))
			cycler.add_child(arrow)
			if step < 0:
				cycler.add_child(name_label)
		look_controls[key] = name_label
		return cycler
	else:
		var swatches := HBoxContainer.new()
		swatches.add_theme_constant_override("separation", 3)
		var group := ButtonGroup.new()
		var buttons := []
		for i in range(count):
			var swatch := Button.new()
			swatch.toggle_mode = true
			swatch.button_group = group
			swatch.custom_minimum_size = Vector2(20, 22)
			swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			swatch.focus_mode = Control.FOCUS_NONE
			var color: Color = Appearance.options(key)[i]
			swatch.add_theme_stylebox_override("normal", UiStyle.box(color, Color(0, 0, 0, 0.6), 1, 0))
			swatch.add_theme_stylebox_override("hover", UiStyle.box(color, Color(1, 1, 1, 0.8), 2, 0))
			swatch.add_theme_stylebox_override("pressed", UiStyle.box(color, UiStyle.ACCENT, 3, 0))
			swatch.add_theme_stylebox_override("hover_pressed", UiStyle.box(color, UiStyle.ACCENT, 3, 0))
			swatch.pressed.connect(func(): _set_look(Appearance.with_field(game.selected_look, key, i)))
			swatches.add_child(swatch)
			buttons.append(swatch)
		look_controls[key] = buttons
		return swatches

func _set_look(code: int) -> void:
	game.selected_look = Appearance.sanitize(code)
	Appearance.save(game.selected_look)
	_refresh_look_controls()
	_refresh_loadout()

func _refresh_look_controls() -> void:
	var look := Appearance.decode(game.selected_look)
	for key in look_controls:
		var control = look_controls[key]
		if control is Label:
			control.text = Appearance.option_name(key, look[key])
		else:
			control[look[key]].button_pressed = true
	if look_summary != null:
		look_summary.text = Appearance.describe(game.selected_look)

func _pick(slot: int, index: int) -> void:
	game.selected_loadout = Loadout.with_slot(game.selected_loadout, slot, index)
	item_blurb.text = Loadout.item_blurb(slot, index)
	_refresh_loadout()

# Summary line plus a fresh portrait holding the chosen guns and melee weapon.
func _refresh_loadout() -> void:
	var code: int = game.selected_loadout
	var primary := Loadout.primary(code)
	var sidearm := Loadout.sidearm(code)
	loadout_summary.text = "HP %d · Ideal body TTK (first impact, LMB): %s %.2fs / %s %.2fs · swap %.2fs" % [int(Fighter.MAX_HEALTH), primary.title, primary.body_ttk(Fighter.MAX_HEALTH), sidearm.title, sidearm.body_ttk(Fighter.MAX_HEALTH), Fighter.SWAP_TIME]
	if spinner == null:
		return
	for child in spinner.get_children():
		child.queue_free()
	var ids := Loadout.decode(code)
	var outlines: Array = []
	CharacterRig.build(spinner, Visuals.team_color(0), outlines, false, ids[0], ids[1], ids[3], game.selected_look)
	for outline in outlines:
		outline.set_shader_parameter("outline_color", Visuals.ALLY_OUTLINE)

func _make_portrait() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(200, 250)
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
	spinner = Node3D.new()
	spinner.rotation.y = PI - 0.45  # show the face when the portrait first appears
	world.add_child(spinner)
	var camera := Camera3D.new()
	camera.fov = 38
	world.add_child(camera)
	camera.position = Vector3(0, 1.05, 3.9)
	camera.look_at_from_position(camera.position, Vector3(0, 0.95, 0))
	return viewport

func _draw() -> void:
	UiStyle.draw_panel(self, Rect2(Vector2.ZERO, size), Color(UiStyle.PANEL, 0.97), Color(UiStyle.ACCENT, 0.85), 18.0, 2.0)

func _process(dt: float) -> void:
	if not visible:
		return
	if spinner != null:
		spinner.rotation.y += dt * 0.9
