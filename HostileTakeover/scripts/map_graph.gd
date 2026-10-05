class_name MapGraph
extends RefCounted

# Waypoint graph for bots (walk and ramp edges only). Built from MapLayout.graph().

var names: Array[String] = []
var positions: Array[Vector3] = []
var index: Dictionary = {}
var adjacency: Array = []

static func from_layout() -> MapGraph:
	var g := MapGraph.new()
	var data := MapLayout.graph()
	for n in data.nodes:
		g.index[n] = g.names.size()
		g.names.append(n)
		g.positions.append(data.nodes[n])
		g.adjacency.append([])
	for l in data.links:
		var a: int = g.index[l[0]]
		var b: int = g.index[l[1]]
		var length: float = g.positions[a].distance_to(g.positions[b])
		g.adjacency[a].append([b, l[2], length])
		g.adjacency[b].append([a, l[2], length])
	return g

# Nearest node on the same level (|dy| < 2.5), by horizontal distance.
func nearest(pos: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in range(positions.size()):
		var p := positions[i]
		if absf(p.y - pos.y) > 2.5:
			continue
		var d := Vector2(p.x - pos.x, p.z - pos.z).length()
		if d < best_d:
			best_d = d
			best = i
	return best

func node(name: String) -> int:
	return index.get(name, -1)

# Dijkstra with per-route-tag cost multipliers (lower = preferred). Returns positions, empty if unreachable.
func path(from_node: int, to_node: int, weights: Dictionary) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if from_node < 0 or to_node < 0:
		return out
	var dist: Array = []
	var prev: Array = []
	var done: Array = []
	for i in range(positions.size()):
		dist.append(INF)
		prev.append(-1)
		done.append(false)
	dist[from_node] = 0.0
	for _step in range(positions.size()):
		var u := -1
		var best := INF
		for i in range(positions.size()):
			if not done[i] and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0 or u == to_node:
			break
		done[u] = true
		for e in adjacency[u]:
			var cost: float = e[2] * weights.get(e[1], 1.0)
			if dist[u] + cost < dist[e[0]]:
				dist[e[0]] = dist[u] + cost
				prev[e[0]] = u
	if prev[to_node] < 0 and from_node != to_node:
		return out
	var cursor := to_node
	while cursor >= 0:
		out.push_front(positions[cursor])
		cursor = prev[cursor]
	return out
