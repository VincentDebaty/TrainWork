extends RefCounted
## Lignes et trains : circulation sur le réseau, arrêts en gare, aller-retour.
##
## Sécurité (M4) : avant de quitter une gare, un train réserve TOUT son trajet jusqu'à la
## gare suivante, quai de destination compris (voir Dispatcher). Sinon il attend en gare.
## Les cases se libèrent derrière lui. Les trains ne rebroussent qu'en gare : en ligne,
## le rayon de courbure interdit le demi-tour.

signal train_arrived(train_id: int, station_id: int, tick: int)
## Émis quand l'ensemble des trains en interblocage change ; `text` est vide s'il n'y en a plus.
signal deadlock_changed(train_ids: Array, text: String)

const Dir = preload("res://src/rail/direction.gd")
const Line = preload("res://src/sim/line.gd")
const Train = preload("res://src/sim/train.gd")
const SimParams = preload("res://src/sim/sim_params.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const GoodsStock = preload("res://src/sim/goods_stock.gd")
const Dispatcher = preload("res://src/sim/dispatcher.gd")

enum LineResult {
	OK,
	TOO_FEW_STATIONS,
	UNKNOWN_STATION,
	REPEATED_STATION,
	NO_ROUTE,
	UNKNOWN_LINE,
	TOO_MANY_TRAINS,
	STATION_FULL,
}

const LINE_RESULT_TEXTS: Dictionary = {
	LineResult.OK: "OK",
	LineResult.TOO_FEW_STATIONS: "Une ligne exige au moins 2 gares",
	LineResult.UNKNOWN_STATION: "Gare inconnue",
	LineResult.REPEATED_STATION: "Deux gares identiques de suite",
	LineResult.NO_ROUTE: "Pas de voie praticable entre deux gares",
	LineResult.UNKNOWN_LINE: "Ligne inconnue",
	LineResult.TOO_MANY_TRAINS: "Nombre maximal de trains atteint",
	LineResult.STATION_FULL: "Gare pleine : aucun quai libre",
}

var network: RailNetwork
var params: SimParams
## Chargement et revenus (null : trains sans marchandises).
var logistics: RefCounted = null
var content: RefCounted = null
## Niveau du dépôt : wagons disponibles et nombre de trains (null : niveau 1).
var progression: RefCounted = null
var dispatcher: Dispatcher = Dispatcher.new()
## Trains en interblocage (attente circulaire) et son diagnostic.
var deadlocked: Array[int] = []
var deadlock_text: String = ""
var lines: Dictionary = {}  # id -> Line
var trains: Dictionary = {}  # id -> Train
var last_created_line_id: int = 0
## Tronçon (gare de départ, gare d'arrivée) qui a fait refuser la dernière ligne (NO_ROUTE).
var last_blocked_leg: Array[int] = []
var _next_line_id: int = 1
var _next_train_id: int = 1


func _init(p_network: RailNetwork, p_params: SimParams) -> void:
	network = p_network
	params = p_params
	network.edge_guard = is_edge_locked
	network.station_guard = station_in_use
	dispatcher.capacity_of = _cell_capacity


## Quantité réservée pour une gare par les trains autres que `except_id`.
func booked_by_others(station_id: int, good: String, except_id: int) -> int:
	var total: int = 0
	for id: int in trains:
		if id != except_id:
			total += trains[id].bookings.get(station_id, {}).get(good, 0)
	return total


static func line_result_text(result: int) -> String:
	return LINE_RESULT_TEXTS.get(result, "?")


## Message pour le joueur, avec le tronçon bloquant et la cause probable.
func line_error_message(result: int) -> String:
	if result != LineResult.NO_ROUTE or last_blocked_leg.size() != 2:
		return line_result_text(result)
	var from_station: RefCounted = network.station_by_id(last_blocked_leg[0])
	var to_station: RefCounted = network.station_by_id(last_blocked_leg[1])
	var text: String = "%s → %s impossible" % [from_station.station_name, to_station.station_name]
	if network.graph.is_connected_cells(from_station.cell, to_station.cell):
		return text + " : demi-tour requis hors gare. Ajoutez un terminus ou une boucle."
	return text + " : les gares ne sont pas reliées par une voie continue."


# --- Lignes et trains ---------------------------------------------------------

## Crée une ligne si chaque tronçon entre gares consécutives est praticable.
func create_line(station_ids: Array[int]) -> int:
	var result: int = _validate_stations(station_ids)
	if result != LineResult.OK:
		return result
	var line: Line = Line.new(_next_line_id, station_ids)
	_next_line_id += 1
	lines[line.id] = line
	last_created_line_id = line.id
	return LineResult.OK


## Change la liste de gares d'une ligne (GDD : « un changement de liste est appliqué après
## le prochain arrêt en gare ») : chaque train de la ligne l'adopte à son prochain arrêt.
func update_line(line_id: int, station_ids: Array[int]) -> int:
	if not lines.has(line_id):
		return LineResult.UNKNOWN_LINE
	var result: int = _validate_stations(station_ids)
	if result == LineResult.OK:
		lines[line_id].station_ids = station_ids.duplicate()
	return result


func _validate_stations(station_ids: Array[int]) -> int:
	if station_ids.size() < 2:
		return LineResult.TOO_FEW_STATIONS
	for i: int in station_ids.size():
		if network.station_by_id(station_ids[i]) == null:
			return LineResult.UNKNOWN_STATION
		if i > 0 and station_ids[i] == station_ids[i - 1]:
			return LineResult.REPEATED_STATION
	last_blocked_leg = []
	for i: int in range(1, station_ids.size()):
		var a: int = station_ids[i - 1]
		var b: int = station_ids[i]
		if network.find_station_path(a, b).is_empty():
			last_blocked_leg = [a, b] as Array[int]
			return LineResult.NO_ROUTE
		if network.find_station_path(b, a).is_empty():
			last_blocked_leg = [b, a] as Array[int]
			return LineResult.NO_ROUTE
	return LineResult.OK


## Affecte un train à la ligne, posé dans sa première gare.
func add_train(line_id: int) -> int:
	if not lines.has(line_id):
		return LineResult.UNKNOWN_LINE
	if trains.size() >= max_trains():
		return LineResult.TOO_MANY_TRAINS
	var line: Line = lines[line_id]
	var first: RefCounted = network.station_by_id(line.station_ids[0])
	if first == null:
		return LineResult.UNKNOWN_STATION
	var train: Train = Train.new(_next_train_id, line_id, first.cell)
	if not dispatcher.try_reserve(train.id, [first.cell] as Array[Vector2i])["ok"]:
		return LineResult.STATION_FULL
	_next_train_id += 1
	train.route = line.station_ids.duplicate()
	train.dwell_left = params.dwell_ticks
	train.cargo = GoodsStock.new(0)
	_equip_wagons(train)
	trains[train.id] = train
	_handle_stop(train)
	return LineResult.OK


func level() -> int:
	return progression.level if progression != null else 1


## Nombre maximal de trains : un réglage `logistics.max_trains` (tests) l'emporte, puis la
## table des niveaux de `content.json`, puis la configuration.
func max_trains() -> int:
	if content == null:
		return params.max_trains
	if content.logistics.has("max_trains"):
		return content.logistics["max_trains"]
	return content.max_trains_for_level(level(), params.max_trains)


## Un wagon de la capacité définie dans `content.json` par produit débloqué (D-017 : pas
## encore d'écran de composition).
func _equip_wagons(train: Train) -> void:
	if content == null:
		return
	for good: String in content.unlocked_goods(level()):
		var wagon_id: String = content.wagon_for(good)
		if wagon_id != "":
			train.cargo.set_capacity(good, content.wagons[wagon_id]["capacity"])


## Appelé quand le niveau change : les trains reçoivent les wagons des nouveaux produits.
func apply_level() -> void:
	for id: int in trains:
		_equip_wagons(trains[id])


func clear_lines_and_trains() -> void:
	if logistics != null:
		for id: int in trains:
			for good: String in trains[id].cargo.goods():
				logistics.industry.record_loss(good, trains[id].cargo.total(good))
	lines.clear()
	trains.clear()
	dispatcher.clear()
	_set_deadlock([] as Array[int])


# --- Gardes appelés par le réseau ---------------------------------------------

## Un segment est verrouillé tant qu'un train roule dessus.
func is_edge_locked(a: Vector2i, b: Vector2i) -> bool:
	for id: int in trains:
		var train: Train = trains[id]
		if train.state == Train.State.RUNNING and train.seg + 1 < train.path.size():
			if network.graph.edge_key(train.path[train.seg], train.path[train.seg + 1]) == network.graph.edge_key(a, b):
				return true
	return false


func station_in_use(station_id: int) -> bool:
	for id: int in lines:
		if station_id in lines[id].station_ids:
			return true
	for id: int in trains:
		if station_id in trains[id].route:  # parcours pas encore mis à jour
			return true
	return false


# --- Pas de simulation --------------------------------------------------------

func step(tick: int) -> void:
	for id: int in trains:
		var train: Train = trains[id]
		train.prev_pos = train.pos
		match train.state:
			Train.State.DWELLING:
				train.dwell_left -= 1
				if train.dwell_left <= 0:
					_depart(train)
			Train.State.WAITING_ROUTE, Train.State.WAITING_CLEARANCE:
				train.retry_left -= 1
				if train.retry_left <= 0:
					_plan(train)
			Train.State.RUNNING:
				_advance(train, tick)
		_refresh_pos(train)
	_detect_deadlocks()


## Empreinte de l'état des trains (tests de déterminisme et, plus tard, de sauvegarde).
func state_checksum() -> int:
	var h: int = 1469598103934665603
	for id: int in trains:
		var t: Train = trains[id]
		for v: int in [t.id, t.line_id, t.state, t.stop_index, t.target_index, t.direction,
				t.dwell_left, t.retry_left, t.seg, t.progress_milli, t.path.size(), t.cell.x, t.cell.y]:
			h = (h ^ v) * 1099511628211
		if t.cargo != null:
			h = (h ^ t.cargo.checksum()) * 1099511628211
		h = (h ^ str(t.bookings_list()).hash()) * 1099511628211
	return (h ^ dispatcher.checksum()) * 1099511628211


func _depart(train: Train) -> void:
	if train.relocate:
		# Nouveau parcours sans la gare où il se trouve : il rejoint la première gare.
		train.relocate = false
		train.target_index = 0
		train.direction = 1
		_plan(train)
		return
	var next: int = train.stop_index + train.direction
	if next < 0 or next >= train.route.size():
		train.direction = -train.direction
		next = train.stop_index + train.direction
	train.target_index = next
	_plan(train)


## Cherche le trajet de `train.cell` jusqu'à la gare visée et le réserve en entier.
## Sans voie : le train attend (WAITING_ROUTE). Voie occupée ou quai plein : il attend
## (WAITING_CLEARANCE) sans rien retenir d'autre que sa case.
func _plan(train: Train) -> void:
	var target: RefCounted = network.station_by_id(train.route[train.target_index])
	var path: Array[Vector2i] = []
	if target != null:
		path = network.graph.find_path(train.cell, target.cell, -1 if train.at_station else train.heading)
	var only_here: Array[Vector2i] = [train.cell]
	if path.size() < 2:
		dispatcher.release_except(train.id, only_here)
		train.state = Train.State.WAITING_ROUTE
		train.retry_left = params.retry_ticks
		train.path = [] as Array[Vector2i]
		return
	var reservation: Dictionary = dispatcher.try_reserve(train.id, path)
	if not reservation["ok"]:
		dispatcher.release_except(train.id, only_here)
		train.state = Train.State.WAITING_CLEARANCE
		train.retry_left = params.retry_ticks
		train.wait_cell = reservation["cell"]
		train.blockers = reservation["blockers"]
		train.path = [] as Array[Vector2i]
		return
	dispatcher.release_except(train.id, path)  # cases d'une ancienne réservation, hors du nouveau trajet
	train.path = path
	train.cell_dist = _cumulative_distances(path)
	train.release_index = 0
	train.seg = 0
	train.progress_milli = 0
	train.heading = Dir.from_delta(path[1] - path[0])
	train.at_station = false
	train.blockers = [] as Array[int]
	train.wait_cell = Vector2i(-1, -1)
	train.state = Train.State.RUNNING


func _cumulative_distances(path: Array[Vector2i]) -> Array[int]:
	var distances: Array[int] = [0]
	for i: int in range(1, path.size()):
		distances.append(distances[i - 1] + Dir.segment_length_milli(Dir.from_delta(path[i] - path[i - 1])))
	return distances


## Libère les cases que la queue du train a quittées (longueur du train en `content.json`).
func _release_behind(train: Train) -> void:
	if train.seg >= train.cell_dist.size():
		return
	var head: int = train.cell_dist[train.seg] + train.progress_milli
	var length: int = content.logistic("train_length_milli", 1000) if content != null else 1000
	while train.release_index < train.path.size() - 1 and head >= train.cell_dist[train.release_index] + length:
		var cell: Vector2i = train.path[train.release_index]
		if not (cell in train.path.slice(train.release_index + 1)):  # case revisitée plus loin : on la garde
			dispatcher.release(train.id, cell)
		train.release_index += 1


func _cell_capacity(cell: Vector2i) -> int:
	if network.station_at(cell) == null:
		return 1
	return content.logistic("station_platforms", 1) if content != null else 1


func _advance(train: Train, tick: int) -> void:
	var remaining: int = params.speed_milli_per_tick
	while remaining > 0 and train.state == Train.State.RUNNING:
		var a: Vector2i = train.path[train.seg]
		var b: Vector2i = train.path[train.seg + 1]
		if train.progress_milli == 0 and not network.graph.has_edge(a, b):
			# Voie retirée devant le train (hors segment verrouillé) : on replanifie.
			train.cell = a
			_plan(train)
			continue
		var room: int = Dir.segment_length_milli(train.heading) - train.progress_milli
		if remaining < room:
			train.progress_milli += remaining
			_release_behind(train)
			return
		remaining -= room
		train.cell = b
		train.seg += 1
		train.progress_milli = 0
		if train.seg + 1 >= train.path.size():
			_arrive(train, tick)
			return
		train.heading = Dir.from_delta(train.path[train.seg + 1] - train.path[train.seg])
		_release_behind(train)


func _arrive(train: Train, tick: int) -> void:
	dispatcher.release_except(train.id, [train.cell] as Array[Vector2i])  # le train est entièrement en gare
	train.state = Train.State.DWELLING
	train.at_station = true
	train.path = [] as Array[Vector2i]
	train.seg = 0
	train.progress_milli = 0
	train.dwell_left = params.dwell_ticks
	train.stop_index = train.target_index
	var station_id: int = train.route[train.stop_index]
	_adopt_line_changes(train)
	_handle_stop(train)
	if progression != null:
		progression.record_trip()
	train_arrived.emit(train.id, station_id, tick)


## À l'arrêt, le train adopte la liste de gares de sa ligne si elle a changé : il reprend
## depuis la gare où il se trouve, ou rejoint la première gare si elle n'y figure plus.
func _adopt_line_changes(train: Train) -> void:
	var line: Line = lines.get(train.line_id)
	if line == null or train.route == line.station_ids:
		return
	var here: int = train.route[train.stop_index]
	train.route = line.station_ids.duplicate()
	var index: int = train.route.find(here)
	train.relocate = index < 0
	train.stop_index = maxi(index, 0)
	train.target_index = train.stop_index


## Manutention à l'arrêt : l'arrêt dure au moins `dwell_ticks`, plus si le volume l'exige.
func _handle_stop(train: Train) -> void:
	if logistics == null:
		return
	var station_id: int = -1 if train.relocate else train.route[train.stop_index]
	var handling: int = logistics.handle_stop(train, station_id, train.route)
	train.dwell_left = maxi(params.dwell_ticks, handling)


func _refresh_pos(train: Train) -> void:
	if train.state == Train.State.RUNNING and train.seg + 1 < train.path.size():
		var a: Vector2 = Vector2(train.path[train.seg]) + Vector2(0.5, 0.5)
		var b: Vector2 = Vector2(train.path[train.seg + 1]) + Vector2(0.5, 0.5)
		train.pos = a.lerp(b, float(train.progress_milli) / float(Dir.segment_length_milli(train.heading)))
	else:
		train.pos = Vector2(train.cell) + Vector2(0.5, 0.5)


# --- Interblocage -------------------------------------------------------------

## Un train est en interblocage si tous ceux qui le retiennent attendent eux-mêmes
## (de façon circulaire) : plus grand ensemble stable d'attentes, calculé par élimination.
func _detect_deadlocks() -> void:
	var stuck: Dictionary = {}
	for id: int in trains:
		var train: Train = trains[id]
		if train.state == Train.State.WAITING_CLEARANCE:
			train.blockers = _blockers_of(train)
			stuck[id] = true
	var changed: bool = true
	while changed:
		changed = false
		for id: int in stuck.keys():
			var blockers: Array[int] = trains[id].blockers
			var free_to_move: bool = blockers.is_empty()
			for blocker: int in blockers:
				if not stuck.has(blocker):
					free_to_move = true
			if free_to_move:
				stuck.erase(id)
				changed = true
	var ids: Array[int] = []
	for id: int in trains:
		if stuck.has(id):
			ids.append(id)
	_set_deadlock(ids)


func _blockers_of(train: Train) -> Array[int]:
	var result: Array[int] = []
	for id: int in dispatcher.holders(train.wait_cell):
		if id != train.id:
			result.append(id)
	return result


func _set_deadlock(ids: Array[int]) -> void:
	if ids == deadlocked:
		return
	deadlocked = ids
	deadlock_text = _deadlock_text(ids)
	deadlock_changed.emit(ids, deadlock_text)


func _deadlock_text(ids: Array[int]) -> String:
	if ids.is_empty():
		return ""
	var parts: PackedStringArray = []
	for id: int in ids:
		parts.append(wait_text(id))
	return "Interblocage : " + " ; ".join(parts) + ". Ajoutez un quai, une voie de croisement, ou retirez un train."


## Phrase décrivant ce qu'attend un train et pourquoi.
func wait_text(train_id: int) -> String:
	var train: Train = trains.get(train_id)
	if train == null or train.state != Train.State.WAITING_CLEARANCE:
		return ""
	var place: RefCounted = network.station_at(train.wait_cell)
	var where: String = place.station_name if place != null else "la voie en (%d, %d)" % [train.wait_cell.x, train.wait_cell.y]
	var who: PackedStringArray = []
	for blocker: int in train.blockers:
		who.append("Train %d" % blocker)
	if who.is_empty():
		return "Train %d attend %s, qui vient de se libérer : départ au prochain essai" % [train.id, where]
	return "Train %d attend %s, occupé par %s" % [train.id, where, ", ".join(who)]


# --- Sauvegarde ---------------------------------------------------------------

func to_dict() -> Dictionary:
	var line_list: Array = []
	for id: int in lines:
		line_list.append(lines[id].to_dict())
	var train_list: Array = []
	for id: int in trains:
		train_list.append(trains[id].to_dict())
	return {"lines": line_list, "trains": train_list, "dispatcher": dispatcher.to_dict(),
			"next_line_id": _next_line_id, "next_train_id": _next_train_id, "last_line_id": last_created_line_id}


func load_dict(data: Dictionary) -> void:
	lines.clear()
	trains.clear()
	for entry: Dictionary in data["lines"]:
		var stations: Array[int] = []
		for id: int in entry["stations"]:
			stations.append(id)
		lines[entry["id"]] = Line.new(entry["id"], stations)
	for entry: Dictionary in data["trains"]:
		var train: Train = Train.new(entry["id"], entry["line_id"], Vector2i(entry["cell"][0], entry["cell"][1]))
		train.state = entry["state"]
		train.stop_index = entry["stop_index"]
		train.target_index = entry["target_index"]
		train.direction = entry["direction"]
		train.dwell_left = entry["dwell_left"]
		train.retry_left = entry["retry_left"]
		train.at_station = entry["at_station"]
		train.heading = entry["heading"]
		train.path = []
		for c: Array in entry["path"]:
			train.path.append(Vector2i(c[0], c[1]))
		train.seg = entry["seg"]
		train.progress_milli = entry["progress"]
		train.cell_dist = []
		for d: int in entry["cell_dist"]:
			train.cell_dist.append(d)
		train.release_index = entry["release_index"]
		train.wait_cell = Vector2i(entry["wait_cell"][0], entry["wait_cell"][1])
		train.blockers = []
		for b: int in entry["blockers"]:
			train.blockers.append(b)
		train.cargo = GoodsStock.new(0)
		train.cargo.load_dict(entry["cargo"])
		# Sauvegardes antérieures : pas de parcours propre, celui de la ligne.
		train.route = []
		for id: int in entry.get("route", lines[train.line_id].station_ids if lines.has(train.line_id) else []):
			train.route.append(id)
		train.relocate = entry.get("relocate", false)
		train.bookings = {}
		for booking: Array in entry.get("bookings", []):
			if not train.bookings.has(booking[0]):
				train.bookings[booking[0]] = {}
			train.bookings[booking[0]][booking[1]] = booking[2]
		trains[train.id] = train
		_refresh_pos(train)
		train.prev_pos = train.pos
	dispatcher.load_dict(data["dispatcher"])
	_next_line_id = data["next_line_id"]
	_next_train_id = data["next_train_id"]
	last_created_line_id = data["last_line_id"]
	_set_deadlock([] as Array[int])
	_detect_deadlocks()
