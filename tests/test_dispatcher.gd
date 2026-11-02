extends "res://tests/test_case.gd"

const Content = preload("res://src/data/content.gd")
const Dispatcher = preload("res://src/sim/dispatcher.gd")
const GameSimulation = preload("res://src/sim/game_simulation.gd")
const SimParams = preload("res://src/sim/sim_params.gd")
const Train = preload("res://src/sim/train.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const WorldMap = preload("res://src/core/world_map.gd")

const LR = preload("res://src/sim/train_simulator.gd").LineResult


class World:
	var net: RailNetwork
	var sim: GameSimulation
	var arrivals: Dictionary = {}  # id de train -> nombre d'arrivées
	var violations: Array[String] = []


func _world(platforms: int = 2, max_trains: int = 2) -> World:
	var content: Content = Content.new()
	content.load_from()
	content.logistics["station_platforms"] = platforms
	content.logistics["max_trains"] = max_trains
	var w: World = World.new()
	w.net = RailNetwork.new(WorldMap.new(40, 40, 1, 1))
	w.sim = GameSimulation.new(SimParams.new(0.2, 2.0, 3.0, 1.0, 1), 25, w.net, content)
	w.sim.trains.train_arrived.connect(func(train: int, _station: int, _tick: int) -> void:
		w.arrivals[train] = w.arrivals.get(train, 0) + 1)
	return w


## Voie droite y=10 de x=6 à x=24 avec une gare à chaque bout : A (6,10) et B (24,10).
func _straight(w: World) -> Array[int]:
	w.net.place_station(Vector2i(6, 10), 0)
	w.net.place_station(Vector2i(24, 10), 0)
	for x: int in range(6, 24):
		w.net.place_edge(Vector2i(x, 10), Vector2i(x + 1, 10))
	return [w.net.station_at(Vector2i(6, 10)).id, w.net.station_at(Vector2i(24, 10)).id]


func _line_and_train(w: World, stations: Array[int]) -> Train:
	check_eq(w.sim.trains.create_line(stations), LR.OK, "ligne créée")
	check_eq(w.sim.trains.add_train(w.sim.trains.last_created_line_id), LR.OK, "train affecté")
	return w.sim.trains.trains[w.sim.trains.trains.keys().back()]


## Invariants de sécurité, vérifiés à chaque pas.
func _check_safety(w: World) -> void:
	var counts: Dictionary = {}
	var trains: Array = w.sim.trains.trains.values()
	for train: Train in trains:
		# Un train en marche tient la case vers laquelle il roule ; à l'arrêt, celle où il se trouve.
		var must_hold: Vector2i = train.path[train.seg + 1] if train.state == Train.State.RUNNING else train.cell
		if not w.sim.trains.dispatcher.holds(train.id, must_hold):
			w.violations.append("pas %d : train %d ne tient pas sa case %s" % [w.sim.tick, train.id, str(must_hold)])
		for cell: Vector2i in w.sim.trains.dispatcher.held_cells(train.id):
			counts[cell] = counts.get(cell, 0) + 1
	for cell: Vector2i in counts:
		if counts[cell] > w.sim.trains.dispatcher.capacity(cell):
			w.violations.append("pas %d : case %s tenue par %d trains (capacité %d)" % [
				w.sim.tick, str(cell), counts[cell], w.sim.trains.dispatcher.capacity(cell)])
	for i: int in trains.size():
		for j: int in range(i + 1, trains.size()):
			var a: Train = trains[i]
			var b: Train = trains[j]
			if a.pos.distance_to(b.pos) < 0.99 and not _share_a_station(w, a, b):
				w.violations.append("pas %d : trains %d et %d superposés (%f)" % [w.sim.tick, a.id, b.id, a.pos.distance_to(b.pos)])


## Deux trains peuvent se trouver tout près l'un de l'autre uniquement autour d'une même
## gare (quais distincts) : l'un y stationne, l'autre y entre ou en sort.
func _share_a_station(w: World, a: Train, b: Train) -> bool:
	for station: RefCounted in w.net.stations():
		var center: Vector2 = Vector2(station.cell) + Vector2(0.5, 0.5)
		if a.pos.distance_to(center) <= 1.0 and b.pos.distance_to(center) <= 1.0:
			return true
	return false


func _run_safe(w: World, ticks: int) -> void:
	for _i: int in ticks:
		w.sim._step()
		_check_safety(w)


func test_dispatcher_reservation_is_atomic_and_respects_capacity() -> void:
	var w: World = _world(2)
	_straight(w)
	var d: Dispatcher = w.sim.trains.dispatcher
	var path: Array[Vector2i] = [Vector2i(10, 10), Vector2i(11, 10), Vector2i(12, 10)]
	check(d.try_reserve(1, path)["ok"], "train 1 réserve")
	var refused: Dictionary = d.try_reserve(2, [Vector2i(9, 10), Vector2i(11, 10)] as Array[Vector2i])
	check(not refused["ok"], "train 2 refusé : une case est tenue")
	check_eq(refused["cell"], Vector2i(11, 10), "case refusée identifiée")
	check_eq(refused["blockers"], [1] as Array[int], "bloqueur identifié")
	check(not d.holds(2, Vector2i(9, 10)), "réservation atomique : rien de retenu en cas de refus")
	d.release(1, Vector2i(11, 10))
	check(d.try_reserve(2, [Vector2i(9, 10), Vector2i(11, 10)] as Array[Vector2i])["ok"], "libérée, elle devient disponible")
	d.release_all(2)
	check_eq(d.held_cells(2).size(), 0, "release_all")
	# Une gare accepte autant de trains que de quais.
	var station: Vector2i = Vector2i(6, 10)
	check_eq(d.capacity(station), 2, "gare à 2 quais")
	check(d.try_reserve(1, [station] as Array[Vector2i])["ok"] and d.try_reserve(2, [station] as Array[Vector2i])["ok"], "deux trains en gare")
	check(not d.try_reserve(3, [station] as Array[Vector2i])["ok"], "pas de troisième")


func test_same_direction_on_shared_track() -> void:
	var w: World = _world(2)
	var s: Array[int] = _straight(w)
	_line_and_train(w, [s[0], s[1]] as Array[int])
	# Deuxième train sur la même ligne : même gare de départ (2 quais).
	check_eq(w.sim.trains.add_train(w.sim.trains.last_created_line_id), LR.OK, "2e train sur la même ligne")
	_run_safe(w, 1500)
	check(w.violations.is_empty(), "aucune violation : %s" % str(w.violations.slice(0, 3)))
	for id: int in w.sim.trains.trains:
		check(w.arrivals.get(id, 0) >= 3, "train %d a fait au moins 3 trajets (%d)" % [id, w.arrivals.get(id, 0)])
	check(w.sim.trains.deadlocked.is_empty(), "pas d'interblocage")


func test_opposite_directions_cross_in_stations_with_two_platforms() -> void:
	var w: World = _world(2)
	var s: Array[int] = _straight(w)
	_line_and_train(w, [s[0], s[1]] as Array[int])  # train 1 part de A
	_line_and_train(w, [s[1], s[0]] as Array[int])  # train 2 part de B
	_run_safe(w, 1500)
	check(w.violations.is_empty(), "aucune violation : %s" % str(w.violations.slice(0, 3)))
	for id: int in w.sim.trains.trains:
		check(w.arrivals.get(id, 0) >= 3, "train %d circule en sens opposé (%d trajets)" % [id, w.arrivals.get(id, 0)])
	check(w.sim.trains.deadlocked.is_empty(), "le croisement en gare évite l'interblocage")


func test_face_to_face_without_crossing_is_safe_and_diagnosed() -> void:
	var w: World = _world(1)  # un seul quai par gare : aucun croisement possible
	var s: Array[int] = _straight(w)
	var t1: Train = _line_and_train(w, [s[0], s[1]] as Array[int])
	var t2: Train = _line_and_train(w, [s[1], s[0]] as Array[int])
	var texts: Array[String] = []
	w.sim.trains.deadlock_changed.connect(func(_ids: Array, text: String) -> void: texts.append(text))
	_run_safe(w, 400)
	check(w.violations.is_empty(), "aucune collision ni superposition : %s" % str(w.violations.slice(0, 3)))
	check_eq(t1.state, Train.State.WAITING_CLEARANCE, "train 1 n'est pas parti : il attend")
	check_eq(t2.state, Train.State.WAITING_CLEARANCE, "train 2 n'est pas parti : il attend")
	check_eq(t1.cell, Vector2i(6, 10), "train 1 toujours en gare A")
	check_eq(t2.cell, Vector2i(24, 10), "train 2 toujours en gare B")
	check_eq(t1.wait_cell, Vector2i(24, 10), "le quai de destination est vérifié AVANT le départ")
	check_eq(t1.blockers, [t2.id] as Array[int], "train 1 attend le train 2")
	check_eq(w.sim.trains.deadlocked, [t1.id, t2.id] as Array[int], "attente circulaire détectée")
	check(not texts.is_empty(), "l'interblocage est signalé")
	var text: String = w.sim.trains.deadlock_text
	check(text.begins_with("Interblocage") and text.contains("Train 1") and text.contains("Train 2") and text.contains("Gare"), "diagnostic compréhensible : %s" % text)
	check(w.arrivals.is_empty(), "personne n'est arrivé : aucun départ dangereux")
	# Le joueur retire les trains : plus d'interblocage.
	w.sim.trains.clear_lines_and_trains()
	check(w.sim.trains.deadlocked.is_empty() and w.sim.trains.deadlock_text == "", "diagnostic effacé après retrait")
	check_eq(w.sim.trains.dispatcher.held_cells(t1.id).size(), 0, "plus aucune réservation")


func test_destination_platform_blocks_departure_but_not_a_free_station() -> void:
	var w: World = _world(1)
	var s: Array[int] = _straight(w)
	var t1: Train = _line_and_train(w, [s[0], s[1]] as Array[int])
	_run_safe(w, 30)
	check_eq(t1.state, Train.State.RUNNING, "gare de destination libre : le train part")
	_run_safe(w, 60)
	check(w.arrivals.get(t1.id, 0) >= 1, "et il arrive")
	check(w.violations.is_empty(), "sans violation")


func test_station_full_refuses_a_second_train() -> void:
	var w: World = _world(1)
	var s: Array[int] = _straight(w)
	_line_and_train(w, [s[0], s[1]] as Array[int])
	check_eq(w.sim.trains.add_train(w.sim.trains.last_created_line_id), LR.STATION_FULL, "un seul quai : le second train est refusé")
	check_eq(w.sim.trains.trains.size(), 1, "un seul train")


func test_max_trains_comes_from_content() -> void:
	var w: World = _world(2, 1)
	var s: Array[int] = _straight(w)
	_line_and_train(w, [s[0], s[1]] as Array[int])
	check_eq(w.sim.trains.add_train(w.sim.trains.last_created_line_id), LR.TOO_MANY_TRAINS, "max_trains = 1 dans content")
	var w2: World = _world(2, 2)
	var s2: Array[int] = _straight(w2)
	_line_and_train(w2, [s2[0], s2[1]] as Array[int])
	check_eq(w2.sim.trains.add_train(w2.sim.trains.last_created_line_id), LR.OK, "max_trains = 2 dans content")


## Voie en Y : deux branches (S1 à l'ouest, S2 au nord-ouest) se rejoignent à un aiguillage
## puis suivent le même tronc jusqu'à S3. Deux lignes, un train chacune, tronc partagé.
func test_shared_trunk_through_a_switch() -> void:
	var w: World = _world(2)
	w.net.place_station(Vector2i(6, 10), 0)
	w.net.place_station(Vector2i(10, 7), 0)
	w.net.place_station(Vector2i(24, 10), 0)
	for x: int in range(14, 24):
		w.net.place_edge(Vector2i(x, 10), Vector2i(x + 1, 10))
	for x: int in range(6, 14):
		w.net.place_edge(Vector2i(x, 10), Vector2i(x + 1, 10))
	var arm: Array[Vector2i] = [Vector2i(10, 7), Vector2i(11, 7), Vector2i(12, 8), Vector2i(13, 9), Vector2i(14, 10)]
	for i: int in range(1, arm.size()):
		check_eq(w.net.place_edge(arm[i - 1], arm[i]), RailNetwork.Result.OK, "branche NO %d" % i)
	check(w.net.graph.is_switch(Vector2i(14, 10)), "aiguillage en (14,10)")
	var s1: int = w.net.station_at(Vector2i(6, 10)).id
	var s2: int = w.net.station_at(Vector2i(10, 7)).id
	var s3: int = w.net.station_at(Vector2i(24, 10)).id
	_line_and_train(w, [s1, s3] as Array[int])
	_line_and_train(w, [s2, s3] as Array[int])
	_run_safe(w, 2000)
	check(w.violations.is_empty(), "aucune violation sur le tronc partagé : %s" % str(w.violations.slice(0, 3)))
	for id: int in w.sim.trains.trains:
		check(w.arrivals.get(id, 0) >= 4, "train %d : %d trajets" % [id, w.arrivals.get(id, 0)])
	check(w.sim.trains.deadlocked.is_empty(), "pas d'interblocage")


func test_waiting_train_holds_only_its_own_cell() -> void:
	var w: World = _world(1)
	var s: Array[int] = _straight(w)
	var t1: Train = _line_and_train(w, [s[0], s[1]] as Array[int])
	var t2: Train = _line_and_train(w, [s[1], s[0]] as Array[int])
	_run_safe(w, 100)
	check_eq(w.sim.trains.dispatcher.held_cells(t1.id), [t1.cell] as Array[Vector2i], "train 1 ne retient que sa gare")
	check_eq(w.sim.trains.dispatcher.held_cells(t2.id), [t2.cell] as Array[Vector2i], "train 2 ne retient que sa gare")


func test_broken_rail_is_not_a_deadlock() -> void:
	var w: World = _world(2)
	var s: Array[int] = _straight(w)
	var t1: Train = _line_and_train(w, [s[0], s[1]] as Array[int])
	_run_safe(w, 30)
	w.net.remove_edge(Vector2i(20, 10), Vector2i(21, 10))
	_run_safe(w, 200)
	check_eq(t1.state, Train.State.WAITING_ROUTE, "voie coupée : le train attend une voie, ce n'est pas un interblocage")
	check(w.sim.trains.deadlocked.is_empty(), "pas d'interblocage signalé")
	check(w.violations.is_empty(), "toujours sans violation")
	w.net.place_edge(Vector2i(20, 10), Vector2i(21, 10))
	_run_safe(w, 300)
	check(w.arrivals.get(t1.id, 0) >= 1, "le train repart après reconnexion")


func test_determinism_with_two_trains_and_frame_rate_independence() -> void:
	var sums: Array[int] = []
	for delta: float in [0.02, 0.1, 0.05]:
		var w: World = _world(2)
		var s: Array[int] = _straight(w)
		_line_and_train(w, [s[0], s[1]] as Array[int])
		_line_and_train(w, [s[1], s[0]] as Array[int])
		for _i: int in roundi(180.0 / delta):
			w.sim.advance(delta)
		sums.append(w.sim.state_checksum())
	check_eq(sums[0], sums[1], "50 FPS = 10 FPS")
	check_eq(sums[0], sums[2], "50 FPS = 20 FPS")
