class_name Acquisition
extends RefCounted

var owners: Array[int] = [0, 0, -1, 1, 1]
var unlocked: Array[bool] = [false, false, true, false, false]
var progress: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var attackers: Array[int] = [-1, -1, -1, -1, -1]
var idle: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var remaining: float = 720.0
var overtime: bool = false
var quiet: float = 0.0
var winner: int = -2
var captures: Array = []
const TIMES = [10.0, 14.0, 18.0, 14.0, 10.0]

func reset() -> void:
	owners.assign([0, 0, -1, 1, 1])
	unlocked.assign([false, false, true, false, false])
	progress.assign([0.0, 0.0, 0.0, 0.0, 0.0])
	attackers.assign([-1, -1, -1, -1, -1])
	idle.assign([0.0, 0.0, 0.0, 0.0, 0.0])
	remaining = 720.0
	overtime = false
	quiet = 0.0
	winner = -2

func recalculate() -> void:
	unlocked.fill(false)
	if owners[2] == -1:
		unlocked[2] = true
		return
	for i in range(4):
		if owners[i] != owners[i + 1]:
			unlocked[i] = true
			unlocked[i + 1] = true
			break
	for i in range(5):
		if not unlocked[i]:
			progress[i] = 0.0
			attackers[i] = -1

# Occupancy is [[team0_count, team1_count], ...], real fighters only.
func tick(dt: float, occupancy: Array) -> void:
	if winner != -2:
		return
	captures.clear()
	var active := false
	var completed: Array = []
	for i in range(5):
		if not unlocked[i]:
			continue
		var counts = occupancy[i]
		var side: int = -1
		if counts[0] > 0 and counts[1] == 0:
			side = 0
		elif counts[1] > 0 and counts[0] == 0:
			side = 1
		if side >= 0 and owners[i] != side:
			active = true
			idle[i] = 0.0
			if attackers[i] != side:
				progress[i] = maxf(0.0, progress[i] - dt / TIMES[i])
				if progress[i] <= 0.0:
					attackers[i] = side
			if attackers[i] == side:
				progress[i] += dt * (1.0 + 0.35 * (mini(3, counts[side]) - 1)) / TIMES[i]
				if progress[i] >= 1.0:
					completed.append([i, side])
		elif counts[0] > 0 and counts[1] > 0:
			# A contested partial capture sustains overtime but does not advance.
			active = active or progress[i] > 0.0
			idle[i] = 0.0
		else:
			idle[i] += dt
			if idle[i] > 3.0:
				progress[i] = maxf(0.0, progress[i] - dt / TIMES[i])
	# Two opposing captures on the same boundary would create disconnected ownership.
	# Cancel that exact simultaneous exchange rather than favoring array order.
	if completed.size() == 2 and completed[0][1] != completed[1][1]:
		for capture in completed:
			progress[capture[0]] = 0.0
		completed.clear()
	for capture in completed:
		owners[capture[0]] = capture[1]
		progress[capture[0]] = 0.0
		attackers[capture[0]] = -1
		captures.append(capture)
	if not completed.is_empty():
		recalculate()
		if owners[0] == 1:
			winner = 1
		elif owners[4] == 0:
			winner = 0
	remaining = maxf(0.0, remaining - dt)
	if remaining <= 0.0 and winner == -2:
		if active:
			overtime = true
			quiet = 0.0
		elif overtime:
			quiet += dt
			if quiet >= 3.0:
				finish_on_territory()
		else:
			finish_on_territory()

func finish_on_territory() -> void:
	var a := owners.count(0)
	var b := owners.count(1)
	winner = 0 if a > b else (1 if b > a else -1)

func pack() -> Dictionary:
	return {"owners": owners, "unlocked": unlocked, "progress": progress, "remaining": remaining, "overtime": overtime, "winner": winner}

func unpack(data: Dictionary) -> void:
	owners.assign(data.owners)
	unlocked.assign(data.unlocked)
	progress.assign(data.progress)
	remaining = data.remaining
	overtime = data.overtime
	winner = data.winner
