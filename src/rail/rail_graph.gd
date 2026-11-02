extends RefCounted
## Topologie des voies : les cases sont les nœuds, les segments relient deux cases
## voisines (8 directions). Un aiguillage est une case de degré >= 3 (déduit, jamais
## stocké). Ne connaît ni le terrain ni les gares : les règles de pose sont dans
## RailNetwork.

const Dir = preload("res://src/rail/direction.gd")

var _edges: Dictionary = {}  # Vector4i canonique -> id stable
var _masks: Dictionary = {}  # Vector2i -> masque de bits des directions reliées
var _next_id: int = 1


static func edge_key(a: Vector2i, b: Vector2i) -> Vector4i:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return Dir.pair(a, b)
	return Dir.pair(b, a)


func has_edge(a: Vector2i, b: Vector2i) -> bool:
	return _edges.has(edge_key(a, b))


## Id stable du segment, 0 s'il n'existe pas.
func edge_id(a: Vector2i, b: Vector2i) -> int:
	return _edges.get(edge_key(a, b), 0)


## Ajoute le segment (cases voisines requises). Renvoie son id, 0 si refusé.
func add_edge(a: Vector2i, b: Vector2i) -> int:
	var d: int = Dir.from_delta(b - a)
	var key: Vector4i = edge_key(a, b)
	if d < 0 or _edges.has(key):
		return 0
	var id: int = _next_id
	_next_id += 1
	_edges[key] = id
	_masks[a] = mask(a) | (1 << d)
	_masks[b] = mask(b) | (1 << Dir.opposite(d))
	return id


## Rétablit un segment avec son id d'origine (annulation). Renvoie false s'il existe déjà.
func add_edge_with_id(a: Vector2i, b: Vector2i, id: int) -> bool:
	var d: int = Dir.from_delta(b - a)
	var key: Vector4i = edge_key(a, b)
	if d < 0 or _edges.has(key):
		return false
	_edges[key] = id
	_masks[a] = mask(a) | (1 << d)
	_masks[b] = mask(b) | (1 << Dir.opposite(d))
	_next_id = maxi(_next_id, id + 1)
	return true


func remove_edge(a: Vector2i, b: Vector2i) -> bool:
	var key: Vector4i = edge_key(a, b)
	if not _edges.has(key):
		return false
	var d: int = Dir.from_delta(b - a)
	_edges.erase(key)
	_clear_bit(a, d)
	_clear_bit(b, Dir.opposite(d))
	return true


func mask(cell: Vector2i) -> int:
	return _masks.get(cell, 0)


func degree(cell: Vector2i) -> int:
	var m: int = mask(cell)
	var count: int = 0
	for d: int in 8:
		if m & (1 << d):
			count += 1
	return count


func has_cell(cell: Vector2i) -> bool:
	return _masks.has(cell)


func is_switch(cell: Vector2i) -> bool:
	return degree(cell) >= 3


func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var m: int = mask(cell)
	for d: int in 8:
		if m & (1 << d):
			result.append(cell + Dir.VECTORS[d])
	return result


func edge_count() -> int:
	return _edges.size()


func switch_count() -> int:
	var count: int = 0
	for cell: Vector2i in _masks:
		if is_switch(cell):
			count += 1
	return count


## Segments, sous forme Vector4i (ax, ay, bx, by), dans l'ordre de création.
func edges() -> Array[Vector4i]:
	var result: Array[Vector4i] = []
	for key: Vector4i in _edges:
		result.append(key)
	return result


func cells() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _masks:
		result.append(cell)
	return result


## Prochain id de segment (sert à annuler proprement une simulation de pose).
func next_id() -> int:
	return _next_id


func set_next_id(value: int) -> void:
	_next_id = value


## Connexité simple (sans règle de virage) : b est-il atteignable depuis a ?
func is_connected_cells(a: Vector2i, b: Vector2i) -> bool:
	if not has_cell(a) or not has_cell(b):
		return false
	var seen: Dictionary = {a: true}
	var stack: Array[Vector2i] = [a]
	while not stack.is_empty():
		var cell: Vector2i = stack.pop_back()
		if cell == b:
			return true
		for n: Vector2i in neighbors(cell):
			if not seen.has(n):
				seen[n] = true
				stack.append(n)
	return false


## Plus court chemin (en segments) respectant le rayon de courbure : virage <= 45°
## par case, pas de demi-tour. Renvoie les cases de `from` à `to`, vide si aucun.
## `initial_dir` : direction de roulement au départ (0..7) pour interdire le demi-tour ;
## -1 si le départ est libre (en gare).
func find_path(from: Vector2i, to: Vector2i, initial_dir: int = -1) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not has_cell(from) or not has_cell(to):
		return result
	if from == to:
		result.append(from)
		return result
	# État = (case, direction d'arrivée + 1) ; 0 = pas encore de direction.
	var start: Vector3i = Vector3i(from.x, from.y, initial_dir + 1)
	var parent: Dictionary = {start: start}
	var queue: Array[Vector3i] = [start]
	var head: int = 0
	while head < queue.size():
		var state: Vector3i = queue[head]
		head += 1
		var cell: Vector2i = Vector2i(state.x, state.y)
		var m: int = mask(cell)
		for d: int in 8:
			if not (m & (1 << d)):
				continue
			if state.z != 0 and not Dir.turn_ok(state.z - 1, d):
				continue
			var next_cell: Vector2i = cell + Dir.VECTORS[d]
			var next_state: Vector3i = Vector3i(next_cell.x, next_cell.y, d + 1)
			if parent.has(next_state):
				continue
			parent[next_state] = state
			if next_cell == to:
				return _rebuild_path(parent, next_state, start)
			queue.append(next_state)
	return result


func _rebuild_path(parent: Dictionary, goal: Vector3i, start: Vector3i) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	var state: Vector3i = goal
	while state != start:
		reversed.append(Vector2i(state.x, state.y))
		state = parent[state]
	reversed.append(Vector2i(start.x, start.y))
	reversed.reverse()
	return reversed


func _clear_bit(cell: Vector2i, d: int) -> void:
	var m: int = mask(cell) & ~(1 << d)
	if m == 0:
		_masks.erase(cell)
	else:
		_masks[cell] = m


# --- Sauvegarde ---------------------------------------------------------------

func to_dict() -> Dictionary:
	var list: Array = []
	for key: Vector4i in _edges:
		list.append({"a": [key.x, key.y], "b": [key.z, key.w], "id": _edges[key]})
	return {"edges": list, "next_id": _next_id}


func load_dict(data: Dictionary) -> void:
	_edges.clear()
	_masks.clear()
	for e: Dictionary in data["edges"]:
		add_edge_with_id(Vector2i(e["a"][0], e["a"][1]), Vector2i(e["b"][0], e["b"][1]), e["id"])
	_next_id = data["next_id"]
