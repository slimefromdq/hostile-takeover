class_name Sfx
extends RefCounted

# Procedural sound effects: each cue is synthesised once from oscillators and noise, cached as an
# AudioStreamWAV, and played through small fixed pools. Silent in headless runs.

enum Kind { SHOT_SKYRUNNER, SHOT_ENGINEER, SHOT_ENFORCER, SHOT_MIRAGE, SHOT_CHARGED, IMPACT, STEP, SWAP, KICKOFF, BRAKE, BREACH, EVICT, PAD, SMOKE, EXPLODE, TURRET, GRAPPLE, DASH, JUMP, HIT, HEADSHOT, KILL, CAPTURE, PLACE }

const MIX_RATE := 22050
const POOL_3D := 16
const POOL_UI := 4

# length (s), start Hz, end Hz, wave, noise mix 0..1, decay, volume
const RECIPES := {
	Kind.SHOT_SKYRUNNER: [0.12, 1800.0, 400.0, "saw", 0.45, 18.0, 0.55],
	Kind.SHOT_ENGINEER: [0.14, 130.0, 110.0, "buzz", 0.3, 12.0, 0.5],
	Kind.SHOT_ENFORCER: [0.10, 95.0, 60.0, "sine", 0.65, 14.0, 0.9],
	Kind.SHOT_MIRAGE: [0.20, 700.0, 250.0, "sine", 0.2, 12.0, 0.55],
	Kind.SHOT_CHARGED: [0.30, 2400.0, 200.0, "saw", 0.4, 8.0, 0.7],
	Kind.IMPACT: [0.08, 0.0, 0.0, "sine", 1.0, 40.0, 0.35],
	Kind.STEP: [0.07, 60.0, 50.0, "sine", 0.5, 30.0, 0.3],
	Kind.SWAP: [0.25, 300.0, 900.0, "sine", 0.0, 9.0, 0.5],
	Kind.KICKOFF: [0.30, 200.0, 700.0, "saw", 0.3, 7.0, 0.5],
	Kind.BRAKE: [0.25, 500.0, 200.0, "sine", 0.8, 8.0, 0.4],
	Kind.BREACH: [0.35, 80.0, 40.0, "sine", 0.5, 8.0, 0.8],
	Kind.EVICT: [0.30, 100.0, 40.0, "sine", 0.4, 9.0, 0.8],
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
