class_name Sfx
extends RefCounted

# Procedural sound effects: each cue is synthesised once from oscillators and noise, cached as an
# AudioStreamWAV, and played through small fixed pools. Silent in headless runs.

enum Kind { SHOT_PISTOL, SHOT_BURST_PISTOL, SHOT_REVOLVER, SHOT_SHOTGUN, SHOT_RIFLE, SHOT_SMG, IMPACT, STEP, SWAP, BREACH, MELEE, PAD, SMOKE, EXPLODE, TURRET, GRAPPLE, DASH, JUMP, HIT, HEADSHOT, KILL, CAPTURE, PLACE, ITEM_BUBBLE, ITEM_ARMOR1, ITEM_ARMOR2, ITEM_POWER, POWER_WARN, POWER_TICK, POWER_TAKEN_INVULNERABLE, POWER_TAKEN_QUAD, SHOT_ROCKET, SHOT_LAUNCHER, SHOT_PLASMA, SHOT_LIGHTNING, SHOT_RAIL, SHOT_DOUBLE, SHOT_NAIL, SHOT_DISC }

const MIX_RATE := 22050
const POOL_3D := 16
const POOL_UI := 4

# length (s), start Hz, end Hz, wave, noise mix 0..1, decay, volume
const RECIPES := {
	Kind.SHOT_ROCKET: [0.25, 100, 40, "saw", 0.65, 10, 0.8],
	Kind.SHOT_LAUNCHER: [0.18, 160, 60, "sine", 0.55, 14, 0.7],
	Kind.SHOT_PLASMA: [0.06, 1600, 800, "square", 0.05, 28, 0.3],
	Kind.SHOT_LIGHTNING: [0.055, 2200, 1800, "buzz", 0.2, 25, 0.25],
	Kind.SHOT_RAIL: [0.35, 2200, 180, "saw", 0.2, 9, 0.75],
	Kind.SHOT_DOUBLE: [0.3, 110, 35, "saw", 0.85, 10, 0.95],
	Kind.SHOT_NAIL: [0.09, 1200, 500, "square", 0.35, 25, 0.35],
	Kind.SHOT_DISC: [0.22, 500, 1700, "sine", 0.1, 12, 0.45],
	Kind.SHOT_PISTOL: [0.10, 1400.0, 380.0, "saw", 0.4, 20.0, 0.5],
	Kind.SHOT_BURST_PISTOL: [0.12, 1800.0, 400.0, "saw", 0.45, 18.0, 0.55],
	Kind.SHOT_REVOLVER: [0.20, 700.0, 250.0, "sine", 0.2, 12.0, 0.55],
	Kind.SHOT_SHOTGUN: [0.22, 140.0, 45.0, "saw", 0.8, 11.0, 0.95],
	Kind.SHOT_RIFLE: [0.26, 1100.0, 120.0, "saw", 0.35, 10.0, 0.8],
	Kind.SHOT_SMG: [0.06, 900.0, 500.0, "square", 0.4, 30.0, 0.4],
	Kind.IMPACT: [0.08, 0.0, 0.0, "sine", 1.0, 40.0, 0.35],
	Kind.STEP: [0.07, 60.0, 50.0, "sine", 0.5, 30.0, 0.3],
	Kind.SWAP: [0.08, 600.0, 900.0, "square", 0.3, 30.0, 0.3],
	Kind.BREACH: [0.35, 80.0, 40.0, "sine", 0.5, 8.0, 0.8],
	Kind.MELEE: [0.30, 100.0, 40.0, "sine", 0.4, 9.0, 0.8],
	Kind.PAD: [0.25, 400.0, 1000.0, "square", 0.0, 10.0, 0.4],
	Kind.SMOKE: [0.40, 0.0, 0.0, "sine", 1.0, 6.0, 0.4],
	Kind.EXPLODE: [0.50, 70.0, 35.0, "sine", 0.75, 6.0, 0.9],
	Kind.TURRET: [0.09, 500.0, 420.0, "square", 0.1, 25.0, 0.35],
	Kind.GRAPPLE: [0.20, 1200.0, 300.0, "saw", 0.1, 9.0, 0.45],
	Kind.DASH: [0.25, 250.0, 900.0, "sine", 0.7, 9.0, 0.45],
	Kind.JUMP: [0.12, 300.0, 520.0, "sine", 0.1, 16.0, 0.35],
	Kind.HIT: [0.05, 1800.0, 1800.0, "sine", 0.0, 50.0, 0.5],
	Kind.HEADSHOT: [0.08, 2600.0, 2600.0, "sine", 0.0, 35.0, 0.55],
	Kind.KILL: [0.28, 800.0, 1600.0, "square", 0.0, 9.0, 0.45],
	Kind.CAPTURE: [0.5, 440.0, 880.0, "sine", 0.0, 5.0, 0.5],
	Kind.PLACE: [0.15, 250.0, 350.0, "square", 0.1, 14.0, 0.4],
	Kind.ITEM_BUBBLE: [0.1, 900.0, 1300.0, "sine", 0.0, 20.0, 0.4],
	Kind.ITEM_ARMOR1: [0.2, 500.0, 760.0, "square", 0.0, 12.0, 0.4],
	Kind.POWER_TAKEN_INVULNERABLE: [0.9, 500.0, 2000.0, "sine", 0.15, 3.0, 0.55],
	Kind.POWER_TAKEN_QUAD: [0.7, 700.0, 90.0, "square", 0.0, 6.0, 0.55],
	Kind.POWER_WARN: [0.6, 300.0, 1100.0, "square", 0.05, 4.0, 0.5],
	Kind.POWER_TICK: [0.08, 1500.0, 1500.0, "square", 0.0, 40.0, 0.45],
	Kind.ITEM_POWER: [0.7, 200.0, 1400.0, "square", 0.1, 5.0, 0.55],
	Kind.ITEM_ARMOR2: [0.4, 300.0, 900.0, "square", 0.05, 7.0, 0.5],
}

static var muted := false
static var _streams: Dictionary = {}
static var _pool_3d: Array = []
static var _pool_ui: Array = []

static func available() -> bool:
	return DisplayServer.get_name() != "headless"

static func stream(kind: int) -> AudioStreamWAV:
	if _streams.has(kind):
		return _streams[kind]
	var r: Array = RECIPES[kind]
	var count := int(MIX_RATE * float(r[0]))
	var bytes := PackedByteArray()
	bytes.resize(count * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + kind
	var phase := 0.0
	var low := 0.0
	for i in range(count):
		var t := float(i) / MIX_RATE
		var progress := float(i) / count
		var freq := lerpf(float(r[1]), float(r[2]), progress)
		phase += TAU * freq / MIX_RATE
		var tone := 0.0
		match r[3]:
			"saw":
				tone = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
			"square":
				tone = 1.0 if fposmod(phase / TAU, 1.0) < 0.5 else -1.0
			"buzz":
				tone = (1.0 if fposmod(phase / TAU, 1.0) < 0.5 else -1.0) * (0.6 + 0.4 * sin(t * TAU * 60.0))
			_:
				tone = sin(phase)
		# Low-passed noise reads as a thump; plain noise as a crack.
		var noise := rng.randf_range(-1.0, 1.0)
		low = lerpf(low, noise, 0.25 if freq < 300.0 else 1.0)
		var env := exp(-float(r[5]) * t) * minf(1.0, t * 400.0)
		var sample := (tone * (1.0 - float(r[4])) + low * float(r[4])) * env * float(r[6])
		bytes.encode_s16(i * 2, int(clampf(sample, -1.0, 1.0) * 28000.0))
	var wave := AudioStreamWAV.new()
	wave.format = AudioStreamWAV.FORMAT_16_BITS
	wave.mix_rate = MIX_RATE
	wave.data = bytes
	_streams[kind] = wave
	return wave

static func _free_player(pool: Array) -> Node:
	for player in pool:
		if is_instance_valid(player) and not player.playing:
			return player
	return null

static func set_muted(value: bool) -> void:
	muted = value
	if muted:
		for player in _pool_3d + _pool_ui:
			if is_instance_valid(player):
				player.stop()

static func _acquire(pool: Array, host: Node, make: Callable, limit: int, priority: bool) -> Node:
	# Players belong to one host; a new host (new match scene) starts a fresh pool.
	if not pool.is_empty() and (not is_instance_valid(pool[0]) or pool[0].get_parent() != host):
		pool.clear()
	for player in pool:
		if not player.playing:
			return player
	if pool.size() < limit:
		var created: Node = make.call()
		host.add_child(created)
		pool.append(created)
		return created
	# Pool exhausted: only high-value cues (hit, kill, capture) may steal a busy player.
	if priority:
		var stolen: Node = pool[0]
		pool.remove_at(0)
		pool.append(stolen)
		stolen.stop()
		return stolen
	return null

# Positional cue. `host` owns the pooled players.
static func play_at(host: Node3D, pos: Vector3, kind: int) -> void:
	if muted or not available():
		return
	var player: AudioStreamPlayer3D = _acquire(_pool_3d, host, func():
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 45.0
		p.unit_size = 8.0
		return p, POOL_3D, kind >= Kind.HIT)
	if player == null:
		return
	player.stream = stream(kind)
	player.global_position = pos
	player.pitch_scale = randf_range(0.96, 1.04)
	player.play()

# Non-positional cue for the local player (hit markers, captures).
static func play_ui(host: Node, kind: int) -> void:
	if muted or not available():
		return
	var player: AudioStreamPlayer = _acquire(_pool_ui, host, func(): return AudioStreamPlayer.new(), POOL_UI, true)
	if player == null:
		return
	player.stream = stream(kind)
	player.pitch_scale = 1.0
	player.play()
