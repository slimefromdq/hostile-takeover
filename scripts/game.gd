extends Node3D

const CLASS_SCENES = [preload("res://scenes/skyrunner.tscn"), preload("res://scenes/field_engineer.tscn"), preload("res://scenes/enforcer.tscn"), preload("res://scenes/mirage_agent.tscn")]
const PORT = 27847
var authoritative := true
var running := false
var explore := false  # single-player free roam: no bots, no objective
var local_id := 1
var selected_class := 0
var fighters: Dictionary = {}
var entities: Dictionary = {}
var entity_next := 1
var match_state := Acquisition.new()
var points: Array[Vector3] = []
var bot_graph: MapGraph
var point_meshes: Array[MeshInstance3D] = []
var beacon_meshes: Array[MeshInstance3D] = []
var snapshot_timer := 0.0
var input_edges := 0
var simulation_tick := 0
# Match clock for map movers and events (scripts/map_verbs.gd). The server owns it; clients follow snapshots.
var map_clock := 0.0
var map_clock_synced := false
var menu: GameMenu
var hud: Hud
var address: LineEdit
var menu_status: Label
var tracer_root: Node3D
var menu_layer: CanvasLayer
var request_times: Dictionary = {}
var rng := RandomNumberGenerator.new()
var network_delay := 0.0
var drop_every := 0
var network_packets := 0
var last_world_tick := -1

func _ready() -> void:
	rng.seed = 47
	Visuals.load_settings()
	DisplayPrefs.load_settings()
	setup_inputs()
	points = CivicDividend.build(self)
	bot_graph = MapGraph.from_layout()
	tracer_root = Node3D.new()
	add_child(tracer_root)
	for i in range(5):
		var mesh := MeshInstance3D.new()
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = 4.5
		cylinder.bottom_radius = 4.5
		cylinder.height = 0.1
		cylinder.radial_segments = 32
		cylinder.rings = 1
		mesh.mesh = cylinder
		mesh.position = points[i] + Vector3.UP * 0.1
		mesh.material_override = Visuals.glow(Color("c4c2af"), 0.6)
		add_child(mesh)
		point_meshes.append(mesh)
		# Beacon: a thin translucent column above head height so each point is findable over the skyline.
		var beacon := MeshInstance3D.new()
		var column := CylinderMesh.new()
		column.top_radius = 0.18
		column.bottom_radius = 0.18
		column.height = 36.0
		column.radial_segments = 8
		beacon.mesh = column
		var beam := StandardMaterial3D.new()
		beam.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		beam.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		beam.albedo_color = Color(1, 1, 1, 0.3)
		beacon.material_override = beam
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		beacon.position = points[i] + Vector3.UP * 22.0
		add_child(beacon)
		beacon_meshes.append(beacon)
	make_ui()
	multiplayer.peer_connected.connect(peer_connected)
	multiplayer.peer_disconnected.connect(peer_disconnected)
	multiplayer.connected_to_server.connect(connected)
	multiplayer.connection_failed.connect(connection_failed)
	multiplayer.server_disconnected.connect(server_disconnected)
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--latency-ms="):
			network_delay = clampf(arg.get_slice("=", 1).to_float() / 1000, 0, 0.5)
		elif arg.begins_with("--drop-every="):
			drop_every = maxi(0, arg.get_slice("=", 1).to_int())
	if "--smoke" in args:
		start_game("offline")
	elif "--host-test" in args:
		start_game("host")
	elif "--join-test" in args:
		start_game("join")

func setup_inputs() -> void:
	var bindings := {"left": KEY_A, "right": KEY_D, "forward": KEY_W, "back": KEY_S, "jump": KEY_SPACE, "slide": KEY_SHIFT, "dash": KEY_1, "reload": KEY_R, "ability1": KEY_Q, "ability2": KEY_E, "ability3": KEY_F, "shoulder": KEY_V, "scoreboard": KEY_TAB}
	for action in bindings:
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = bindings[action]
		InputMap.action_add_event(action, key)
	for pair in [["fire", MOUSE_BUTTON_LEFT], ["alt", MOUSE_BUTTON_RIGHT]]:
		InputMap.add_action(pair[0])
		var mouse := InputEventMouseButton.new()
		mouse.button_index = pair[1]
		InputMap.action_add_event(pair[0], mouse)

func team_color(side: int) -> Color:
	return Visuals.team_color(side)

func local_player() -> Fighter:
	return fighters.get(local_id)

func local_team() -> int:
	var player := local_player()
	return player.team if player != null else 0

func make_ui() -> void:
	menu_layer = CanvasLayer.new()
	add_child(menu_layer)
	hud = Hud.new()
	hud.visible = false
	menu_layer.add_child(hud)
	menu = GameMenu.new()
	menu.setup(self)
	menu_layer.add_child(menu)
	menu_status = menu.status
	address = menu.address
	var overview := Camera3D.new()
	add_child(overview)
	overview.position = Vector3(0, 28, 40)
	overview.look_at(Vector3.ZERO)
	overview.current = true

func start_game(mode: String) -> void:
	if mode == "restart":
		if not running or not authoritative:
			menu_status.text = "Only the host or offline player can restart a running round."
			return
		match_state.reset()
		map_clock = 0.0
		for e in entities.values():
			remove_entity(e.entity_id)
		for p in fighters.values():
			respawn(p)
		apply_class(local_id, selected_class)
		menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		announce("NEW CONTRACT · Center point unlocked.")
		return
	if mode == "resume":
		if not running:
			return
		request_class(selected_class)
		menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if running:
		menu_status.text = "Match already running. Apply class / Resume, or restart the app."
		return
	if mode == "join":
		var client := ENetMultiplayerPeer.new()
		var err := client.create_client(address.text.strip_edges(), PORT)
		if err != OK:
			menu_status.text = "Connection could not start: %s" % error_string(err)
			return
		authoritative = false
		multiplayer.multiplayer_peer = client
		menu_status.text = "Connecting…"
		return
	if mode == "host":
		var server := ENetMultiplayerPeer.new()
		var err := server.create_server(PORT, 11)
		if err != OK:
			menu_status.text = "Host failed: %s" % error_string(err)
			return
		multiplayer.multiplayer_peer = server
	authoritative = true
	local_id = 1
	explore = mode == "explore"
	hud.explore = explore
	spawn_fighter(1, 0, selected_class, false)
	if not explore:
		for i in range(11):
			spawn_fighter(100 + i, 0 if i < 5 else 1, i % 4, true)
	running = true
	menu.hide()
	hud.show()
	local_player().camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if explore:
		announce("EXPLORATION · Free roam. No objectives, no opposition.")
		return
	announce("ACQUISITION · The center is open for business.")

func connected() -> void:
	local_id = multiplayer.get_unique_id()
	running = true
	menu.hide()
	hud.show()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	join_request.rpc_id(1, selected_class)

func connection_failed() -> void:
	menu_status.text = "Connection failed. Check server IP and UDP port 27847."
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	authoritative = true

func server_disconnected() -> void:
	running = false
	menu.show()
	hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	menu_status.text = "Server disconnected. Restart the app to start a fresh match."

func peer_connected(_id: int) -> void:
	pass

func peer_disconnected(id: int) -> void:
	if not authoritative or not fighters.has(id):
		return
	var side: int = fighters[id].team
	remove_owned(id)
	fighters[id].queue_free()
	fighters.erase(id)
	request_times.erase(id)
	var replacement := 100
	while fighters.has(replacement):
		replacement += 1
	spawn_fighter(replacement, side, replacement % 4, true)

@rpc("any_peer", "call_remote", "reliable")
func join_request(class_choice: int) -> void:
	if not authoritative:
		return
	var id := multiplayer.get_remote_sender_id()
	if fighters.has(id):
		return
	var counts := [0, 0]
	for p in fighters.values():
		if not p.bot:
			counts[p.team] += 1
	var side := 0 if counts[0] <= counts[1] else 1
	for p in fighters.values():
		if p.bot and p.team == side:
			remove_owned(p.fighter_id)
			fighters.erase(p.fighter_id)
			p.queue_free()
			break
	spawn_fighter(id, side, clampi(class_choice, 0, 3), false)
	initial_sync.rpc_id(id, encode_world())

func spawn_position(side: int, id: int) -> Vector3:
	return Vector3(-CivicDividend.spawn_x if side == 0 else CivicDividend.spawn_x, 0.2, CivicDividend.spawn_z + (abs(id) % 6) * CivicDividend.spawn_step)

func spawn_fighter(id: int, side: int, archetype: int, is_bot: bool) -> Fighter:
	var p: Fighter = CLASS_SCENES[archetype].instantiate()
	p.configure(self, id, side, archetype, is_bot)
	add_child(p)
	p.global_position = spawn_position(side, id)
	p.yaw = -PI / 2 if side == 0 else PI / 2
	fighters[id] = p
	return p

func request_class(index: int) -> void:
	if authoritative:
		apply_class(local_id, index)
	else:
		class_request.rpc_id(1, index)

@rpc("any_peer", "call_remote", "reliable")
func class_request(index: int) -> void:
	if authoritative:
		apply_class(multiplayer.get_remote_sender_id(), index)

func apply_class(id: int, index: int) -> void:
	if not fighters.has(id):
		return
	var p: Fighter = fighters[id]
	if p.hp > 0 and absf(p.global_position.x) < 80:
		if id == local_id:
			announce("Class changes are available at spawn or while awaiting respawn.")
		else:
			remote_notice.rpc_id(id, "Return to spawn to change class.")
		return
	remove_owned(id)
	p.double_id = -1
	p.change_class(index)
	p.dead_time = 0
	p.global_position = spawn_position(p.team, id)
	p.velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		hud.toggle_help()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		Sfx.set_muted(not Sfx.muted)
		announce("Sound %s." % ("muted" if Sfx.muted else "on"))
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F2:
		Visuals.set_colorblind(not Visuals.colorblind)
		announce("Colour-blind palette %s · applies as fighters respawn." % ("on" if Visuals.colorblind else "off"))
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed)):
		DisplayPrefs.toggle()
		menu.refresh_display_button()
		if DisplayPrefs.embedded():
			announce("Fullscreen unavailable while embedded in the editor. Turn off Embed Game on Next Play.")
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		menu.visible = not menu.visible
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if menu.visible else Input.MOUSE_MODE_CAPTURED
		return
	var p := local_player()
	if p == null or not running or menu.visible:
		return
	if event is InputEventMouseMotion:
		p.yaw -= event.relative.x * 0.0025
		p.pitch = clampf(p.pitch - event.relative.y * 0.0025, -1.25, 1.2)
	for pair in [["jump", 1], ["dash", 2], ["reload", 4], ["ability1", 8], ["ability2", 16], ["ability3", 32]]:
		if event.is_action_pressed(pair[0]) and not event.is_echo():
			input_edges |= pair[1]
	if event.is_action_pressed("shoulder"):
		p.shoulder *= -1

func _physics_process(dt: float) -> void:
	if not running:
		return
	simulation_tick += 1
	map_clock += dt
	MapVerbs.update(map_clock, self)
	var p := local_player()
	if p != null:
		var motion := Input.get_vector("left", "right", "forward", "back") if not menu.visible else Vector2.ZERO
		var buttons := 0
		if not menu.visible:
			buttons = (1 if Input.is_action_pressed("fire") else 0) | (2 if Input.is_action_pressed("alt") else 0) | (4 if Input.is_action_pressed("ability3") else 0) | (8 if Input.is_action_pressed("slide") else 0) | (16 if Input.is_action_pressed("jump") else 0)
		p.movement = motion
		p.held = buttons
		if authoritative:
			p.edges |= input_edges
		else:
			network_packets += 1
			if drop_every <= 0 or network_packets % drop_every != 0:
				var send_motion := send_motion_packet.bind(motion, p.yaw, p.pitch, buttons, p.shoulder)
				if network_delay > 0:
					get_tree().create_timer(network_delay).timeout.connect(send_motion)
				else:
					send_motion.call()
			if input_edges != 0:
				var send_action := send_action_packet.bind(input_edges)
				if network_delay > 0:
					get_tree().create_timer(network_delay).timeout.connect(send_action)
				else:
					send_action.call()
			if match_state.winner == -2:
				p.simulate_movement(dt, input_edges)
		input_edges = 0
	if authoritative:
		for player in fighters.values():
			if player.bot:
				bot_input(player, dt)
			elif player.fighter_id != local_id and Time.get_ticks_msec() - request_times.get(player.fighter_id, 0) > 500:
				player.held = 0
				player.movement = Vector2.ZERO
			if player.hp <= 0:
				player.dead_time -= dt
				if player.dead_time <= 0:
					respawn(player)
				continue
			if out_of_bounds(player.global_position):
				damage_fighter(player, 10000, -1)
				continue
			if match_state.winner == -2:
				player.simulate_movement(dt, player.edges)
				combat_tick(player, dt)
			player.edges = 0
		if match_state.winner == -2:
			entities_tick(dt)
			if not explore:
				objectives_tick(dt)
		snapshot_timer += dt
		if snapshot_timer >= 0.05:
			snapshot_timer = 0
			if multiplayer.has_multiplayer_peer() and multiplayer.get_peers().size() > 0:
				network_packets += 1
				if drop_every <= 0 or network_packets % drop_every != 0:
					var send_state := send_world_packet.bind(encode_world())
					if network_delay > 0:
						get_tree().create_timer(network_delay).timeout.connect(send_state)
					else:
						send_state.call()
	update_hud(dt)

# Grapples and launch pads can never carry a fighter out of the arena.
func out_of_bounds(pos: Vector3) -> bool:
	var b := CivicDividend.bounds
	return pos.x < b.position.x - 1.5 or pos.x > b.end.x + 1.5 or pos.z < b.position.y - 1.5 or pos.z > b.end.y + 1.5 or pos.y > CivicDividend.ceiling

func send_motion_packet(motion: Vector2, aim_yaw: float, aim_pitch: float, buttons: int, shoulder_value: float) -> void:
	if running and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		submit_input.rpc_id(1, motion, aim_yaw, aim_pitch, buttons, shoulder_value)

func send_action_packet(pressed: int) -> void:
	if running and multiplayer.multiplayer_peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED:
		submit_actions.rpc_id(1, pressed)

func send_world_packet(payload: PackedByteArray) -> void:
	if running and multiplayer.get_peers().size() > 0:
		snapshot.rpc(payload)

@rpc("any_peer", "call_remote", "unreliable_ordered", 1)
func submit_input(motion: Vector2, aim_yaw: float, aim_pitch: float, buttons: int, shoulder_value: float) -> void:
	if not authoritative:
		return
	var id := multiplayer.get_remote_sender_id()
	if not fighters.has(id) or not motion.is_finite() or not is_finite(aim_yaw) or not is_finite(aim_pitch):
		return
	var p: Fighter = fighters[id]
	p.movement = motion.limit_length(1.0)
	p.yaw = wrapf(aim_yaw, -PI, PI)
	p.pitch = clampf(aim_pitch, -1.25, 1.2)
	p.held = buttons & 31
	p.shoulder = 1.0 if shoulder_value >= 0 else -1.0
	request_times[id] = Time.get_ticks_msec()

@rpc("any_peer", "call_remote", "reliable", 1)
func submit_actions(pressed: int) -> void:
	if not authoritative:
		return
	var id := multiplayer.get_remote_sender_id()
	if fighters.has(id):
		fighters[id].edges |= pressed & 63

func packed_world() -> Dictionary:
	var players: Array = []
	var deploys: Array = []
	for p in fighters.values():
		players.append(p.pack())
	for e in entities.values():
		deploys.append(e.pack())
	return {"players": players, "entities": deploys, "match": match_state.pack(), "tick": simulation_tick, "mt": map_clock}

func encode_world() -> PackedByteArray:
	return var_to_bytes(packed_world()).compress(FileAccess.COMPRESSION_DEFLATE)

func decode_world(payload: PackedByteArray) -> void:
	if payload.size() > 65536:
		return
	var decoded = bytes_to_var(payload.decompress_dynamic(1048576, FileAccess.COMPRESSION_DEFLATE))
	if decoded is Dictionary:
		apply_world(decoded)

@rpc("authority", "call_remote", "reliable", 2)
func initial_sync(payload: PackedByteArray) -> void:
	if not authoritative:
		decode_world(payload)

@rpc("authority", "call_remote", "unreliable_ordered", 2)
func snapshot(payload: PackedByteArray) -> void:
	if authoritative:
		return
	decode_world(payload)

func apply_world(data: Dictionary) -> void:
	if data.tick < last_world_tick:
		return
	last_world_tick = data.tick
	if data.has("mt"):
		# Follow the server's map clock; snap on a big error, otherwise ease so platforms never jerk.
		var error: float = data.mt - map_clock
		if not map_clock_synced or absf(error) > 0.25:
			map_clock = data.mt
			map_clock_synced = true
		else:
			map_clock += error * 0.1
	var seen: Array = []
	for state in data.players:
		seen.append(state.id)
		if not fighters.has(state.id):
			spawn_fighter(state.id, state.team, state["class"], state.bot)
		fighters[state.id].unpack(state, state.id == local_id)
		if state.id == local_id:
			fighters[state.id].camera.current = true
	for id in fighters.keys():
		if not seen.has(id):
			fighters[id].queue_free()
			fighters.erase(id)
	seen.clear()
	for state in data.entities:
		seen.append(state.id)
		if not entities.has(state.id):
			create_entity_from(state)
		var e: Deployable = entities[state.id]
		e.global_position = state.pos
		e.rotation.y = state.yaw
		e.hp = state.hp
		e.used = state.used
		e.update_visual()
	for id in entities.keys():
		if not seen.has(id):
			entities[id].queue_free()
			entities.erase(id)
	match_state.unpack(data.match)

func ray(from: Vector3, to: Vector3, exclude: Array = [], mask: int = 15) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, mask)
	query.exclude = exclude
	return get_world_3d().direct_space_state.intersect_ray(query)

func respawn(p: Fighter) -> void:
	remove_owned(p.fighter_id)
	p.double_id = -1
	p.bot_path.clear()
	p.bot_bias.clear()
	p.change_class(p.class_id)
	p.global_position = spawn_position(p.team, p.fighter_id)
	p.velocity = Vector3.ZERO
	p.idle_weapon = 2
	p.air_dash = true
	p.held = 0
	p.edges = 0

func combat_tick(p: Fighter, dt: float) -> void:
	for i in range(3):
		p.cooldowns[i] = maxf(0, p.cooldowns[i] - dt)
	p.shot_timer = maxf(0, p.shot_timer - dt)
	p.alt_timer = maxf(0, p.alt_timer - dt)
	p.conceal = maxf(0, p.conceal - dt)
	p.reveal = maxf(0, p.reveal - dt)
	p.melee_buff = maxf(0, p.melee_buff - dt)
	p.gun_buff = maxf(0, p.gun_buff - dt)
	if p.edges & 4 and p.ammo < p.spec.magazine and p.reload_timer <= 0:
		p.reload_timer = p.spec.reload_time * (0.8 if p.hot_lap > 0 else 1.0)
	if p.reload_timer > 0:
		p.reload_timer -= dt
		if p.reload_timer <= 0:
			p.ammo = p.spec.magazine
	for i in range(3):
		if p.edges & (8 << i):
			activate(p, i)
	if p.class_id == 2:
		p.spin = move_toward(p.spin, 1.0 if p.held & 1 else 0.0, dt / (0.25 if p.melee_buff > 0 else 0.6))
	if p.held & 2:
		p.conceal = 0
		if p.class_id == 0:
			p.charge += dt
			if p.charge >= 0.9 and p.shot_timer <= 0.00001 and p.ammo >= 3 and p.reload_timer <= 0:
				p.ammo -= 3
				p.shot_timer = 0.9
				p.charge = 0
				fire_ray(p, 60, false)
		elif p.class_id == 1 and p.alt_timer <= 0:
			p.alt_timer = 0.35
			var hit := ray(p.muzzle(), p.aim_point(), [p.get_rid()])
			if not hit.is_empty() and hit.collider is Deployable and hit.collider.team == p.team:
				hit.collider.hp = minf(hit.collider.max_hp, hit.collider.hp + 30)
			show_trace(p.muzzle(), hit.position if not hit.is_empty() else p.aim_point(), team_color(p.team), Vfx.Style.REPAIR)
		elif p.class_id == 2 and p.alt_timer <= 0:
			p.alt_timer = 0.65 if p.gun_buff > 0 else 0.9
			if cone_attack(p, 3.0, 75, 0.35, 3.0) > 0:
				p.melee_buff = 2.0
			show_trace(p.muzzle(), p.muzzle() + p.horizontal_direction() * 3, Color.WHITE, Vfx.Style.SWOOSH)
	else:
		p.charge = 0
	# Bursts finish their committed three-shot sequence even if fire is released.
	if p.burst_left > 0:
		p.burst_timer -= dt
		if p.burst_timer <= 0.00001 and p.ammo > 0 and p.reload_timer <= 0:
			p.burst_left -= 1
			p.burst_timer += p.spec.burst_gap
			p.ammo -= 1
			p.conceal = 0
			p.idle_weapon = 0
			fire_ray(p, p.spec.damage, false)
	elif p.held & 1 and not p.held & 2 and p.shot_timer <= 0.00001 and p.reload_timer <= 0 and (p.class_id != 2 or p.spin >= 0.99):
		if p.ammo <= 0:
			p.reload_timer = p.spec.reload_time * (0.8 if p.hot_lap > 0 else 1.0)
		else:
			p.conceal = 0
			p.ammo -= 1
			p.shot_timer = p.spec.interval
			p.burst_left = p.spec.burst - 1
			p.burst_timer = p.spec.burst_gap
			fire_ray(p, p.spec.damage, p.class_id == 3)
	if p.rush_time > 0:
		for target in fighters.values():
			if target.team != p.team and target.hp > 0 and not p.rush_hit.has(target.fighter_id) and target.global_position.distance_to(p.global_position) < 1.8:
				p.rush_hit.append(target.fighter_id)
				damage_fighter(target, 35, p.fighter_id)
	p.update_visual()

func fire_ray(p: Fighter, amount: float, ricochet: bool) -> void:
	var cue: int = [Sfx.Kind.SHOT_SKYRUNNER, Sfx.Kind.SHOT_ENGINEER, Sfx.Kind.SHOT_ENFORCER, Sfx.Kind.SHOT_MIRAGE][p.class_id]
	if p.class_id == 0 and amount > 30.0:
		cue = Sfx.Kind.SHOT_CHARGED
	play_sfx(p.global_position, cue)
	var from := p.muzzle()
	var toward := (p.aim_point() - from).normalized()
	if p.class_id == 1:
		var best: Fighter = null
		var best_dot := cos(deg_to_rad(10.0))
		for target in fighters.values():
			if target.team == p.team or target.hp <= 0:
				continue
			var diff: Vector3 = target.global_position + Vector3.UP - from
			if diff.length() <= p.spec.reach and toward.dot(diff.normalized()) > best_dot:
				var sight := ray(from, target.global_position + Vector3.UP, [p.get_rid()])
				if not sight.is_empty() and sight.collider == target:
					best = target
					best_dot = toward.dot(diff.normalized())
		if best != null:
			toward = (best.global_position + Vector3.UP - from).normalized()
	var hit := ray(from, from + toward * p.spec.reach, [p.get_rid()])
	var end: Vector3 = from + toward * p.spec.reach if hit.is_empty() else hit.position
	var style: int = [Vfx.Style.SKYRUNNER, Vfx.Style.ARC, Vfx.Style.ENFORCER, Vfx.Style.MIRAGE][p.class_id]
	if p.class_id == 0 and amount > 30.0:
		style = Vfx.Style.CHARGED
	show_trace(from, end, team_color(p.team), style, not hit.is_empty())
	if hit.is_empty():
		p.consecutive_hits = 0
		return
	if hit.collider is Fighter or hit.collider is Deployable:
		apply_hit(p, hit, amount)
	elif ricochet:
		var remaining := p.spec.reach - from.distance_to(hit.position)
		var bounce := toward.bounce(hit.normal)
		var start: Vector3 = hit.position + hit.normal * 0.04
		var second := ray(start, start + bounce * remaining, [p.get_rid()])
		show_trace(start, start + bounce * remaining if second.is_empty() else second.position, Color("ffe0ab"), Vfx.Style.BOUNCE, not second.is_empty())
		if not second.is_empty():
			apply_hit(p, second, amount)
	# Double echoes are visual only, never a second damage ray.
	if entities.has(p.double_id):
		var e: Deployable = entities[p.double_id]
		show_trace(e.global_position + Vector3.UP * 1.3, e.global_position + Vector3.UP * 1.3 + toward * 8, team_color(p.team).darkened(0.3))
		play_sfx(e.global_position, cue)

func apply_hit(p: Fighter, hit: Dictionary, amount: float) -> void:
	var object = hit.collider
	if object is Fighter and object.team != p.team:
		var headshot: bool = hit.position.y - object.global_position.y > 1.55
		damage_fighter(object, amount * (1.35 if headshot and p.class_id != 1 else 1.0), p.fighter_id)
		p.consecutive_hits += 1
		if p.class_id == 2 and p.consecutive_hits >= 5:
			p.gun_buff = 2.0
		hit_feedback(p.fighter_id, 2 if object.hp <= 0 else (1 if headshot and p.class_id != 1 else 0))
	elif object is Deployable and object.team != p.team:
		object.hp -= amount
		object.last_damage = object.age
		hit_feedback(p.fighter_id)
	else:
		p.consecutive_hits = 0

func damage_fighter(target: Fighter, amount: float, attacker: int) -> void:
	if target.hp <= 0 or not authoritative:
		return
	# Sheltered depot interiors prevent spawn farming; leaving the depot ends protection.
	if absf(target.global_position.x) > CivicDividend.depot_limit and attacker >= 0:
		return
	target.hp = maxf(0, target.hp - amount)
	target.reveal = 0.65
	var source: Fighter = fighters.get(attacker)
	if source != null and not target.bot:
		if target.fighter_id == local_id:
			hud.damaged(source.global_position)
		else:
			damage_taken.rpc_id(target.fighter_id, source.global_position)
	if target.hp <= 0:
		target.deaths += 1
		target.dead_time = 5.0
		target.velocity = Vector3.ZERO
		target.grapple_time = 0
		target.conceal = 0
		remove_owned(target.fighter_id)
		target.double_id = -1
		target.update_visual()
		if source != null:
			source.kills += 1
			kill_feed(source.spec.title, source.team, target.spec.title, target.team)
			if multiplayer.get_peers().size() > 0:
				kill_feed.rpc(source.spec.title, source.team, target.spec.title, target.team)
			var line: String = source.spec.quips[rng.randi_range(0, source.spec.quips.size() - 1)]
			if attacker == local_id:
				character_quip(line)
			elif not source.bot:
				character_quip.rpc_id(attacker, line)

func cone_attack(p: Fighter, reach: float, amount: float, dot_limit: float, push: float) -> int:
	var hits := 0
	for target in fighters.values():
		var diff: Vector3 = target.global_position - p.global_position
		if target.team == p.team or target.hp <= 0 or diff.length() > reach or p.horizontal_direction().dot(diff.normalized()) < dot_limit:
			continue
		var sight := ray(p.muzzle(), target.global_position + Vector3.UP, [p.get_rid()])
		if sight.is_empty() or sight.collider != target:
			continue
		damage_fighter(target, amount, p.fighter_id)
		var reduction := 0.5 if target.class_id == 2 and target.spin > 0.8 and target.horizontal_direction().dot(-diff.normalized()) > 0.5 else 1.0
		target.velocity += diff.normalized() * push * reduction
		hits += 1
	return hits

func activate(p: Fighter, slot: int) -> void:
	if p.hp <= 0:
		return
	if p.class_id == 0 and slot == 0 and p.grapple_time > 0:
		p.grapple_time = 0
		p.hot_lap = 2
		return
	if p.class_id == 3 and slot == 0 and entities.has(p.double_id):
		var double: Deployable = entities[p.double_id]
		if not double.used and double.hp > 0 and p.global_position.distance_to(double.global_position) <= 25 and clear_body(p, double.global_position) and clear_double(double, p.global_position):
			var old := p.global_position
			show_trace(old + Vector3.UP, double.global_position + Vector3.UP, Color("d9b8ff"))
			p.global_position = double.global_position
			double.global_position = old
			double.used = true
			p.ammo = mini(p.spec.magazine, p.ammo + 1)
			p.idle_weapon = 1.25
			play_sfx(old, Sfx.Kind.SWAP)
			play_sfx(p.global_position, Sfx.Kind.SWAP)
		return
	if p.cooldowns[slot] > 0:
		return
	var success := true
	match p.class_id:
		0:
			match slot:
				0:
					if p.grapple_time > 0:
						p.grapple_time = 0
						p.hot_lap = 2
					else:
						var hit := ray(p.muzzle(), p.muzzle() + p.direction() * 28, [p.get_rid()], 1 | 4)
						if hit.is_empty():
							success = false
						else:
							p.grapple = hit.position
							play_sfx(p.global_position, Sfx.Kind.GRAPPLE)
							p.grapple_time = 2.5
							p.hot_lap = 2
				1:
					p.velocity += Vector3.UP * 12.5 + p.horizontal_direction() * 3
					show_ring(p.global_position, 1.6, team_color(p.team))
					play_sfx(p.global_position, Sfx.Kind.KICKOFF)
				2:
					p.brake_time = 2
					show_ring(p.global_position + Vector3.UP * 0.6, 1.2, Color("ffe2a3"))
					play_sfx(p.global_position, Sfx.Kind.BRAKE)
		1:
			match slot:
				0, 1:
					var place := placement(p, 8.0)
					if place == Vector3.INF:
						success = false
					else:
						var kind := "turret" if slot == 0 else "pad"
						for e in entities.values():
							if e.owner_id == p.fighter_id and e.kind == kind:
								remove_entity(e.entity_id)
						create_entity(p, kind, place, 100 if slot == 0 else 80, 90)
				2:
					var nearest: Deployable = null
					for e in entities.values():
						if e.owner_id == p.fighter_id and e.kind in ["turret", "pad"] and (nearest == null or p.global_position.distance_to(e.global_position) < p.global_position.distance_to(nearest.global_position)):
							nearest = e
					if nearest == null:
						success = false
					else:
						var refund_slot := 0 if nearest.kind == "turret" else 1
						p.cooldowns[refund_slot] = maxf(0, p.cooldowns[refund_slot] - p.spec.cooldowns[refund_slot] * 0.5)
						remove_entity(nearest.entity_id)
		2:
			match slot:
				0:
					p.rush_time = 0.5
					show_ring(p.global_position, 1.8, Color("ff8a4c"))
					play_sfx(p.global_position, Sfx.Kind.BREACH)
					show_trace(p.global_position + Vector3.UP * 0.8, p.global_position + Vector3.UP * 0.8 + p.horizontal_direction() * 8, Color("ffd9a0"), Vfx.Style.SWOOSH)

					p.rush_hit.clear()
				1:
					var place := placement(p, 4)
					if place == Vector3.INF:
						success = false
					else:
						create_entity(p, "cover", place, 180, 8)
				2:
					cone_attack(p, 5, 30, 0.4, 9)
					show_ring(p.global_position, 5.0, team_color(p.team))
					show_trace(p.global_position + Vector3.UP * 0.6, p.global_position + Vector3.UP * 0.6 + p.horizontal_direction() * 5, Color("ffd9a0"), Vfx.Style.SWOOSH)
					play_sfx(p.global_position, Sfx.Kind.EVICT)
		3:
			match slot:
				0:
					var place := placement(p, 15)
					if place == Vector3.INF or not clear_body(p, place):
						success = false
					else:
						if entities.has(p.double_id):
							remove_entity(p.double_id)
						p.double_id = create_entity(p, "double", place, p.spec.health * 0.25, 8)
				1:
					p.conceal = 0
					throw_capsule(p)
				2:
					create_entity(p, "smoke", p.global_position, 1, 3)
					show_ring(p.global_position, 2.5, Color("c7a8f1"))
					play_sfx(p.global_position, Sfx.Kind.SMOKE)
					p.conceal = 2.5
	if success:
		p.cooldowns[slot] = p.spec.cooldowns[slot]
		if p.fighter_id == local_id:
			announce(p.spec.abilities[slot])

func placement(p: Fighter, reach: float) -> Vector3:
	var origin := p.global_position + Vector3.UP * 1.5
	var end := origin + p.direction() * reach
	var hit := ray(origin, end, [p.get_rid()], 1 | 4)
	if not hit.is_empty():
		end = hit.position + hit.normal * 0.7
	var ground := ray(end + Vector3.UP * 0.5, end + Vector3.DOWN * 12, [p.get_rid()], 1)
	if ground.is_empty() or ground.normal.y < 0.7:
		return Vector3.INF
	return ground.position + Vector3.UP * 0.05

func clear_body(p: Fighter, pos: Vector3) -> bool:
	var shape := CapsuleShape3D.new()
	shape.radius = 0.39
	shape.height = 1.9
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, pos + Vector3.UP * 0.97)
	query.collision_mask = 1 | 2 | 4 | 8
	var exclusions: Array[RID] = [p.get_rid()]
	if entities.has(p.double_id):
		exclusions.append(entities[p.double_id].get_rid())
	query.exclude = exclusions
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func clear_double(e: Deployable, pos: Vector3) -> bool:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 1.7, 0.55)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(Vector3.UP, e.rotation.y), pos + Vector3.UP * 0.9)
	query.collision_mask = 1 | 2 | 4
	query.exclude = [e.get_rid(), fighters[e.owner_id].get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func create_entity(p: Fighter, kind: String, pos: Vector3, hp_value: float, life: float) -> int:
	var data := {"id": entity_next, "owner": p.fighter_id, "team": p.team, "kind": kind, "hp": hp_value, "life": life, "pos": pos, "yaw": p.yaw, "used": false}
	entity_next += 1
	create_entity_from(data)
	if kind != "smoke":
		play_sfx(pos, Sfx.Kind.PLACE)
	return data.id

func create_entity_from(data: Dictionary) -> void:
	var e := Deployable.new()
	e.configure(self, data)
	add_child(e)
	e.global_position = data.pos
	e.rotation.y = data.yaw
	e.used = data.used
	entities[data.id] = e
	e.update_visual()

func remove_entity(id: int) -> void:
	if entities.has(id):
		var e: Deployable = entities[id]
		if e.kind == "double" and fighters.has(e.owner_id) and fighters[e.owner_id].double_id == id:
			fighters[e.owner_id].double_id = -1
		e.collision_layer = 0
		e.queue_free()
		entities.erase(id)

func remove_owned(id: int) -> void:
	for e in entities.values():
		if e.owner_id == id:
			remove_entity(e.entity_id)

func entities_tick(dt: float) -> void:
	for e in entities.values():
		e.age += dt
		e.timer = maxf(0, e.timer - dt)
		if e.age >= e.lifetime or e.hp <= 0:
			remove_entity(e.entity_id)
			continue
		var owner: Fighter = fighters.get(e.owner_id)
		if e.kind in ["turret", "pad"] and owner != null and owner.hp > 0 and owner.global_position.distance_to(e.global_position) < 12 and e.age - e.last_damage > 4:
			e.hp = minf(e.max_hp, e.hp + 8 * dt)
		if e.kind == "double" and owner != null:
			e.rotation.y = owner.yaw
		if e.kind == "pad" and e.timer <= 0:
			for p in fighters.values():
				if p.hp > 0 and p.global_position.distance_to(e.global_position) < 1.7:
					p.velocity.y = 14.5
					show_ring(e.global_position, 1.7, team_color(e.team))
					e.timer = 0.7
					play_sfx(e.global_position, Sfx.Kind.PAD)
		elif e.kind == "turret" and e.timer <= 0:
			var forward := Basis(Vector3.UP, e.rotation.y) * Vector3.FORWARD
			var from: Vector3 = e.global_position + Vector3.UP * 0.85
			for target in fighters.values():
				var diff: Vector3 = target.global_position + Vector3.UP - from
				if target.team == e.team or target.hp <= 0 or diff.length() > 14 or forward.dot(diff.normalized()) < 0.5:
					continue
				var hit := ray(from, target.global_position + Vector3.UP, [e.get_rid()])
				if not hit.is_empty() and hit.collider == target:
					damage_fighter(target, 6, e.owner_id)
					e.timer = 0.3
					show_trace(from, hit.position, team_color(e.team), Vfx.Style.SKYRUNNER, true)
					play_sfx(from, Sfx.Kind.TURRET)
					break
		e.update_visual()

func throw_capsule(p: Fighter) -> void:
	var capsule := preload("res://scripts/dead_drop.gd").new()
	capsule.configure(self, p)
	add_child(capsule)
	capsule.global_position = p.muzzle()
	if entities.has(p.double_id):
		var e: Deployable = entities[p.double_id]
		show_trace(e.global_position + Vector3.UP, e.global_position + Vector3.UP + p.direction() * 5, team_color(p.team))

func objectives_tick(dt: float) -> void:
	var occupancy: Array = []
	for point in points:
		var counts := [0, 0]
		for p in fighters.values():
			if p.hp > 0 and Vector2(p.global_position.x - point.x, p.global_position.z - point.z).length() < 4.5 and absf(p.global_position.y - point.y) < 2.0:
				counts[p.team] += 1
		occupancy.append(counts)
	match_state.tick(dt, occupancy)
	for capture in match_state.captures:
		var message := "%s acquired point %s" % ["HELIX" if capture[1] == 0 else "MONARCH", String.chr(65 + capture[0])]
		announce(message)
		play_sfx(points[capture[0]], Sfx.Kind.CAPTURE)
		if multiplayer.get_peers().size() > 0:
			remote_notice.rpc(message)

func bot_input(p: Fighter, dt: float) -> void:
	if p.hp <= 0:
		return
	p.bot_think -= dt
	if p.bot_think <= 0:
		p.bot_think = rng.randf_range(0.25, 0.5)
		var objective := 2
		var closest := INF
		for i in range(5):
			if match_state.unlocked[i] and match_state.owners[i] != p.team:
				var distance := p.global_position.distance_to(points[i])
				if distance < closest:
					closest = distance
					objective = i
		p.bot_target = points[objective] + Vector3(rng.randf_range(-2, 2), 0, rng.randf_range(-2, 2))
		if objective != p.bot_goal or p.bot_path.is_empty():
			plan_bot_path(p, objective)
		p.aim_target = -1
		closest = 30
		for target in fighters.values():
			if target.team == p.team or target.hp <= 0 or target.conceal > 0 and target.reveal <= 0:
				continue
			var distance := p.global_position.distance_to(target.global_position)
			if distance < closest:
				var hit := ray(p.muzzle(), target.global_position + Vector3.UP, [p.get_rid()])
				if not hit.is_empty() and hit.collider == target:
					closest = distance
					p.aim_target = target.fighter_id
	var destination := bot_waypoint(p, dt)
	var target: Fighter = fighters.get(p.aim_target)
	var diff := destination - p.global_position
	var aim := diff.normalized()
	p.held = 0
	if target != null and target.hp > 0:
		var target_diff := target.global_position + Vector3.UP * 1.1 - p.muzzle()
		aim = target_diff.normalized()
		if target_diff.length() <= p.spec.reach:
			p.held = 1
		if p.class_id == 2 and target_diff.length() < 3:
			p.held = 2
		if rng.randf() < dt * 0.25:
			p.edges |= 16
	if aim.length() > 0.01:
		p.yaw = lerp_angle(p.yaw, atan2(-aim.x, -aim.z), minf(1, dt * 9))
		p.pitch = lerpf(p.pitch, asin(clampf(aim.y, -1, 1)), minf(1, dt * 9))
	var local_move := Basis(Vector3.UP, -p.yaw) * diff.normalized()
	var stopping_distance := 2.0 if p.bot_path_i >= p.bot_path.size() - 1 else 0.4
	p.movement = Vector2(local_move.x, local_move.z) if diff.length() > stopping_distance else Vector2.ZERO
	if p.is_on_wall() or p.is_on_floor() and p.get_real_velocity().length() < 1 and p.movement.length() > 0.1:
		p.edges |= 1
	if p.class_id == 1 and absf(p.global_position.x) < 75 and rng.randf() < dt * 0.25:
		p.edges |= 8
	elif p.class_id == 3 and rng.randf() < dt * 0.2:
		p.edges |= 8 if p.double_id < 0 else 32
	elif p.class_id == 0 and target != null and rng.randf() < dt * 0.1:
		p.edges |= 16

# Each bot commits to a route family (class-weighted odds) so a squad spreads over the flanks;
# the chosen family is cheap to path through, the others expensive but still usable as connectors.
func bot_weights(p: Fighter) -> Dictionary:
	if p.bot_bias.is_empty():
		var odds := {"blv": 0.25, "roof": 0.25, "trn": 0.25, "aln": 0.25}
		match p.class_id:
			0:
				odds = {"blv": 0.2, "roof": 0.4, "trn": 0.2, "aln": 0.2}
			1:
				odds = {"blv": 0.25, "roof": 0.1, "trn": 0.35, "aln": 0.3}
			2:
				odds = {"blv": 0.45, "roof": 0.1, "trn": 0.3, "aln": 0.15}
		var roll := rng.randf()
		var chosen := "blv"
		for tag in odds:
			roll -= odds[tag]
			if roll <= 0.0:
				chosen = tag
				break
		for tag in odds:
			p.bot_bias[tag] = (0.4 if tag == chosen else 2.0) * rng.randf_range(0.9, 1.1)
	return p.bot_bias.duplicate()

func plan_bot_path(p: Fighter, objective: int) -> void:
	p.bot_goal = objective
	p.bot_path = bot_graph.path(bot_graph.nearest(p.global_position), bot_graph.node(CivicDividend.goal_names[objective]), bot_weights(p))
	p.bot_path_i = 0
	p.bot_progress_pos = p.global_position
	p.bot_progress_time = 0.0

# Current steering target: next waypoint on the planned route, then the capture point itself.
func bot_waypoint(p: Fighter, dt: float) -> Vector3:
	if p.bot_path.is_empty():
		return p.bot_target
	while p.bot_path_i < p.bot_path.size() - 1:
		var wp: Vector3 = p.bot_path[p.bot_path_i]
		if Vector2(wp.x - p.global_position.x, wp.z - p.global_position.z).length() < 1.4 and absf(wp.y - p.global_position.y) < 2.0:
			p.bot_path_i += 1
		else:
			break
	# Replan when wedged: little horizontal progress while trying to move.
	p.bot_progress_time += dt
	if p.bot_progress_time > 2.0:
		var moved := Vector2(p.global_position.x - p.bot_progress_pos.x, p.global_position.z - p.bot_progress_pos.z).length()
		if moved < 0.8 and p.bot_path_i < p.bot_path.size() - 1:
			p.bot_bias.clear()
			plan_bot_path(p, p.bot_goal)
			p.edges |= 1
		p.bot_progress_pos = p.global_position
		p.bot_progress_time = 0.0
	if p.bot_path.is_empty():
		# The replan found no route (the bot is somewhere the graph does not cover): head for the point directly.
		return p.bot_target
	if p.bot_path_i >= p.bot_path.size() - 1:
		return p.bot_target if Vector2(p.bot_target.x - p.global_position.x, p.bot_target.z - p.global_position.z).length() < 12.0 else p.bot_path[p.bot_path.size() - 1]
	return p.bot_path[p.bot_path_i]

func show_trace(from: Vector3, to: Vector3, color: Color, style: int = 0, with_impact: bool = false) -> void:
	trace_visual(from, to, color, style, with_impact)
	if authoritative and multiplayer.get_peers().size() > 0:
		trace_visual.rpc(from, to, color, style, with_impact)

@rpc("authority", "call_remote", "unreliable", 3)
func trace_visual(from: Vector3, to: Vector3, color: Color, style: int = 0, with_impact: bool = false) -> void:
	Vfx.tracer(tracer_root, from, to, style, color, with_impact)

func show_ring(pos: Vector3, radius: float, color: Color) -> void:
	ring_visual(pos, radius, color)
	if authoritative and multiplayer.get_peers().size() > 0:
		ring_visual.rpc(pos, radius, color)

@rpc("authority", "call_remote", "unreliable", 3)
func ring_visual(pos: Vector3, radius: float, color: Color) -> void:
	Vfx.ring(tracer_root, pos, radius, color)

func hit_feedback(id: int, kind: int = 0) -> void:
	if id == local_id:
		hit_confirm(kind)
	elif fighters.has(id) and not fighters[id].bot:
		hit_confirm.rpc_id(id, kind)

@rpc("authority", "call_remote", "unreliable")
func hit_confirm(kind: int = 0) -> void:
	hud.hit(kind)
	Sfx.play_ui(self, [Sfx.Kind.HIT, Sfx.Kind.HEADSHOT, Sfx.Kind.KILL][clampi(kind, 0, 2)])

@rpc("authority", "call_remote", "unreliable")
func damage_taken(from_pos: Vector3) -> void:
	hud.damaged(from_pos)

@rpc("authority", "call_remote", "reliable")
func kill_feed(killer_title: String, killer_team: int, victim_title: String, victim_team: int) -> void:
	hud.add_kill(killer_title, killer_team, victim_title, victim_team)

@rpc("authority", "call_remote", "unreliable")
func character_quip(value: String) -> void:
	hud.quip(value)

@rpc("authority", "call_remote", "reliable")
func remote_notice(value: String) -> void:
	announce(value)

func announce(value: String) -> void:
	hud.announce(value)

func play_sfx(pos: Vector3, kind: int) -> void:
	sfx_visual(pos, kind)
	if authoritative and multiplayer.get_peers().size() > 0:
		sfx_visual.rpc(pos, kind)

@rpc("authority", "call_remote", "unreliable")
func sfx_visual(pos: Vector3, kind: int) -> void:
	Sfx.play_at(self, pos, kind)

# Capture discs and beacons take the owner's colour; locked points are dimmed.
func update_points() -> void:
	for i in range(point_meshes.size()):
		var owner: int = match_state.owners[i]
		var color := team_color(owner) if owner >= 0 else Color("c4c2af")
		if not match_state.unlocked[i]:
			color = color.darkened(0.55)
		var disc: StandardMaterial3D = point_meshes[i].material_override
		disc.albedo_color = color
		disc.emission = color
		var beam: StandardMaterial3D = beacon_meshes[i].material_override
		beam.albedo_color = Color(color, 0.12 if not match_state.unlocked[i] else 0.35)

func update_hud(dt: float) -> void:
	update_points()
	hud.refresh(self, dt)
	var p := local_player()
	if p == null:
		return
	# Ricochet preview is local presentation only and never deals damage.
	if p.class_id == 3 and p.held & 2 and simulation_tick % 4 == 0:
		var start := p.muzzle()
		var direction := (p.aim_point() - start).normalized()
		var hit := ray(start, start + direction * p.spec.reach, [p.get_rid()])
		trace_visual(start, start + direction * p.spec.reach if hit.is_empty() else hit.position, Color("bc9ee8"))
		if not hit.is_empty() and not hit.collider is Fighter and not hit.collider is Deployable:
			var next: Vector3 = hit.position + hit.normal * 0.05
			var end: Vector3 = next + direction.bounce(hit.normal) * (p.spec.reach - start.distance_to(hit.position))
			var second := ray(next, end, [p.get_rid()])
			trace_visual(next, end if second.is_empty() else second.position, Color("e1c7ff"))
