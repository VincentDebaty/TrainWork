extends RefCounted
## Pose de rails « au toucher » : à partir de la case touchée, des rails voisins et de
## la dernière case choisie (la « tête »), calcule les segments à poser. Pur : ne
## modifie jamais le réseau (le contrôleur applique le plan).
##
## Ordre des règles :
##  0. case déjà équipée (rail ou gare) : devient la tête, ou est reliée à la tête ;
##  1. case voisine d'un rail : raccord automatique à la meilleure extrémité
##     (bout de voie ou gare, alignement droit) ; comble un trou entre deux bouts ;
##  2. coin à 90° sur un bout de voie : arrondi en remplaçant le dernier segment par
##     une diagonale à 45° ;
##  3. sinon, tracé calculé depuis la tête en respectant les virages (45° par case) ;
##  4. sinon, la case devient la tête.

const Dir = preload("res://src/rail/direction.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const Terrain = preload("res://src/core/terrain.gd")

enum Kind { ANCHOR, CONNECT, ROUTE, ROUND, FAIL }

const R = RailNetwork.Result

## Rayon de recherche autour de la tête (cases) et coûts d'essai du tracé.
const MAX_RADIUS: int = 20
const EDGE_COST: int = 10
## Score à partir duquel un raccord (bout de voie, gare) l'emporte sur l'arrondi d'un coin.
const END_SCORE: int = 8
const TURN_COST: int = 3
const MAX_COST: int = 300


## Plan pour un toucher sur `cell`. Résultat : {"kind", "edges": Array[Vector4i],
## "replace": Array[Vector4i] ([ancien, nouveau] ou vide), "head": Vector2i, "message"}.
func plan_tap(network: RailNetwork, cell: Vector2i, head: Vector2i, has_head: bool) -> Dictionary:
	var graph: RefCounted = network.graph
	if not network.map.in_bounds(cell):
		return _fail(RailNetwork.result_text(R.OUT_OF_BOUNDS))
	if not Terrain.is_buildable(network.map.get_terrain(cell)):
		return _fail(RailNetwork.result_text(R.BLOCKED_TERRAIN))

	if graph.has_cell(cell) or network.station_at(cell) != null:
		if not has_head or head == cell:
			return _anchor(cell, "Départ choisi : touchez où prolonger la voie.")
		return _route(network, head, cell)

	var candidates: Array[Dictionary] = []
	var sharp_ends: Array[Vector2i] = []
	var refusal: int = -1
	for d: int in 8:
		var n: Vector2i = cell + Dir.VECTORS[d]
		if not network.map.in_bounds(n):
			continue
		if not (graph.has_cell(n) or network.station_at(n) != null):
			continue
		var result: int = network.check_edge(n, cell)
		if result == R.OK:
			candidates.append({"cell": n, "score": _score(network, n, cell)})
		else:
			if refusal < 0:
				refusal = result
			if result == R.SHARP_TURN:
				sharp_ends.append(n)

	var best_score: int = -1
	for candidate: Dictionary in candidates:
		best_score = maxi(best_score, candidate["score"])
	if best_score >= END_SCORE:
		return _connect(network, cell, candidates)

	for end: Vector2i in sharp_ends:
		if graph.degree(end) != 1 or network.station_at(end) != null:
			continue
		var previous: Vector2i = graph.neighbors(end)[0]
		if Dir.from_delta(cell - previous) >= 0 and network.check_replace(previous, end, previous, cell) == R.OK:
			return {
				"kind": Kind.ROUND, "edges": [] as Array[Vector4i],
				"replace": [Dir.pair(previous, end), Dir.pair(previous, cell)] as Array[Vector4i],
				"head": cell, "message": "Virage arrondi.",
			}

	if not candidates.is_empty():
		return _connect(network, cell, candidates)
	if has_head and head != cell:
		return _route(network, head, cell)
	if refusal >= 0:
		return _fail(RailNetwork.result_text(refusal))
	return _anchor(cell, "Départ choisi : touchez une autre case pour poser la voie.")


## Tracé le plus court (virages pénalisés) de `from` à `to`, ou vide s'il n'y en a pas.
## Les cases intermédiaires doivent être libres ; seule l'arrivée peut être équipée.
func find_route(network: RailNetwork, from: Vector2i, to: Vector2i, radius: int = MAX_RADIUS) -> Array[Vector2i]:
	var graph: RefCounted = network.graph
	var max_cost: int = maxi(MAX_COST, radius * 3 * EDGE_COST)
	var best: Dictionary = {}
	var parent: Dictionary = {}
	var start: Vector3i = Vector3i(from.x, from.y, 0)  # z = direction d'arrivée + 1
	best[start] = 0
	var buckets: Array = []
	for _i: int in max_cost + 1:
		buckets.append([])
	buckets[0].append(start)
	for cost: int in max_cost + 1:
		var bucket: Array = buckets[cost]
		var index: int = 0
		while index < bucket.size():
			var state: Vector3i = bucket[index]
			index += 1
			if best.get(state, 1 << 30) != cost:
				continue
			var cell: Vector2i = Vector2i(state.x, state.y)
			if cell == to and state != start:
				return _rebuild(parent, state, start)
			for d: int in 8:
				if state.z != 0 and not Dir.turn_ok(state.z - 1, d):
					continue
				var next: Vector2i = cell + Dir.VECTORS[d]
				if maxi(absi(next.x - from.x), absi(next.y - from.y)) > radius:
					continue
				if next != to and (graph.has_cell(next) or network.station_at(next) != null):
					continue
				if network.check_edge(cell, next) != R.OK:
					continue
				var step: int = EDGE_COST
				if state.z != 0 and ((d - (state.z - 1)) & 7) != 0:
					step += TURN_COST
				var new_cost: int = cost + step
				var next_state: Vector3i = Vector3i(next.x, next.y, d + 1)
				if new_cost <= max_cost and new_cost < best.get(next_state, 1 << 30):
					best[next_state] = new_cost
					parent[next_state] = state
					buckets[new_cost].append(next_state)
	return [] as Array[Vector2i]


func _connect(network: RailNetwork, cell: Vector2i, candidates: Array[Dictionary]) -> Dictionary:
	var graph: RefCounted = network.graph
	var best_index: int = 0
	for i: int in candidates.size():
		if candidates[i]["score"] > candidates[best_index]["score"]:
			best_index = i
	var edges: Array[Vector4i] = [Dir.pair(candidates[best_index]["cell"], cell)]
	# Comble un trou : relie aussi un second bout de voie ou une gare voisine.
	for i: int in candidates.size():
		var other: Vector2i = candidates[i]["cell"]
		if i != best_index and edges.size() < 2 and (graph.degree(other) == 1 or network.station_at(other) != null):
			var extended: Array[Vector4i] = edges.duplicate()
			extended.append(Dir.pair(other, cell))
			if not _all_ok(network.simulate_edges(extended)):
				continue
			edges = extended
	return {"kind": Kind.CONNECT, "edges": edges, "replace": [] as Array[Vector4i], "head": cell, "message": ""}


func _all_ok(results: Array[int]) -> bool:
	for result: int in results:
		if result != R.OK:
			return false
	return true


func _route(network: RailNetwork, from: Vector2i, to: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = find_route(network, from, to)
	if cells.size() < 2:
		return _fail("Aucun tracé possible (virage trop serré, obstacle ou trop loin).")
	var edges: Array[Vector4i] = []
	for i: int in range(1, cells.size()):
		edges.append(Dir.pair(cells[i - 1], cells[i]))
	var results: Array[int] = network.simulate_edges(edges)
	for result: int in results:
		if result != R.OK:
			return _fail(RailNetwork.result_text(result))
	return {"kind": Kind.ROUTE, "edges": edges, "replace": [] as Array[Vector4i], "head": to, "message": ""}


func _score(network: RailNetwork, neighbor: Vector2i, cell: Vector2i) -> int:
	var graph: RefCounted = network.graph
	var score: int = 0
	if network.station_at(neighbor) != null:
		score += 8
	elif graph.degree(neighbor) == 1:
		score += 10
	var outgoing: int = Dir.from_delta(cell - neighbor)
	var mask: int = graph.mask(neighbor)
	var alignment: int = 0
	for e: int in 8:
		if mask & (1 << e):
			var diff: int = (outgoing - e) & 7
			alignment = maxi(alignment, 5 if diff == 4 else 3 if diff == 3 or diff == 5 else 0)
	return score + alignment


func _rebuild(parent: Dictionary, goal: Vector3i, start: Vector3i) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	var state: Vector3i = goal
	while state != start:
		reversed.append(Vector2i(state.x, state.y))
		state = parent[state]
	reversed.append(Vector2i(start.x, start.y))
	reversed.reverse()
	return reversed


func _anchor(cell: Vector2i, text: String) -> Dictionary:
	return {"kind": Kind.ANCHOR, "edges": [] as Array[Vector4i], "replace": [] as Array[Vector4i], "head": cell, "message": text}


func _fail(text: String) -> Dictionary:
	return {"kind": Kind.FAIL, "edges": [] as Array[Vector4i], "replace": [] as Array[Vector4i], "head": Vector2i(-1, -1), "message": text}
