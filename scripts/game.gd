extends Node3D

const FIGHTER_SCENE = preload("res://scenes/fighter.tscn")
const PORT = 27847
# Health packs (blockout "pickup" features): an instant heal, then a regen that enemy hero damage cancels.
const PACK_HEAL := 60.0
const PACK_REGEN := 150.0
const PACK_REGEN_TIME := 5.0
const PACK_RESPAWN := 25.0
const PACK_RADIUS := 1.5
const ARMOR_DROP := 15.0  # light armor dropped by a kill, for the killer's team
const ARMOR_DROP_BEHIND := 10.0  # extra per point the killer's team is behind (up to 2)
const ARMOR_DROP_LIFE := 20.0
# Bot roles (see assign_bot_role). Capture speed stops growing at three capturers; a fourth covers contest fights.
const BOT_MAX_ATTACKERS := 4
const BOT_ROAM_CHANCE := 0.3  # chance an attacker slot rotates to a roam/defend role anyway
const BOT_DEFEND_SHARE := 0.3  # share of non-attack roles that patrol an owned point instead of flanking
const BOT_ROLE_MIN := 6.0
const BOT_ROLE_MAX := 11.0
const BOT_ROAM_RADIUS := 55.0
const BOT_DEFEND_RADIUS := 24.0
const BOT_POINT_RING := 3.4  # attackers hold spots inside the 4.5 m capture radius
const BOT_PAUSE_MIN := 0.8
const BOT_PAUSE_MAX := 2.5
const BOT_SIGHT := 30.0
const BOT_ITEM_RANGE := 30.0  # bots only detour for a timed item this close (horizontal)
const BOT_ITEM_TIME := 10.0  # give up on a detour after this long
const BOT_POWER_RANGE := 60.0  # the power-up is worth a longer trip (it can sit up a tower)
const BOT_POWER_PATH := 110.0  # but only if the graph route to it is no longer than this
const BOT_POWER_TIME := 35.0  # time allowed for a detour to the power-up (ladders are slow)
const BOT_JUMP_DISTANCE := 3.3  # a bot jumps a graph "jmp" link once this close to its far end
const BOT_SIDEARM_RANGE := 15.0  # an empty primary swaps to the sidearm when the target is this close
const BOT_ITEM_VALUE := {"bubble": 1.0, "armor1": 2.0, "armor2": 3.0, "power": 6.0}
const ASSIST_WINDOW := 6.0  # seconds a recent attacker still counts for an assist
# Input edges: one-shot presses, OR-ed together until the server's next tick consumes them.
const EDGE_JUMP := 1
const EDGE_DASH := 2
const EDGE_RELOAD := 4
const EDGE_UTILITY := 8  # Q
const EDGE_MELEE := 16  # F
const EDGE_SWAP := 32  # 2 or the mouse wheel: primary <-> sidearm
const EDGE_ALL := 63
const HELD_BITS := 27  # held buttons: 1 fire, 2 aim down sights (RMB), 8 slide, 16 jump
var authoritative := true
var running := false
var explore := false  # single-player free roam: no bots, no objective
var local_id := 1
# Test cheats (F6 cooldowns, F8 damage, F9 full heal); host/offline only.
var cheat_no_cooldowns := false
var cheat_invulnerable := false
var selected_loadout := Loadout.encode(1, 0, Loadout.Utility.FRAG_GRENADE, Loadout.Melee.KNIFE)
var selected_look := Appearance.load_saved()  # the start menu's LOOK tab; saved in user://settings.cfg
var fighters: Dictionary = {}
var entities: Dictionary = {}
var entity_next := 1
var match_state := Acquisition.new()
var points: Array[Vector3] = []
var bot_graph: MapGraph
var bot_enemies: Array = [[], []]  # per team: living, visible fighters; rebuilt each physics tick for bot target search
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
	var bindings := {"left": KEY_A, "right": KEY_D, "forward": KEY_W, "back": KEY_S, "jump": KEY_SPACE, "slide": KEY_SHIFT, "dash": KEY_1, "reload": KEY_R, "utility": KEY_Q, "melee": KEY_F, "swap": KEY_2, "shoulder": KEY_V, "scoreboard": KEY_TAB}
	if InputMap.has_action("fire"):
		return  # another Game instance (a restart from the editor, a test) already registered them
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
	for wheel in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var scroll := InputEventMouseButton.new()
		scroll.button_index = wheel
		InputMap.action_add_event("swap", scroll)

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
		spawn_pickups()
		for p in fighters.values():
			respawn(p)
		apply_loadout(local_id, selected_loadout)
		apply_look(local_id, selected_look)
		menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		announce("NEW CONTRACT · Center point unlocked.")
		return
	if mode == "resume":
		if not running:
			return
		request_loadout(selected_loadout, selected_look)
		menu.hide()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if running:
		menu_status.text = "Match already running. Apply loadout / Resume, or restart the app."
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
		var err := server.create_server(PORT, CivicDividend.TEAM_SIZE * 2 - 1)
		if err != OK:
			menu_status.text = "Host failed: %s" % error_string(err)
			return
		multiplayer.multiplayer_peer = server
	authoritative = true
	local_id = 1
	explore = mode == "explore"
	hud.explore = explore
	spawn_fighter(1, 0, selected_loadout, false, selected_look)
	if not explore:
		for i in range(CivicDividend.TEAM_SIZE * 2 - 1):
			spawn_fighter(100 + i, 0 if i < CivicDividend.TEAM_SIZE - 1 else 1, bot_loadout(i), true, bot_look(100 + i))
	spawn_pickups()
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
	join_request.rpc_id(1, selected_loadout, selected_look)

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
	spawn_fighter(replacement, side, bot_loadout(replacement), true, bot_look(replacement))

@rpc("any_peer", "call_remote", "reliable")
func join_request(loadout_code: int, look_code: int) -> void:
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
	spawn_fighter(id, side, loadout_code, false, look_code)  # Fighter.equip and Appearance.sanitize clamp every field
	initial_sync.rpc_id(id, encode_world())

# Lowest depot slot on the team that no teammate holds, so a full team never shares a spawn (peer ids are arbitrary).
func free_spawn_slot(side: int) -> int:
	var taken := {}
	for other in fighters.values():
		if other.team == side:
			taken[other.spawn_slot] = true
	for slot in range(CivicDividend.TEAM_SIZE):
		if not taken.has(slot):
			return slot
	return fighters.size() % CivicDividend.TEAM_SIZE

func spawn_position(p: Fighter) -> Vector3:
	return CivicDividend.spawn_slot_position(p.team, p.spawn_slot)

# Bots cycle through the primaries so a match exercises them all; the other slots are rolled.
func bot_loadout(index: int) -> int:
	return Loadout.encode(index % Loadout.PRIMARIES.size(), rng.randi_range(0, Loadout.SIDEARMS.size() - 1), rng.randi_range(0, Loadout.UTILITIES.size() - 1), rng.randi_range(0, Loadout.MELEES.size() - 1))

# Each bot id always gets the same random look, so a bot keeps its outfit across restarts and on every client.
func bot_look(id: int) -> int:
	var look_rng := RandomNumberGenerator.new()
	look_rng.seed = hash(id * 7919 + 17)
	return Appearance.random(look_rng)

func spawn_fighter(id: int, side: int, loadout_code: int, is_bot: bool, look_code: int = -1) -> Fighter:
	var p: Fighter = FIGHTER_SCENE.instantiate()
	p.configure(self, id, side, loadout_code, is_bot, look_code)
	p.bot_think = rng.randf_range(0.0, 0.5)
	add_child(p)
	p.spawn_slot = free_spawn_slot(side)
	p.global_position = spawn_position(p)
	p.yaw = -PI / 2 if side == 0 else PI / 2
	fighters[id] = p
	return p

func request_loadout(loadout_code: int, look_code: int) -> void:
	if authoritative:
		apply_look(local_id, look_code)
		apply_loadout(local_id, loadout_code)
	else:
		loadout_request.rpc_id(1, loadout_code, look_code)

@rpc("any_peer", "call_remote", "reliable")
func loadout_request(loadout_code: int, look_code: int) -> void:
	if authoritative:
		apply_look(multiplayer.get_remote_sender_id(), look_code)
		apply_loadout(multiplayer.get_remote_sender_id(), loadout_code)

# Looks are cosmetic, so they change anywhere (no return-to-spawn rule); snapshots carry them to everyone ("ap").
func apply_look(id: int, look_code: int) -> void:
	if fighters.has(id):
		fighters[id].set_look(look_code)

func apply_loadout(id: int, loadout_code: int) -> void:
	if not fighters.has(id):
		return
	var p: Fighter = fighters[id]
	if p.hp > 0 and absf(p.global_position.x) < 80:
		if id == local_id:
			announce("Loadout changes are available at spawn or while awaiting respawn.")
		else:
			remote_notice.rpc_id(id, "Return to spawn to change loadout.")
		return
	remove_owned(id)
	p.apply_loadout(loadout_code)
	p.dead_time = 0
	p.global_position = spawn_position(p)
	p.velocity = Vector3.ZERO

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		hud.toggle_help()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		Sfx.set_muted(not Sfx.muted)
		announce("Sound %s." % ("muted" if Sfx.muted else "on"))
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_F6, KEY_F7, KEY_F8, KEY_F9]:
		_toggle_cheat(event.keycode)
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
		var look := 0.0025 * DisplayPrefs.sensitivity
		p.yaw -= event.relative.x * look
		p.pitch = clampf(p.pitch - event.relative.y * look, -1.25, 1.2)
	for pair in [["jump", EDGE_JUMP], ["dash", EDGE_DASH], ["reload", EDGE_RELOAD], ["utility", EDGE_UTILITY], ["melee", EDGE_MELEE], ["swap", EDGE_SWAP]]:
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
			buttons = (1 if Input.is_action_pressed("fire") else 0) | (2 if Input.is_action_pressed("alt") else 0) | (8 if Input.is_action_pressed("slide") else 0) | (16 if Input.is_action_pressed("jump") else 0)
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
		refresh_bot_enemies()
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
				if player.heal_left > 0:
					var step := minf(player.heal_left, PACK_REGEN / PACK_REGEN_TIME * dt)
					player.heal_left -= step
					player.hp = minf(Fighter.MAX_HEALTH, player.hp + step)
					if player.hp >= Fighter.MAX_HEALTH:
						player.heal_left = 0
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
	p.held = buttons & HELD_BITS
	p.shoulder = 1.0 if shoulder_value >= 0 else -1.0
	request_times[id] = Time.get_ticks_msec()

@rpc("any_peer", "call_remote", "reliable", 1)
func submit_actions(pressed: int) -> void:
	if not authoritative:
		return
	var id := multiplayer.get_remote_sender_id()
	if fighters.has(id):
		fighters[id].edges |= pressed & EDGE_ALL

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
			spawn_fighter(state.id, state.team, state["lo"], state.bot, state.get("ap", -1))
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
		e.timer = state.get("t", 0.0)
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
	p.bot_path.clear()
	p.bot_bias.clear()
	p.bot_role_until = 0.0
	p.bot_pause_until = 0.0
	p.bot_roam_node = -1
	p.bot_item = -1
	p.bot_think = rng.randf_range(0.0, 0.5)
	p.apply_loadout(p.loadout)
	p.global_position = spawn_position(p)
	p.velocity = Vector3.ZERO
	p.idle_weapon = 2
	p.air_dash = true
	p.air_jump = true
	p.dash_cd = 0.0
	p.held = 0
	p.edges = 0

func _toggle_cheat(keycode: int) -> void:
	if not authoritative:
		announce("Test cheats are only available offline or as host.")
		return
	match keycode:
		KEY_F6:
			cheat_no_cooldowns = not cheat_no_cooldowns
			announce("Test: cooldowns %s." % ("disabled" if cheat_no_cooldowns else "normal"))
		KEY_F8:
			cheat_invulnerable = not cheat_invulnerable
			announce("Test: damage %s." % ("off" if cheat_invulnerable else "on"))
		KEY_F9:
			var p := local_player()
			if p != null and p.hp > 0:
				p.hp = Fighter.MAX_HEALTH
				announce("Test: full heal.")

func combat_tick(p: Fighter, dt: float) -> void:
	if p.fighter_id == local_id and cheat_no_cooldowns:
		p.utility_cd = 0.0
		p.melee_cd = 0.0
		p.dash_cd = 0.0
		p.air_dash = true
		p.slide_cd = 0.0
	p.utility_cd = maxf(0.0, p.utility_cd - dt)
	p.melee_cd = maxf(0.0, p.melee_cd - dt)
	p.swap_timer = maxf(0.0, p.swap_timer - dt)
	if p.power != 0:
		p.power_time = maxf(0.0, p.power_time - dt)
		if p.power_time <= 0.0:
			p.power = 0
		elif fmod(p.power_time, 1.0) < dt:
			show_ring(p.global_position + Vector3.UP * 0.9, 1.4, Items.POWER_COLORS[p.power])
	for attacker in p.damagers.keys():
		p.damagers[attacker] += dt
		if p.damagers[attacker] > ASSIST_WINDOW:
			p.damagers.erase(attacker)
	p.shot_timer = maxf(0, p.shot_timer - dt)
	p.conceal = maxf(0, p.conceal - dt)
	p.reveal = maxf(0, p.reveal - dt)
	if p.edges & EDGE_SWAP:
		p.swap_weapon()
		play_sfx(p.global_position, Sfx.Kind.SWAP)
	var w := p.weapon
	if p.edges & EDGE_RELOAD and p.ammo < w.magazine and p.reload_timer <= 0 and p.swap_timer <= 0:
		p.reload_timer = w.reload_time
	if p.reload_timer > 0:
		p.reload_timer -= dt
		if p.reload_timer <= 0:
			p.ammo = w.magazine
	if p.edges & EDGE_UTILITY:
		use_utility(p)
	if p.edges & EDGE_MELEE:
		use_melee(p)
	# The gun in hand fires once a swap has finished, no melee is recovering and no reload is running.
	var ready := p.swap_timer <= 0.0 and p.melee_cd <= 0.0 and p.reload_timer <= 0
	# Bursts finish their committed sequence even if fire is released.
	if p.burst_left > 0:
		p.burst_timer -= dt
		if p.burst_timer <= 0.00001 and p.ammo > 0 and ready:
			p.burst_left -= 1
			p.burst_timer += w.burst_gap
			p.ammo -= 1
			p.conceal = 0
			p.idle_weapon = 0
			fire_ray(p, w.damage)
	elif p.held & 1 and ready and p.shot_timer <= 0.00001:
		if p.ammo <= 0:
			p.reload_timer = w.reload_time
		else:
			p.conceal = 0
			p.ammo -= 1
			p.shot_timer = w.interval
			p.burst_left = w.burst - 1
			p.burst_timer = w.burst_gap
			fire_ray(p, w.damage)
	p.update_visual()

# Shot sound and tracer per gun, keyed by WeaponSpec.title.
const WEAPON_FX := {
	"Shotgun": [Sfx.Kind.SHOT_SHOTGUN, Vfx.Style.PELLET],
	"Rifle": [Sfx.Kind.SHOT_RIFLE, Vfx.Style.RIFLE],
	"SMG": [Sfx.Kind.SHOT_SMG, Vfx.Style.SMG],
	"Pistol": [Sfx.Kind.SHOT_PISTOL, Vfx.Style.PISTOL],
	"Burst Pistol": [Sfx.Kind.SHOT_BURST_PISTOL, Vfx.Style.PISTOL],
	"Revolver": [Sfx.Kind.SHOT_REVOLVER, Vfx.Style.REVOLVER],
}
const MAX_PELLET_TRACES := 4  # a shotgun blast draws a few tracers, not nine

# Random direction inside a cone of `deg` half-angle around `toward`.
func spread_direction(toward: Vector3, deg: float) -> Vector3:
	if deg <= 0.0:
		return toward
	var side := toward.cross(Vector3.UP)
	side = Vector3.RIGHT if side.length() < 0.001 else side.normalized()
	var up := side.cross(toward).normalized()
	var angle := rng.randf() * TAU
	var radius := tan(deg_to_rad(deg)) * sqrt(rng.randf())
	return (toward + (side * cos(angle) + up * sin(angle)) * radius).normalized()

func fire_ray(p: Fighter, amount: float) -> void:
	var w := p.weapon
	var fx: Array = WEAPON_FX.get(w.title, [Sfx.Kind.SHOT_PISTOL, Vfx.Style.LINE])
	play_sfx(p.global_position, fx[0])
	var from := p.muzzle()
	var toward := (p.aim_point() - from).normalized()
	var landed := {}  # enemy Fighter -> [damage, headshot], applied once per shot so a blast is one hit
	for i in range(w.pellets):
		var dir := toward if i == 0 and w.pellets > 1 else spread_direction(toward, w.spread_deg)
		var hit := ray(from, from + dir * w.reach, [p.get_rid()])
		var end: Vector3 = from + dir * w.reach if hit.is_empty() else hit.position
		if i < MAX_PELLET_TRACES:
			show_trace(from, end, team_color(p.team), fx[1], not hit.is_empty())
		if hit.is_empty():
			continue
		var dmg := amount * w.falloff_at(from.distance_to(hit.position))
		var object = hit.collider
		if object is Fighter and object.team != p.team:
			var headshot: bool = hit.position.y - object.global_position.y > 1.55 and w.headshot_mult > 1.0
			var entry: Array = landed.get(object, [0.0, false])
			landed[object] = [entry[0] + dmg * (w.headshot_mult if headshot else 1.0), entry[1] or headshot]
		elif object is Fighter or object is Deployable:
			apply_hit(p, hit, dmg)
		elif w.ricochet:
			var remaining := w.reach - from.distance_to(hit.position)
			var bounce := dir.bounce(hit.normal)
			var start: Vector3 = hit.position + hit.normal * 0.04
			var second := ray(start, start + bounce * remaining, [p.get_rid()])
			show_trace(start, start + bounce * remaining if second.is_empty() else second.position, Color("ffe0ab"), Vfx.Style.BOUNCE, not second.is_empty())
			if not second.is_empty():
				apply_hit(p, second, dmg)
	for target in landed:
		hit_fighter(p, target, landed[target][0], landed[target][1])

func hit_fighter(p: Fighter, target: Fighter, amount: float, headshot: bool, cause: String = "") -> void:
	damage_fighter(target, amount, p.fighter_id, Vector3.INF, cause)
	hit_feedback(p.fighter_id, 2 if target.hp <= 0 else (1 if headshot else 0))

func apply_hit(p: Fighter, hit: Dictionary, amount: float) -> void:
	var object = hit.collider
	if object is Fighter and object.team != p.team:
		var headshot: bool = hit.position.y - object.global_position.y > 1.55 and p.weapon.headshot_mult > 1.0
		hit_fighter(p, object, amount * (p.weapon.headshot_mult if headshot else 1.0), headshot)
	elif object is Deployable and object.team != p.team:
		object.hp -= amount
		object.last_damage = object.age
		hit_feedback(p.fighter_id)

# Returns true when the damage reached the target. `cause` names what dealt it in the kill feed (a utility or melee);
# empty means the attacker's gun in hand.
func damage_fighter(target: Fighter, amount: float, attacker: int, origin: Vector3 = Vector3.INF, cause: String = "") -> bool:
	if target.hp <= 0 or not authoritative:
		return false
	# Sheltered depot interiors prevent spawn farming; leaving the depot ends protection.
	if absf(target.global_position.x) > CivicDividend.depot_limit and attacker >= 0:
		return false
	if target.power == Items.POWER_INVULNERABLE and (attacker >= 0 or amount < 1000.0):
		return false  # invincible; only the out-of-bounds kill (attacker -1, 10000) goes through
	var source: Fighter = fighters.get(attacker)
	if source != null and source != target and source.power == Items.POWER_QUAD:
		amount *= Items.QUAD_MULTIPLIER
	if cheat_invulnerable and target.fighter_id == local_id:
		return false
	var soaked := minf(target.armor, amount)
	target.armor -= soaked
	target.hp = maxf(0, target.hp - (amount - soaked))
	target.reveal = 0.65
	if source != null and source != target and source.team != target.team:
		target.heal_left = 0
		target.damagers[attacker] = 0.0
	if source != null and not target.bot:
		var from_pos := source.global_position if origin == Vector3.INF else origin
		if target.fighter_id == local_id:
			hud.damaged(from_pos)
		else:
			damage_taken.rpc_id(target.fighter_id, from_pos)
	if target.hp <= 0:
		target.deaths += 1
		target.dead_time = 5.0
		target.velocity = Vector3.ZERO
		target.grapple_time = 0
		target.conceal = 0
		target.armor = 0.0
		target.power = 0
		target.power_time = 0.0
		remove_owned(target.fighter_id)
		target.update_visual()
		if source != null:
			source.kills += 1
			if source.power != 0 and source.team != target.team:
				source.power_kills += 1
				var streak := Items.streak_name(source.power_kills)
				if streak != "":
					notice_all("%s %s · %d kills on %s" % [HELIX_MONARCH[source.team], streak, source.power_kills, Items.POWER_NAMES[source.power]])
			if source.team != target.team:
				drop_armor(target.global_position, source.team)
			var killer_label := "%s · %s" % [source.callsign(), cause if cause != "" else source.weapon.title]
			kill_feed(killer_label, source.team, target.callsign(), target.team)
			if multiplayer.get_peers().size() > 0:
				kill_feed.rpc(killer_label, source.team, target.callsign(), target.team)
			var line: String = Loadout.QUIPS[rng.randi_range(0, Loadout.QUIPS.size() - 1)]
			if attacker == local_id:
				character_quip(line)
			elif not source.bot:
				character_quip.rpc_id(attacker, line)
		target.damagers.clear()
	return true

# Melee and close blasts: every visible enemy within `reach` whose direction is inside the `dot_limit` arc ahead.
# `backstab` multiplies damage on a target facing away (Loadout.BACKSTAB_DOT). Returns the number of fighters hit.
func cone_attack(p: Fighter, reach: float, amount: float, dot_limit: float, push: float, backstab: float = 1.0, cause: String = "") -> int:
	var hits := 0
	for target in fighters.values():
		var diff: Vector3 = target.global_position - p.global_position
		if target.team == p.team or target.hp <= 0 or diff.length() > reach or p.horizontal_direction().dot(diff.normalized()) < dot_limit:
			continue
		var sight := ray(p.muzzle(), target.global_position + Vector3.UP, [p.get_rid()])
		if sight.is_empty() or sight.collider != target:
			continue
		var flat := Vector3(diff.x, 0.0, diff.z)
		var behind: bool = flat.length() > 0.05 and target.horizontal_direction().dot(flat.normalized()) > Loadout.BACKSTAB_DOT
		hit_fighter(p, target, amount * (backstab if behind else 1.0), behind and backstab > 1.0, cause)
		target.velocity += diff.normalized() * push
		hits += 1
	return hits

# Q: the loadout's utility. A failed use (nothing to grapple, no ground to place on) costs no cooldown.
func use_utility(p: Fighter) -> void:
	if p.hp <= 0:
		return
	var kind := p.utility()
	if kind == Loadout.Utility.GRAPPLE and p.grapple_time > 0:
		p.grapple_time = 0
		p.hot_lap = 2
		return
	if p.utility_cd > 0:
		return
	var success := true
	match kind:
		Loadout.Utility.GRAPPLE:
			var hit := ray(p.muzzle(), p.muzzle() + p.direction() * 28, [p.get_rid()], 1 | 4)
			if hit.is_empty():
				success = false
			else:
				p.grapple = hit.position
				play_sfx(p.global_position, Sfx.Kind.GRAPPLE)
				p.grapple_time = 2.5
				p.hot_lap = 2
		Loadout.Utility.FRAG_GRENADE:
			p.conceal = 0
			throw_grenade(p)
		Loadout.Utility.SMOKE_GRENADE:
			create_entity(p, "smoke", p.global_position, 1, 3)
			show_ring(p.global_position, 2.5, Color("c7a8f1"))
			play_sfx(p.global_position, Sfx.Kind.SMOKE)
			p.conceal = 2.5
		Loadout.Utility.LAUNCH_PAD, Loadout.Utility.SENTRY_TURRET:
			var place := placement(p, 8.0)
			if place == Vector3.INF:
				success = false
			else:
				var entity_kind := "turret" if kind == Loadout.Utility.SENTRY_TURRET else "pad"
				for e in entities.values():
					if e.owner_id == p.fighter_id and e.kind == entity_kind:
						remove_entity(e.entity_id)
				create_entity(p, entity_kind, place, 100 if entity_kind == "turret" else 80, 90)
		Loadout.Utility.BARRICADE:
			var place := placement(p, 4)
			if place == Vector3.INF:
				success = false
			else:
				create_entity(p, "cover", place, 180, 8)
		Loadout.Utility.BREACH_CHARGE:
			breach_charge(p)
	if success:
		p.utility_cd = Loadout.UTILITIES[kind].cooldown
		if p.fighter_id == local_id:
			announce(Loadout.UTILITIES[kind].name)

# F: the loadout's melee. Recovery also holds the gun, and a swing cancels a burst in progress.
func use_melee(p: Fighter) -> void:
	if p.hp <= 0 or p.melee_cd > 0.0:
		return
	var m: Dictionary = Loadout.MELEES[p.melee()]
	p.melee_cd = m.recovery
	p.burst_left = 0
	p.conceal = 0
	p.idle_weapon = 0.0
	var hits := cone_attack(p, m.reach, m.damage, m.arc, m.push, m.backstab, m.name)
	show_trace(p.global_position + Vector3.UP * 1.1, p.global_position + Vector3.UP * 1.1 + p.horizontal_direction() * m.reach, Color("ffd9a0"), Vfx.Style.SWOOSH)
	play_sfx(p.global_position, Sfx.Kind.MELEE)
	if hits > 0 and p.melee() == Loadout.Melee.SWORD:
		p.ammo = p.weapon.magazine
		p.reload_timer = 0.0

# Breach Charge: a close blast that launches enemies and wrecks deployables.
func breach_charge(p: Fighter) -> void:
	var forward := p.horizontal_direction()
	for target in fighters.values():
		var diff: Vector3 = target.global_position - p.global_position
		if target.team == p.team or target.hp <= 0 or diff.length() > 5.0 or forward.dot(diff.normalized()) < 0.5:
			continue
		var sight := ray(p.muzzle(), target.global_position + Vector3.UP, [p.get_rid()])
		if sight.is_empty() or sight.collider != target:
			continue
		hit_fighter(p, target, 20.0, false, "Breach Charge")
		target.velocity += diff.normalized() * 14.0 + Vector3.UP * 4.0
	for e in entities.values():
		var diff: Vector3 = e.global_position - p.global_position
		if e.team != p.team and e.kind in ["cover", "turret", "pad"] and diff.length() <= 5.0 and forward.dot(diff.normalized()) >= 0.5:
			e.hp -= 60.0
			e.last_damage = e.age
	show_ring(p.global_position + forward * 1.5, 3.0, Color("ff7a3a"))
	show_trace(p.global_position + Vector3.UP * 0.4, p.global_position + Vector3.UP * 0.4 + forward * 5.0, Color("ffd9a0"), Vfx.Style.SWOOSH)
	play_sfx(p.global_position, Sfx.Kind.BREACH)

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
	query.exclude = exclusions
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

# A kill drops light armor for the killer's team. A team that is behind on points gets a bigger drop.
func drop_armor(pos: Vector3, team: int) -> void:
	var behind := match_state.owners.count(1 - team) - match_state.owners.count(team)
	var amount := ARMOR_DROP + ARMOR_DROP_BEHIND * clampf(behind, 0.0, 2.0)
	var data := {"id": entity_next, "owner": -1, "team": team, "kind": "armor", "hp": amount, "life": ARMOR_DROP_LIFE, "pos": pos, "yaw": 0.0, "used": false}
	entity_next += 1
	create_entity_from(data)  # clients receive it in the next snapshot's entity list

# Health packs belong to nobody (owner -1) so class swaps and deaths never clear them.
func spawn_pickups() -> void:
	for f in CivicDividend.pickups:
		var at: Array = f.pos
		var is_power: bool = f.get("kind", "health") == "power"
		var data := {"id": entity_next, "owner": -1, "team": 0, "kind": Items.entity_kind(f.get("kind", "health")), "hp": 1.0, "life": 1e9, "pos": Vector3(at[0], at[1], at[2]), "yaw": 0.0, "used": is_power}
		entity_next += 1
		create_entity_from(data)
		if is_power:
			entities[data.id].hp = float(Items.POWER_QUAD)
			entities[data.id].timer = Items.POWER_FIRST_SPAWN

func remove_entity(id: int) -> void:
	if entities.has(id):
		var e: Deployable = entities[id]
		e.collision_layer = 0
		e.queue_free()
		entities.erase(id)

func remove_owned(id: int) -> void:
	for e in entities.values():
		if e.owner_id == id:
			remove_entity(e.entity_id)

func entities_tick(dt: float) -> void:
	var tick_cues := {}  # map-wide cues this tick, deduped so two power-ups in step play each cue once
	for e in entities.values():
		e.age += dt
		var timer_before: float = e.timer
		e.timer = maxf(0, e.timer - dt)
		if e.kind == "power" and e.used:
			var cue := Items.power_cue(timer_before, e.timer)
			if cue >= 0:
				tick_cues[cue] = true
		if e.age >= e.lifetime or e.hp <= 0:
			remove_entity(e.entity_id)
			continue
		var owner: Fighter = fighters.get(e.owner_id)
		if e.kind in ["turret", "pad"] and owner != null and owner.hp > 0 and owner.global_position.distance_to(e.global_position) < 12 and e.age - e.last_damage > 4:
			e.hp = minf(e.max_hp, e.hp + 8 * dt)
		if e.kind == "healpack":
			if e.used and e.timer <= 0:
				e.used = false
				e.update_visual()
			elif not e.used:
				for p in fighters.values():
					if p.hp > 0 and p.hp < Fighter.MAX_HEALTH and p.global_position.distance_to(e.global_position) < PACK_RADIUS:
						p.hp = minf(Fighter.MAX_HEALTH, p.hp + PACK_HEAL)
						p.heal_left = PACK_REGEN
						e.used = true
						e.timer = PACK_RESPAWN
						e.update_visual()
						show_ring(e.global_position, PACK_RADIUS, Color("3dff7a"))
						play_sfx(e.global_position, Sfx.Kind.PAD)
						break
		elif Items.KINDS.has(e.kind):
			if e.used and e.timer <= 0:
				e.used = false
				if e.kind == "power":
					tick_cues[Sfx.Kind.ITEM_POWER] = true
					e.hp = float(rng.randi_range(Items.POWER_INVULNERABLE, Items.POWER_QUAD))
					notice_all("%s power-up is up." % Items.POWER_NAMES[int(e.hp)].capitalize())
				e.update_visual()
			elif not e.used:
				for p in fighters.values():
					if p.hp > 0 and Items.can_use(e.kind, p.hp, Fighter.MAX_HEALTH, p.armor) and (e.kind != "power" or p.power == 0) and p.global_position.distance_to(e.global_position) < Items.RADIUS:
						Items.apply(e.kind, p)
						if e.kind == "power":
							p.power = int(e.hp)
							p.power_time = Items.POWER_DURATION
							p.power_pickups += 1
							p.power_kills = 0
							notice_all("%s took %s." % [HELIX_MONARCH[p.team], Items.POWER_NAMES[p.power]])
						e.used = true
						e.timer = Items.KINDS[e.kind].respawn
						e.update_visual()
						show_ring(e.global_position, Items.RADIUS, Items.KINDS[e.kind].color)
						if e.kind == "power":
							global_cue(Items.POWER_TAKEN_CUES[p.power])
						else:
							play_sfx(e.global_position, Items.KINDS[e.kind].sound)
						break
		elif e.kind == "armor":
			for p in fighters.values():
				if p.hp > 0 and p.team == e.team and p.armor < Fighter.ARMOR_MAX and p.global_position.distance_to(e.global_position) < PACK_RADIUS:
					p.armor = minf(Fighter.ARMOR_MAX, p.armor + e.hp)
					show_ring(e.global_position, PACK_RADIUS, Color("5ab8ff"))
					play_sfx(e.global_position, Sfx.Kind.PAD)
					remove_entity(e.entity_id)
					break
		elif e.kind == "pad" and e.timer <= 0:
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
					damage_fighter(target, 6, e.owner_id, from, "Sentry Turret")
					e.timer = 0.3
					show_trace(from, hit.position, team_color(e.team), Vfx.Style.PISTOL, true)
					play_sfx(from, Sfx.Kind.TURRET)
					break
		e.update_visual()
	for cue in tick_cues:
		global_cue(cue)

func throw_grenade(p: Fighter) -> void:
	var grenade := preload("res://scripts/grenade.gd").new()
	grenade.configure(self, p)
	add_child(grenade)
	grenade.global_position = p.muzzle()

func objectives_tick(dt: float) -> void:
	var occupancy: Array = []
	for i in range(points.size()):
		var point := points[i]
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

# Bots on one team split into attackers (capture the frontier point), roamers (flank and intercept around it) and
# defenders (patrol a point the team already owns). Capture speed stops growing at three capturers (acquisition.gd), so
# surplus bots stay mobile instead of standing on the point.
func refresh_bot_enemies() -> void:
	bot_enemies = [[], []]
	for f in fighters.values():
		if f.hp > 0 and not (f.conceal > 0 and f.reveal <= 0):
			bot_enemies[f.team].append(f)

func frontier_point(p: Fighter) -> int:
	var objective := 2
	var closest := INF
	for i in range(5):
		if match_state.unlocked[i] and match_state.owners[i] != p.team:
			var distance := p.global_position.distance_to(points[i])
			if distance < closest:
				closest = distance
				objective = i
	return objective

func assign_bot_role(p: Fighter, objective: int) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	p.bot_role_until = now + rng.randf_range(BOT_ROLE_MIN, BOT_ROLE_MAX)
	p.bot_pause_until = 0.0
	var attackers := 0
	for other in fighters.values():
		if other != p and other.bot and other.team == p.team and other.hp > 0 and other.bot_role == Fighter.BotRole.ATTACK and other.bot_goal == objective:
			attackers += 1
	var role := Fighter.BotRole.ATTACK
	if attackers >= BOT_MAX_ATTACKERS or rng.randf() < BOT_ROAM_CHANCE:
		role = Fighter.BotRole.DEFEND if rng.randf() < BOT_DEFEND_SHARE else Fighter.BotRole.ROAM
	p.bot_role = role
	p.bot_roam_node = -1
	if role == Fighter.BotRole.ATTACK:
		roll_bot_offset(p)

func roll_bot_offset(p: Fighter) -> void:
	var angle := rng.randf() * TAU
	var radius := rng.randf_range(0.8, BOT_POINT_RING)
	p.bot_offset = Vector3(cos(angle), 0, sin(angle)) * radius

# Random graph node within a ring around a point; the bot walks there, lingers briefly, then picks another.
func pick_roam_node(p: Fighter, center: Vector3, min_range: float, max_range: float) -> int:
	var candidates: Array[int] = []
	for i in range(bot_graph.positions.size()):
		if CivicDividend.spawn_nodes.has(bot_graph.names[i]):
			continue
		var d := Vector2(bot_graph.positions[i].x - center.x, bot_graph.positions[i].z - center.z).length()
		if d >= min_range and d <= max_range:
			candidates.append(i)
	if candidates.is_empty():
		return -1
	return candidates[rng.randi() % candidates.size()]

func choose_bot_roam(p: Fighter, objective: int) -> void:
	var center := points[objective]
	var min_range := 8.0
	var max_range := BOT_ROAM_RADIUS
	if p.bot_role == Fighter.BotRole.DEFEND:
		var owned := -1
		var closest := INF
		for i in range(5):
			if match_state.unlocked[i] and match_state.owners[i] == p.team:
				var distance := p.global_position.distance_to(points[i])
				if distance < closest:
					closest = distance
					owned = i
		if owned >= 0:
			center = points[owned]
			min_range = 0.0
			max_range = BOT_DEFEND_RADIUS
	var node := pick_roam_node(p, center, min_range, max_range)
	if node < 0:
		# Nothing suitable near the point: attack instead of idling.
		p.bot_role = Fighter.BotRole.ATTACK
		roll_bot_offset(p)
		return
	p.bot_roam_node = node
	p.bot_target = bot_graph.positions[node]
	plan_bot_path(p, objective, node)

# Drops a detour that is finished, pointless or stuck, and hands the bot back to its role.
func update_bot_item(p: Fighter, now: float) -> void:
	if p.bot_item < 0:
		return
	var e: Deployable = entities.get(p.bot_item)
	if e != null and not e.used and now < p.bot_item_until and Items.can_use(e.kind, p.hp, Fighter.MAX_HEALTH, p.armor):
		return
	p.bot_item = -1
	p.bot_path.clear()
	p.bot_roam_node = -1
	p.bot_goal_node = -1

# Picks the best ready armor or bubble within reach that this bot can use, and routes to it.
func choose_bot_item(p: Fighter, objective: int, now: float) -> bool:
	if p.bot_role == Fighter.BotRole.ATTACK and p.global_position.distance_to(points[objective]) < 6.0:
		return false  # capturing: stay on the point
	var best: Deployable = null
	var best_score := 0.0
	var best_route := 0.0
	for e in entities.values():
		if not Items.KINDS.has(e.kind) or e.used:
			continue
		if e.kind != "power" and absf(e.global_position.y - p.global_position.y) > 3.0:
			continue
		if not Items.can_use(e.kind, p.hp, Fighter.MAX_HEALTH, p.armor):
			continue
		# Bubbles are only worth a detour once hurt; armor once it is meaningfully missing.
		if e.kind == "power" and p.power != 0:
			continue
		if e.kind == "bubble" and p.hp > Fighter.MAX_HEALTH * 0.75:
			continue
		if e.kind == "armor1" and p.armor >= 50.0 or e.kind == "armor2" and p.armor >= 60.0:
			continue
		var distance := Vector2(e.global_position.x - p.global_position.x, e.global_position.z - p.global_position.z).length()
		if e.kind == "power":
			# Possibly up a tower: judge it by the graph route (ladders and jumps included), not by straight-line height.
			if distance > BOT_POWER_RANGE:
				continue
			var route := bot_graph.path(bot_graph.nearest(p.global_position), bot_graph.nearest(e.global_position), {})
			if route.is_empty() or Vector2(route[-1].x - e.global_position.x, route[-1].z - e.global_position.z).length() > 4.0:
				continue
			distance = 0.0
			for i in range(route.size() - 1):
				distance += route[i].distance_to(route[i + 1])
			if distance > BOT_POWER_PATH:
				continue
		elif distance > BOT_ITEM_RANGE:
			continue
		var score: float = BOT_ITEM_VALUE[e.kind] / (distance + 10.0)
		if score > best_score:
			best_score = score
			best = e
	if best == null:
		return false
	p.bot_item = best.entity_id
	p.bot_item_until = now + (BOT_POWER_TIME if best.kind == "power" else BOT_ITEM_TIME)
	p.bot_target = best.global_position
	plan_bot_path(p, objective, bot_graph.nearest(best.global_position))
	return true

func bot_input(p: Fighter, dt: float) -> void:
	if p.hp <= 0:
		return
	p.bot_think -= dt
	if p.bot_think <= 0:
		p.bot_think = rng.randf_range(0.25, 0.5)
		var now := Time.get_ticks_msec() / 1000.0
		var objective := frontier_point(p)
		update_bot_item(p, now)
		if p.bot_item < 0:
			if now >= p.bot_role_until or objective != p.bot_goal and p.bot_role == Fighter.BotRole.ATTACK:
				assign_bot_role(p, objective)
			if p.bot_role == Fighter.BotRole.ATTACK:
				if p.bot_goal == objective and p.global_position.distance_to(points[objective]) < 6.0 and rng.randf() < 0.15:
					roll_bot_offset(p)
				p.bot_target = points[objective] + p.bot_offset
				if objective != p.bot_goal or p.bot_path.is_empty() or p.bot_goal_node >= 0:
					plan_bot_path(p, objective)
			else:
				var arrived := p.bot_roam_node >= 0 and Vector2(p.bot_target.x - p.global_position.x, p.bot_target.z - p.global_position.z).length() < 3.0
				if arrived and p.bot_pause_until <= 0.0:
					p.bot_pause_until = now + rng.randf_range(BOT_PAUSE_MIN, BOT_PAUSE_MAX)
				if p.bot_roam_node < 0 or p.bot_pause_until > 0.0 and now >= p.bot_pause_until:
					p.bot_pause_until = 0.0
					choose_bot_roam(p, objective)
				p.bot_goal = objective
		if p.bot_item < 0 and p.aim_target < 0:
			choose_bot_item(p, objective, now)
		p.aim_target = -1
		var candidates: Array = []
		for target in bot_enemies[1 - p.team]:
			var distance_sq := p.global_position.distance_squared_to(target.global_position)
			if distance_sq < BOT_SIGHT * BOT_SIGHT:
				candidates.append([distance_sq, target])
		candidates.sort_custom(func(a, b): return a[0] < b[0])
		for i in range(mini(candidates.size(), 2)):
			var target: Fighter = candidates[i][1]
			var hit := ray(p.muzzle(), target.global_position + Vector3.UP, [p.get_rid()])
			if not hit.is_empty() and hit.collider == target:
				p.aim_target = target.fighter_id
				break
	var destination := bot_waypoint(p, dt)
	var target: Fighter = fighters.get(p.aim_target)
	var diff := destination - p.global_position
	var aim := diff.normalized()
	p.held = 0
	if target != null and target.hp > 0:
		var target_diff := target.global_position + Vector3.UP * 1.1 - p.muzzle()
		aim = target_diff.normalized()
		var gap := target_diff.length()
		if gap <= p.weapon.reach:
			p.held = 1
		bot_kit(p, gap, dt)
	elif p.slot == 1 and p.swap_timer <= 0.0 and rng.randf() < dt * 2.0:
		p.edges |= EDGE_SWAP  # nobody in sight: back to the primary
	# Graph link tags that need more than walking: climb a ladder ("lad", head up it facing the wall) or jump a gap ("jmp").
	var link := ""
	if p.bot_path_i > 0 and p.bot_path_i < p.bot_path.size():
		link = bot_graph.link_tag(p.bot_path[p.bot_path_i - 1], p.bot_path[p.bot_path_i])
	var climbing_up: bool = link == "lad" and destination.y - p.global_position.y > 2.0
	if climbing_up:
		aim = Vector3(diff.x, 0.0, diff.z).normalized()
	if aim.length() > 0.01:
		p.yaw = lerp_angle(p.yaw, atan2(-aim.x, -aim.z), minf(1, dt * 9))
		p.pitch = lerpf(p.pitch, asin(clampf(aim.y, -1, 1)), minf(1, dt * 9))
	var local_move := Basis(Vector3.UP, -p.yaw) * diff.normalized()
	var stopping_distance := 2.0 if p.bot_path_i >= p.bot_path.size() - 1 else 0.4
	p.movement = Vector2(local_move.x, local_move.z) if diff.length() > stopping_distance else Vector2.ZERO
	if p.bot_pause_until > 0.0 and target == null:
		p.movement = Vector2.ZERO
	if climbing_up:
		p.movement = Vector2(0.0, -1.0)  # straight forward into the ladder; the climb volume carries the bot up
		p.held = 0
		if p.is_on_floor() and not p.climbing and p.get_real_velocity().length() < 1:
			p.edges |= 1  # stalled on a lip before the ladder (the booth's launch pad): hop it
	elif link == "jmp" and p.is_on_floor() and Vector2(diff.x, diff.z).length() <= BOT_JUMP_DISTANCE:
		p.edges |= 1
	elif (p.is_on_wall() or p.is_on_floor() and p.get_real_velocity().length() < 1 and p.movement.length() > 0.1) and not p.climbing:
		p.edges |= 1
	var kind := p.utility()
	if (kind == Loadout.Utility.SENTRY_TURRET or kind == Loadout.Utility.LAUNCH_PAD) and p.utility_cd <= 0.0 and absf(p.global_position.x) < 75 and rng.randf() < dt * 0.25:
		p.edges |= EDGE_UTILITY

# A bot in a fight: swap to the sidearm instead of reloading up close, melee at arm's length, and use its utility
# when the moment suits it (the Grapple is left alone; bots would only fling themselves off the route).
func bot_kit(p: Fighter, gap: float, dt: float) -> void:
	if p.slot == 0 and p.ammo <= 0 and p.stowed_ammo > 0 and gap < BOT_SIDEARM_RANGE and p.swap_timer <= 0.0:
		p.edges |= EDGE_SWAP
	elif p.slot == 1 and p.ammo <= 0 and p.swap_timer <= 0.0:
		p.edges |= EDGE_SWAP
	var m: Dictionary = Loadout.MELEES[p.melee()]
	if gap < m.reach * 0.9 and p.melee_cd <= 0.0 and rng.randf() < dt * 3.0:
		p.edges |= EDGE_MELEE
	if p.utility_cd > 0.0:
		return
	var want := false
	match p.utility():
		Loadout.Utility.FRAG_GRENADE:
			want = gap > 8.0 and gap < 25.0 and rng.randf() < dt * 0.5
		Loadout.Utility.SMOKE_GRENADE:
			want = p.hp < Fighter.MAX_HEALTH * 0.4 and rng.randf() < dt
		Loadout.Utility.BREACH_CHARGE:
			want = gap < 4.5 and rng.randf() < dt * 1.5
		Loadout.Utility.BARRICADE:
			want = gap > 12.0 and not p.damagers.is_empty() and rng.randf() < dt * 0.3
	if want:
		p.edges |= EDGE_UTILITY

# Each bot commits to a route family (class-weighted odds) so a squad spreads over the flanks;
# the chosen family is cheap to path through, the others expensive but still usable as connectors.
func bot_weights(p: Fighter) -> Dictionary:
	if p.bot_bias.is_empty():
		var odds := {"blv": 0.25, "roof": 0.25, "trn": 0.25, "aln": 0.25}
		match Loadout.decode(p.loadout)[0]:
			0:  # Shotgun: close quarters
				odds = {"blv": 0.2, "roof": 0.1, "trn": 0.4, "aln": 0.3}
			1:  # Rifle: long sightlines
				odds = {"blv": 0.25, "roof": 0.45, "trn": 0.1, "aln": 0.2}
			2:  # SMG
				odds = {"blv": 0.4, "roof": 0.15, "trn": 0.25, "aln": 0.2}
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

# `goal_node` >= 0 routes to that graph node (roaming); otherwise to the objective's own node.
func plan_bot_path(p: Fighter, objective: int, goal_node: int = -1) -> void:
	p.bot_goal = objective
	p.bot_goal_node = goal_node
	var destination := goal_node if goal_node >= 0 else bot_graph.node(CivicDividend.goal_names[objective])
	p.bot_path = bot_graph.path(bot_graph.nearest(p.global_position), destination, bot_weights(p))
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
	if p.climbing:
		p.bot_progress_pos = p.global_position
		p.bot_progress_time = 0.0
	if p.bot_progress_time > 2.0:
		var moved := Vector2(p.global_position.x - p.bot_progress_pos.x, p.global_position.z - p.bot_progress_pos.z).length()
		if moved < 0.8 and p.bot_path_i < p.bot_path.size() - 1:
			p.bot_bias.clear()
			plan_bot_path(p, p.bot_goal, p.bot_goal_node)
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

# A map-wide, non-positional cue everyone hears (the power-up's countdown).
func global_cue(kind: int) -> void:
	Sfx.play_ui(self, kind)
	if authoritative and multiplayer.get_peers().size() > 0:
		cue_remote.rpc(kind)

@rpc("authority", "call_remote", "unreliable")
func cue_remote(kind: int) -> void:
	if kind >= 0 and kind < Sfx.Kind.size():
		Sfx.play_ui(self, kind)

const HELIX_MONARCH := ["HELIX", "MONARCH"]

# A notice every player sees: shown here and sent to connected clients.
func notice_all(message: String) -> void:
	announce(message)
	if multiplayer.get_peers().size() > 0:
		remote_notice.rpc(message)

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
	# Aiming down sights with a ricochet gun previews the bounce; local presentation only, it never deals damage.
	if p.weapon.ricochet and p.held & 2 and p.hp > 0 and simulation_tick % 4 == 0:
		var start := p.muzzle()
		var direction := (p.aim_point() - start).normalized()
		var hit := ray(start, start + direction * p.weapon.reach, [p.get_rid()])
		trace_visual(start, start + direction * p.weapon.reach if hit.is_empty() else hit.position, Color("bc9ee8"))
		if not hit.is_empty() and not hit.collider is Fighter and not hit.collider is Deployable:
			var next: Vector3 = hit.position + hit.normal * 0.05
			var end: Vector3 = next + direction.bounce(hit.normal) * (p.weapon.reach - start.distance_to(hit.position))
			var second := ray(next, end, [p.get_rid()])
			trace_visual(next, end if second.is_empty() else second.position, Color("e1c7ff"))
