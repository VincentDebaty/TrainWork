extends Node
## Outils de construction : traduit les gestes de la caméra en commandes sur le
## RailNetwork. Pas de logique de règles ici (elles sont dans RailNetwork) : il
## calcule l'aperçu, valide au relâchement et rapporte les refus à l'utilisateur.

signal mode_changed(mode: int)
signal preview_changed
signal message(text: String)

enum Mode { NAVIGATE, RAIL, STATION, ERASE, LINE }

const Dir = preload("res://src/rail/direction.gd")
const RailDragPath = preload("res://src/rail/rail_drag_path.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const RailPlanner = preload("res://src/rail/rail_planner.gd")
const TrainSimulator = preload("res://src/sim/train_simulator.gd")
const Construction = preload("res://src/sim/construction.gd")

const MAX_UNDO: int = 30

var mode: int = Mode.NAVIGATE
var station_orientation: int = 0
## Aperçu du tracé en cours : segments (Vector4i) et résultat de pose de chacun.
var preview_edges: Array[Vector4i] = []
var preview_results: Array[int] = []
## Coût (milli-pièces) du tracé en cours, 0 hors tracé ou si la construction est gratuite.
var preview_cost_milli: int = 0
## Gares choisies (dans l'ordre) pour la ligne en préparation.
var pending_stations: Array[int] = []
## Dernière case choisie en mode Rails : point de départ du prochain tracé.
var head: Vector2i = Vector2i(-1, -1)
var has_head: bool = false

var _network: RailNetwork
var _trains: TrainSimulator
## Coûts de construction (null : construction gratuite, tests).
var _construction: Construction = null
var _projection: RefCounted
var _camera: Camera2D
var _drag: RailDragPath = RailDragPath.new()
var _planner: RailPlanner = RailPlanner.new()
var _undo: Array[Dictionary] = []
var _dragging: bool = false


func setup(network: RailNetwork, projection: RefCounted, camera: Camera2D, trains: TrainSimulator = null, construction: Construction = null) -> void:
	_network = network
	_trains = trains
	_construction = construction
	_projection = projection
	_camera = camera
	camera.pointer_pressed.connect(_on_pressed)
	camera.pointer_dragged.connect(_on_dragged)
	camera.pointer_released.connect(_on_released)
	camera.pointer_cancelled.connect(_cancel_drag)
	camera.world_tapped.connect(_on_tapped)
	set_mode(Mode.NAVIGATE)


func set_mode(new_mode: int) -> void:
	mode = new_mode
	if mode != Mode.LINE:
		_clear_pending()
	elif pending_stations.is_empty() and _trains != null and _trains.lines.size() == 1:
		# Une seule ligne : on la charge pour la voir et la modifier.
		pending_stations = _trains.lines.values()[0].station_ids.duplicate()
		preview_changed.emit()
		message.emit("Ligne actuelle affichée : touchez une gare pour l'ajouter à la fin, la dernière pour la retirer, puis Lancer.")
	_set_head(false, Vector2i(-1, -1))
	_cancel_drag()
	_camera.single_finger_pan = (mode == Mode.NAVIGATE)
	mode_changed.emit(mode)


func rotate_station_orientation() -> void:
	station_orientation = (station_orientation + 1) % 4


func orientation_name() -> String:
	return Dir.AXIS_NAMES[station_orientation]


func _cell_at(world: Vector2) -> Vector2i:
	return _projection.world_to_cell(world)


func _on_pressed(world: Vector2) -> void:
	if mode != Mode.RAIL and mode != Mode.ERASE:
		return
	var cell: Vector2i = _cell_at(world)
	if not _network.map.in_bounds(cell):
		return
	_dragging = true
	_drag.begin(cell)
	_refresh_preview()


func _on_dragged(world: Vector2) -> void:
	if not _dragging:
		return
	var cell: Vector2i = _cell_at(world)
	if _network.map.in_bounds(cell):
		_drag.extend_to(cell)
		_refresh_preview()


func _on_released(_world: Vector2) -> void:
	if not _dragging:
		return
	var edges: Array[Vector4i] = _drag.edges()
	_cancel_drag()
	if edges.is_empty():
		return
	if mode == Mode.RAIL:
		_commit_rails(edges)
	elif mode == Mode.ERASE:
		_commit_erase(edges)


func _on_tapped(world: Vector2) -> void:
	var cell: Vector2i = _cell_at(world)
	if mode == Mode.LINE:
		_tap_line_station(cell)
	elif mode == Mode.RAIL:
		_tap_rail(cell)
	elif mode == Mode.STATION:
		var result: int = _construction.place_station(cell, station_orientation) if _construction != null else _network.place_station(cell, station_orientation)
		message.emit("Gare posée." if result == RailNetwork.Result.OK else RailNetwork.result_text(result))
	elif mode == Mode.ERASE and _network.map.in_bounds(cell):
		if (_construction.remove_station(cell) if _construction != null else _network.remove_station(cell)):
			message.emit("Gare supprimée.")
		elif _network.station_at(cell) != null:
			message.emit("Gare utilisée par une ligne : retirez la ligne d'abord.")
		else:
			var around: Array[Vector4i] = []
			for n: Vector2i in _network.graph.neighbors(cell):
				around.append(Dir.pair(cell, n))
			if (_construction.remove_edges_at(cell) if _construction != null else _network.remove_edges_at(cell)) > 0:
				_record_undo([] as Array[Vector4i], _missing(around))
				message.emit("Voies supprimées.")


## Pose automatique au toucher : le rail se raccorde selon les voies voisines.
func _tap_rail(cell: Vector2i) -> void:
	var plan: Dictionary = _planner.plan_tap(_network, cell, head, has_head)
	var kind: int = plan["kind"]
	if kind == RailPlanner.Kind.FAIL:
		message.emit(plan["message"])
		return
	if kind == RailPlanner.Kind.ROUND:
		var old_edge: Vector4i = plan["replace"][0]
		var new_edge: Vector4i = plan["replace"][1]
		var result: int = _network.replace_edge(Vector2i(old_edge.x, old_edge.y), Vector2i(old_edge.z, old_edge.w),
				Vector2i(new_edge.x, new_edge.y), Vector2i(new_edge.z, new_edge.w))
		if result != RailNetwork.Result.OK:
			message.emit(RailNetwork.result_text(result))
			return
		_record_undo([new_edge] as Array[Vector4i], [old_edge] as Array[Vector4i])
	elif kind == RailPlanner.Kind.CONNECT or kind == RailPlanner.Kind.ROUTE:
		var report: Dictionary = _place_edges(plan["edges"])
		if report["insufficient"]:
			message.emit(_funds_text(report["needed"]))
			return
		_record_undo(report["placed_edges"], [] as Array[Vector4i])
		if report["placed"] == 0:
			message.emit("Rien à poser ici.")
			return
	if plan["message"] != "":
		message.emit(plan["message"])
	_set_head(true, plan["head"])


func _set_head(active: bool, cell: Vector2i) -> void:
	if has_head == active and head == cell:
		return
	has_head = active
	head = cell
	preview_changed.emit()


## Mémorise une action sur les segments : `added` (à retirer) et `removed` (à rétablir).
func _record_undo(added: Array[Vector4i], removed: Array[Vector4i]) -> void:
	if added.is_empty() and removed.is_empty():
		return
	_undo.append({"added": added, "removed": removed})
	if _undo.size() > MAX_UNDO:
		_undo.pop_front()


## Segments de `edges` qui n'existent plus dans le réseau.
func _missing(edges: Array[Vector4i]) -> Array[Vector4i]:
	var result: Array[Vector4i] = []
	for e: Vector4i in edges:
		if not _network.graph.has_edge(Vector2i(e.x, e.y), Vector2i(e.z, e.w)):
			result.append(e)
	return result


func undo() -> void:
	if _undo.is_empty():
		message.emit("Rien à annuler.")
		return
	var action: Dictionary = _undo.pop_back()
	var blocked: int = 0
	if _construction != null:
		blocked = _construction.undo_added(action["added"])
		if not action["removed"].is_empty() and not _construction.undo_removed(action["removed"]):
			_undo.append(action)
			message.emit("Annulation impossible : pièces insuffisantes pour rembourser le retrait.")
			return
	else:
		for e: Vector4i in action["added"]:
			if not _network.remove_edge(Vector2i(e.x, e.y), Vector2i(e.z, e.w)):
				blocked += 1
		for e: Vector4i in action["removed"]:
			_network.place_edge(Vector2i(e.x, e.y), Vector2i(e.z, e.w))
	_set_head(false, Vector2i(-1, -1))
	message.emit("Action annulée." if blocked == 0 else "Annulation partielle : voie occupée par un train.")


## Ajoute la gare tapée à la ligne en préparation ; retaper la dernière la retire.
func _tap_line_station(cell: Vector2i) -> void:
	var station: RefCounted = _network.station_at(cell)
	if station == null:
		return
	if not pending_stations.is_empty() and pending_stations.back() == station.id:
		pending_stations.pop_back()
	else:
		pending_stations.append(station.id)
	preview_changed.emit()


func clear_pending() -> void:
	_clear_pending()


## Crée la ligne choisie et lui affecte un train. Si une ligne identique existe déjà,
## le nouveau train la rejoint (deux trains sur la même ligne).
func launch_line() -> void:
	if _trains == null:
		return
	var existing: int = _find_line(pending_stations)
	var line_id: int = existing
	if existing != 0 and _trains.trains.size() >= _trains.max_trains():
		message.emit("Ligne inchangée : elle dessert déjà ces gares, dans cet ordre.")
		return
	# Plus de train disponible et une seule ligne : on la modifie (appliqué au prochain arrêt).
	if existing == 0 and _trains.trains.size() >= _trains.max_trains() and _trains.lines.size() == 1:
		var updated: int = _trains.update_line(_trains.lines.keys()[0], pending_stations)
		if updated == TrainSimulator.LineResult.OK:
			message.emit("Ligne modifiée : le train suivra le nouveau parcours après son prochain arrêt.")
			_clear_pending()
		else:
			message.emit(_trains.line_error_message(updated))
		return
	if existing == 0:
		var created: int = _trains.create_line(pending_stations)
		if created != TrainSimulator.LineResult.OK:
			message.emit(_trains.line_error_message(created))
			return
		line_id = _trains.last_created_line_id
	var result: int = _trains.add_train(line_id)
	if result != TrainSimulator.LineResult.OK:
		if existing == 0:
			_trains.lines.erase(line_id)
		if result == TrainSimulator.LineResult.TOO_MANY_TRAINS:
			message.emit("Nombre maximal de trains atteint : retirez une ligne avant d'en créer une autre.")
		else:
			message.emit(TrainSimulator.line_result_text(result))
		return
	message.emit("Train affecté à la ligne existante." if existing != 0 else "Ligne créée, train en route.")
	_clear_pending()


func _find_line(station_ids: Array[int]) -> int:
	for id: int in _trains.lines:
		if _trains.lines[id].station_ids == station_ids:
			return id
	return 0


func remove_all_lines() -> void:
	if _trains != null:
		_trains.clear_lines_and_trains()
		message.emit("Lignes et trains retirés.")


func _clear_pending() -> void:
	if not pending_stations.is_empty():
		pending_stations.clear()
		preview_changed.emit()


func _commit_rails(edges: Array[Vector4i]) -> void:
	var report: Dictionary = _place_edges(edges)
	if report["insufficient"]:
		message.emit(_funds_text(report["needed"]))
		return
	_record_undo(report["placed_edges"], [] as Array[Vector4i])
	var refused: Dictionary = report["refused"]
	if refused.is_empty():
		if report["placed"] > 0:
			message.emit("%d segment(s) posé(s)." % report["placed"])
		return
	var reasons: PackedStringArray = []
	for reason: int in refused:
		reasons.append("%s (%d)" % [RailNetwork.result_text(reason), refused[reason]])
	message.emit("%d posé(s), refusé(s) : %s" % [report["placed"], ", ".join(reasons)])


func _place_edges(edges: Array[Vector4i]) -> Dictionary:
	if _construction != null:
		return _construction.place_edges(edges)
	var report: Dictionary = _network.place_edges(edges)
	report["insufficient"] = false
	report["needed"] = 0
	return report


func _remove_edge(a: Vector2i, b: Vector2i) -> bool:
	return _construction.remove_edge(a, b) if _construction != null else _network.remove_edge(a, b)


func _funds_text(needed_milli: int) -> String:
	return "Pièces insuffisantes : il faut %.0f, vous avez %.0f." % [needed_milli / 1000.0, _construction.economy.wallet_milli / 1000.0]


func _commit_erase(edges: Array[Vector4i]) -> void:
	var removed: int = 0
	var removed_edges: Array[Vector4i] = []
	for e: Vector4i in edges:
		if _remove_edge(Vector2i(e.x, e.y), Vector2i(e.z, e.w)):
			removed += 1
			removed_edges.append(e)
	_record_undo([] as Array[Vector4i], removed_edges)
	if removed > 0:
		message.emit("%d segment(s) supprimé(s)." % removed)


func _refresh_preview() -> void:
	preview_edges = _drag.edges()
	if mode == Mode.RAIL:
		preview_results = _network.simulate_edges(preview_edges)
		preview_cost_milli = _construction.quote_edges(preview_edges) if _construction != null else 0
	else:
		preview_results = []
		preview_cost_milli = 0
	preview_changed.emit()


func _cancel_drag() -> void:
	var had_preview: bool = _dragging or not preview_edges.is_empty()
	_dragging = false
	_drag.clear()
	preview_edges = []
	preview_results = []
	preview_cost_milli = 0
	if had_preview:
		preview_changed.emit()
