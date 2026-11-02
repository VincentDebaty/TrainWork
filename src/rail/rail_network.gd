extends RefCounted
## Réseau ferré : graphe + gares + règles de pose sur la carte. C'est l'unique point
## d'entrée pour modifier les voies. Aucune dépendance au rendu.
##
## Règles de pose (défauts d'essai, voir docs/DECISIONS.md) :
##  - cases voisines (8 directions), dans la carte, terrain constructible (pas d'eau) ;
##  - pas de croisement de deux diagonales sans case commune ;
##  - pas de virage trop serré : à chaque case, un nouveau segment doit pouvoir
##    s'enchaîner avec un segment existant à angle ouvert >= 135° ;
##  - une gare n'est raccordée que le long de son axe.

signal changed

const Dir = preload("res://src/rail/direction.gd")
const RailGraph = preload("res://src/rail/rail_graph.gd")
const Station = preload("res://src/rail/station.gd")
const Terrain = preload("res://src/core/terrain.gd")

enum Result {
	OK,
	OUT_OF_BOUNDS,
	NOT_ADJACENT,
	BLOCKED_TERRAIN,
	ALREADY_EXISTS,
	CROSSING,
	SHARP_TURN,
	STATION_AXIS,
	STATION_EXISTS,
	BAD_ORIENTATION,
	LOCKED,
	OCCUPIED,
	INSUFFICIENT_FUNDS,
	RESERVED,
	BRIDGE_LOCKED,
}

const RESULT_TEXTS: Dictionary = {
	Result.OK: "OK",
	Result.OUT_OF_BOUNDS: "Hors de la carte",
	Result.NOT_ADJACENT: "Cases non voisines",
	Result.BLOCKED_TERRAIN: "Terrain non constructible",
	Result.ALREADY_EXISTS: "Déjà posé",
	Result.CROSSING: "Croisement impossible",
	Result.SHARP_TURN: "Virage trop serré",
	Result.STATION_AXIS: "Raccord hors de l'axe de la gare",
	Result.STATION_EXISTS: "Une gare occupe déjà cette case",
	Result.BAD_ORIENTATION: "Orientation invalide",
	Result.LOCKED: "Voie occupée par un train",
	Result.OCCUPIED: "Emplacement occupé par un bâtiment",
	Result.INSUFFICIENT_FUNDS: "Pièces insuffisantes",
	Result.RESERVED: "Site réservé pour une extension future",
	Result.BRIDGE_LOCKED: "Rivière : le pont sera disponible au niveau 2",
}

## Gardes posés par la simulation : empêchent de retirer une voie sous un train
## (`edge_guard(a, b) -> bool`) ou une gare utilisée par une ligne
## (`station_guard(station_id) -> bool`). Vrai = suppression refusée.
## Cellules bloquées : `cell_blocker(cell) -> int` : 0 libre, 1 bâtiment, 2 site réservé
## (bâtiment d'un niveau futur, invisible).
var cell_blocker: Callable = Callable()
## Franchissement de l'eau : `water_crossing(cell) -> int` : 0 impossible, 1 pont
## disponible, 2 site de pont pas encore débloqué.
var water_crossing: Callable = Callable()
var edge_guard: Callable = Callable()
var station_guard: Callable = Callable()

var map: RefCounted
var graph: RailGraph = RailGraph.new()
var _stations: Dictionary = {}  # id -> Station
var _station_at: Dictionary = {}  # Vector2i -> id
var _next_station_id: int = 1


func _init(p_map: RefCounted) -> void:
	map = p_map


static func result_text(result: int) -> String:
	return RESULT_TEXTS.get(result, "?")


# --- Segments -----------------------------------------------------------------

## Valide la pose d'un segment sans rien modifier.
func check_edge(a: Vector2i, b: Vector2i) -> int:
	if not map.in_bounds(a) or not map.in_bounds(b):
		return Result.OUT_OF_BOUNDS
	var d: int = Dir.from_delta(b - a)
	if d < 0:
		return Result.NOT_ADJACENT
	for cell: Vector2i in [a, b]:
		var terrain_result: int = _rail_terrain_result(cell)
		if terrain_result != Result.OK:
			return terrain_result
	for cell: Vector2i in [a, b]:
		var block: int = _block_result(cell)
		if block != Result.OK:
			return block
	if graph.has_edge(a, b):
		return Result.ALREADY_EXISTS
	var opp: int = Dir.opposite(d)
	var station_a: Station = station_at(a)
	var station_b: Station = station_at(b)
	if (station_a != null and not Dir.on_axis(d, station_a.orientation)) \
			or (station_b != null and not Dir.on_axis(opp, station_b.orientation)):
		return Result.STATION_AXIS
	if Dir.is_diagonal(d):
		var delta: Vector2i = Dir.VECTORS[d]
		if graph.has_edge(Vector2i(a.x + delta.x, a.y), Vector2i(a.x, a.y + delta.y)):
			return Result.CROSSING
	if not _has_partner(a, d) or not _has_partner(b, opp):
		return Result.SHARP_TURN
	return Result.OK


func place_edge(a: Vector2i, b: Vector2i) -> int:
	var result: int = check_edge(a, b)
	if result == Result.OK:
		graph.add_edge(a, b)
		changed.emit()
	return result


## Pose une suite de segments (Vector4i). Renvoie {"placed": n, "placed_edges": [...], "refused": {résultat: n}}.
## Les segments déjà présents ne sont ni posés ni comptés comme refus.
func place_edges(edges: Array[Vector4i]) -> Dictionary:
	var placed: int = 0
	var placed_edges: Array[Vector4i] = []
	var refused: Dictionary = {}
	for e: Vector4i in edges:
		var result: int = check_edge(Vector2i(e.x, e.y), Vector2i(e.z, e.w))
		if result == Result.OK:
			graph.add_edge(Vector2i(e.x, e.y), Vector2i(e.z, e.w))
			placed += 1
			placed_edges.append(e)
		elif result != Result.ALREADY_EXISTS:
			refused[result] = refused.get(result, 0) + 1
	if placed > 0:
		changed.emit()
	return {"placed": placed, "placed_edges": placed_edges, "refused": refused}


## Résultat qu'aurait chaque segment d'une suite posée dans l'ordre (aperçu). Ne
## modifie pas le réseau et n'émet pas `changed`.
func simulate_edges(edges: Array[Vector4i]) -> Array[int]:
	var saved_id: int = graph.next_id()
	var added: Array[Vector4i] = []
	var results: Array[int] = []
	for e: Vector4i in edges:
		var a: Vector2i = Vector2i(e.x, e.y)
		var b: Vector2i = Vector2i(e.z, e.w)
		var result: int = check_edge(a, b)
		results.append(result)
		if result == Result.OK:
			graph.add_edge(a, b)
			added.append(e)
	for i: int in range(added.size() - 1, -1, -1):
		graph.remove_edge(Vector2i(added[i].x, added[i].y), Vector2i(added[i].z, added[i].w))
	graph.set_next_id(saved_id)
	return results


func is_edge_locked(a: Vector2i, b: Vector2i) -> bool:
	return edge_guard.is_valid() and edge_guard.call(a, b)


## Résultat qu'aurait le remplacement du segment `old` par `new` (sans rien modifier).
func check_replace(old_a: Vector2i, old_b: Vector2i, new_a: Vector2i, new_b: Vector2i) -> int:
	if not graph.has_edge(old_a, old_b):
		return Result.NOT_ADJACENT
	if is_edge_locked(old_a, old_b):
		return Result.LOCKED
	var id: int = graph.edge_id(old_a, old_b)
	graph.remove_edge(old_a, old_b)
	var result: int = check_edge(new_a, new_b)
	graph.add_edge_with_id(old_a, old_b, id)
	return result


## Remplace un segment par un autre (arrondi d'un coin). Atomique : rien ne change si refusé.
func replace_edge(old_a: Vector2i, old_b: Vector2i, new_a: Vector2i, new_b: Vector2i) -> int:
	var result: int = check_replace(old_a, old_b, new_a, new_b)
	if result == Result.OK:
		graph.remove_edge(old_a, old_b)
		graph.add_edge(new_a, new_b)
		changed.emit()
	return result


func remove_edge(a: Vector2i, b: Vector2i) -> bool:
	if is_edge_locked(a, b):
		return false
	var removed: bool = graph.remove_edge(a, b)
	if removed:
		changed.emit()
	return removed


## Supprime les segments touchant la case (sauf ceux verrouillés). Renvoie leur nombre.
func remove_edges_at(cell: Vector2i) -> int:
	var count: int = 0
	for n: Vector2i in graph.neighbors(cell):
		if not is_edge_locked(cell, n):
			graph.remove_edge(cell, n)
			count += 1
	if count > 0:
		changed.emit()
	return count


# --- Gares --------------------------------------------------------------------

func check_station(cell: Vector2i, orientation: int) -> int:
	if orientation < 0 or orientation > 3:
		return Result.BAD_ORIENTATION
	if not map.in_bounds(cell):
		return Result.OUT_OF_BOUNDS
	if not Terrain.is_buildable(map.get_terrain(cell)):
		return Result.BLOCKED_TERRAIN
	var block: int = _block_result(cell)
	if block != Result.OK:
		return block
	if _station_at.has(cell):
		return Result.STATION_EXISTS
	var m: int = graph.mask(cell)
	for d: int in 8:
		if (m & (1 << d)) and not Dir.on_axis(d, orientation):
			return Result.STATION_AXIS
	return Result.OK


func place_station(cell: Vector2i, orientation: int) -> int:
	var result: int = check_station(cell, orientation)
	if result == Result.OK:
		var station: Station = Station.new(_next_station_id, cell, orientation)
		_next_station_id += 1
		_stations[station.id] = station
		_station_at[cell] = station.id
		changed.emit()
	return result


func remove_station(cell: Vector2i) -> bool:
	if not _station_at.has(cell):
		return false
	if station_guard.is_valid() and station_guard.call(_station_at[cell]):
		return false
	_stations.erase(_station_at[cell])
	_station_at.erase(cell)
	changed.emit()
	return true


func station_at(cell: Vector2i) -> Station:
	return _stations.get(_station_at.get(cell, 0))


func station_by_id(id: int) -> Station:
	return _stations.get(id)


func stations() -> Array[Station]:
	var result: Array[Station] = []
	for id: int in _stations:
		result.append(_stations[id])
	return result


func station_count() -> int:
	return _stations.size()


## Chemin ferroviaire praticable (rayon de courbure respecté) entre deux gares.
func find_station_path(from_id: int, to_id: int) -> Array[Vector2i]:
	var from_station: Station = station_by_id(from_id)
	var to_station: Station = station_by_id(to_id)
	if from_station == null or to_station == null:
		return [] as Array[Vector2i]
	return graph.find_path(from_station.cell, to_station.cell)


# --- Interne ------------------------------------------------------------------

func _block_result(cell: Vector2i) -> int:
	if not cell_blocker.is_valid():
		return Result.OK
	match cell_blocker.call(cell):
		1:
			return Result.OCCUPIED
		2:
			return Result.RESERVED
	return Result.OK


## Un rail peut-il passer sur cette case ? L'eau seulement par un site de pont débloqué.
func _rail_terrain_result(cell: Vector2i) -> int:
	var terrain: int = map.get_terrain(cell)
	if Terrain.is_buildable(terrain):
		return Result.OK
	if terrain == Terrain.Type.WATER and water_crossing.is_valid():
		match water_crossing.call(cell):
			1:
				return Result.OK
			2:
				return Result.BRIDGE_LOCKED
	return Result.BLOCKED_TERRAIN


func is_bridge_open(cell: Vector2i) -> bool:
	return water_crossing.is_valid() and water_crossing.call(cell) == 1


## Le segment sortant de `cell` dans la direction `d` a-t-il de quoi s'enchaîner ?
## Vrai si la case est vide de voies, ou si un segment existant forme un angle ouvert.
func _has_partner(cell: Vector2i, d: int) -> bool:
	var m: int = graph.mask(cell)
	if m == 0:
		return true
	for e: int in 8:
		if (m & (1 << e)) and Dir.edges_compatible(d, e):
			return true
	return false


# --- Sauvegarde ---------------------------------------------------------------

func to_dict() -> Dictionary:
	var stations_list: Array = []
	for id: int in _stations:
		var station: Station = _stations[id]
		stations_list.append({"id": station.id, "cell": [station.cell.x, station.cell.y],
				"orientation": station.orientation, "type": station.type, "name": station.station_name})
	return {"graph": graph.to_dict(), "stations": stations_list, "next_station_id": _next_station_id}


func load_dict(data: Dictionary) -> void:
	graph.load_dict(data["graph"])
	_stations.clear()
	_station_at.clear()
	for entry: Dictionary in data["stations"]:
		var station: Station = Station.new(entry["id"], Vector2i(entry["cell"][0], entry["cell"][1]), entry["orientation"])
		station.type = entry["type"]
		station.station_name = entry["name"]
		_stations[station.id] = station
		_station_at[station.cell] = station.id
	_next_station_id = data["next_station_id"]
	changed.emit()
