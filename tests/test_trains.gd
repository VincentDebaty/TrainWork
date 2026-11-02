extends "res://tests/test_case.gd"

const GameSimulation = preload("res://src/sim/game_simulation.gd")
const SimParams = preload("res://src/sim/sim_params.gd")
const TrainSimulator = preload("res://src/sim/train_simulator.gd")
const Train = preload("res://src/sim/train.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const WorldMap = preload("res://src/core/world_map.gd")

const LR = TrainSimulator.LineResult

# Vitesse 2 cases/s, pas 0,2 s => 400 milli-cases par pas ; arrêt 3 s => 15 pas.


class World:
	var net: RailNetwork
	var sim: GameSimulation
	var arrivals: Array[Vector3i] = []  # (train, station, tick)


func _world(max_trains: int = 1) -> World:
	var w: World = World.new()
	w.net = RailNetwork.new(WorldMap.new(24, 24, 1, 1))
	w.sim = GameSimulation.new(SimParams.new(0.2, 2.0, 3.0, 1.0, max_trains), 25, w.net)
	w.sim.trains.train_arrived.connect(func(train: int, station: int, tick: int) -> void: w.arrivals.append(Vector3i(train, station, tick)))
	return w


## Gares sur une ligne droite y=5 : A en x=2, B en x=12, C en x=20. Retourne leurs ids.
func _straight(w: World) -> Array[int]:
	for x: int in [2, 12, 20]:
		w.net.place_station(Vector2i(x, 5), 0)
	for x: int in range(2, 20):
		w.net.place_edge(Vector2i(x, 5), Vector2i(x + 1, 5))
	return [w.net.station_at(Vector2i(2, 5)).id, w.net.station_at(Vector2i(12, 5)).id, w.net.station_at(Vector2i(20, 5)).id]


func _launch(w: World, ids: Array[int]) -> void:
	check_eq(w.sim.trains.create_line(ids), LR.OK, "ligne créée")
	check_eq(w.sim.trains.add_train(w.sim.trains.last_created_line_id), LR.OK, "train affecté")


func _run(w: World, ticks: int) -> void:
	for _i: int in ticks:
		w.sim._step()


func _stations_of(w: World) -> Array[int]:
	var result: Array[int] = []
	for a: Vector3i in w.arrivals:
		result.append(a.y)
	return result


func test_two_stations_back_and_forth() -> void:
	var w: World = _world()
	var s: Array[int] = _straight(w)
	_launch(w, [s[0], s[1]] as Array[int])
	_run(w, 400)
	var seq: Array[int] = _stations_of(w)
	check(seq.size() >= 6, "plusieurs trajets")
	for i: int in seq.size():
		check_eq(seq[i], s[1] if i % 2 == 0 else s[0], "arrêt %d alterne B, A, B, A…" % i)


func test_three_stations_visit_order_a_b_c_b_a() -> void:
	var w: World = _world()
	var s: Array[int] = _straight(w)
	_launch(w, [s[0], s[1], s[2]] as Array[int])
	_run(w, 1200)
	var expected: Array[int] = [s[1], s[2], s[1], s[0], s[1], s[2], s[1], s[0]]
	var seq: Array[int] = _stations_of(w)
	check(seq.size() >= expected.size(), "assez d'arrêts")
	for i: int in mini(expected.size(), seq.size()):
		check_eq(seq[i], expected[i], "arrêt %d" % i)


func test_exact_travel_time_and_dwell() -> void:
	var w: World = _world()
	var s: Array[int] = _straight(w)
	_launch(w, [s[0], s[1]] as Array[int])
	_run(w, 200)
	# Arrêt initial 15 pas, puis 10 cases à 0,4 case/pas = 25 pas : arrivée au pas 40.
	check_eq(w.arrivals[0].z, 40, "première arrivée au pas 40")
	# Arrêt de 15 pas, départ, 25 pas de route : prochaine arrivée au pas 80.
	check_eq(w.arrivals[1].z, 80, "retour : arrêt 15 pas + 25 pas de route")


func test_terminus_is_stable_without_jump_or_oscillation() -> void:
	var w: World = _world()
	var s: Array[int] = _straight(w)
	_launch(w, [s[0], s[1]] as Array[int])
	var train: Train = w.sim.trains.trains.values()[0]
	var max_step: float = 0.0
	var dwell_positions: Dictionary = {}
	var previous: Vector2 = train.pos
	for _i: int in 500:
		w.sim._step()
		max_step = maxf(max_step, train.pos.distance_to(previous))
		previous = train.pos
		if train.state == Train.State.DWELLING:
			dwell_positions[train.pos] = true
	check(max_step <= 0.4 + 0.0001, "jamais plus de 0,4 case par pas (obtenu %f)" % max_step)
	check_eq(dwell_positions.size(), 2, "à l'arrêt, uniquement deux positions : les centres de A et de B")
	check(dwell_positions.has(Vector2(2.5, 5.5)) and dwell_positions.has(Vector2(12.5, 5.5)), "arrêts exactement au centre des gares")


func test_train_never_moves_backwards_within_a_leg() -> void:
	var w: World = _world()
	var s: Array[int] = _straight(w)
	_launch(w, [s[0], s[2]] as Array[int])
	var train: Train = w.sim.trains.trains.values()[0]
	var last_x: float = train.pos.x
	var direction: float = 0.0
	for _i: int in 300:
		w.sim._step()
		if train.state == Train.State.RUNNING:
			var dx: float = train.pos.x - last_x
			if direction == 0.0 and absf(dx) > 0.0:
				direction = signf(dx)
			check(dx * direction >= -0.0001, "pas de recul en route (tick %d)" % w.sim.tick)
		else:
			direction = 0.0
		last_x = train.pos.x


func test_diagonal_and_curved_route() -> void:
	var w: World = _world()
	# A (3,3) -> diagonale jusqu'à (8,8) -> droite jusqu'à (14,8) = B.
	w.net.place_station(Vector2i(3, 3), 1)
	w.net.place_station(Vector2i(14, 8), 0)
	for i: int in range(3, 8):
		check_eq(w.net.place_edge(Vector2i(i, i), Vector2i(i + 1, i + 1)), RailNetwork.Result.OK, "diagonale %d" % i)
	for x: int in range(8, 14):
		check_eq(w.net.place_edge(Vector2i(x, 8), Vector2i(x + 1, 8)), RailNetwork.Result.OK, "droite %d" % x)
	_launch(w, [w.net.station_at(Vector2i(3, 3)).id, w.net.station_at(Vector2i(14, 8)).id] as Array[int])
	var train: Train = w.sim.trains.trains.values()[0]
	var max_step: float = 0.0
	var previous: Vector2 = train.pos
	for _i: int in 200:
		w.sim._step()
		max_step = maxf(max_step, train.pos.distance_to(previous))
		previous = train.pos
	check(w.arrivals.size() >= 2, "le trajet courbe est parcouru dans les deux sens")
	check(max_step <= 0.4 + 0.0001, "pas de saut dans la courbe (obtenu %f)" % max_step)


func test_line_validation() -> void:
	var w: World = _world()
	var s: Array[int] = _straight(w)
	var trains: TrainSimulator = w.sim.trains
	check_eq(trains.create_line([s[0]] as Array[int]), LR.TOO_FEW_STATIONS, "une seule gare")
	check_eq(trains.create_line([s[0], s[0]] as Array[int]), LR.REPEATED_STATION, "même gare deux fois de suite")
	check_eq(trains.create_line([s[0], 999] as Array[int]), LR.UNKNOWN_STATION, "gare inconnue")
	w.net.place_station(Vector2i(10, 15), 0)
	var isolated: int = w.net.station_at(Vector2i(10, 15)).id
	check_eq(trains.create_line([s[0], isolated] as Array[int]), LR.NO_ROUTE, "gare non reliée")
	check_eq(trains.add_train(42), LR.UNKNOWN_LINE, "ligne inconnue")
	_launch(w, [s[0], s[1]] as Array[int])
	check_eq(trains.create_line([s[1], s[2]] as Array[int]), LR.OK, "seconde ligne autorisée")
	check_eq(trains.add_train(trains.last_created_line_id), LR.TOO_MANY_TRAINS, "un seul train en M2")


func test_line_through_a_switch_and_impossible_reversal() -> void:
	var w: World = _world()
	w.net.place_station(Vector2i(1, 8), 0)
	w.net.place_station(Vector2i(8, 8), 0)
	w.net.place_station(Vector2i(8, 5), 0)
	for x: int in range(1, 8):
		w.net.place_edge(Vector2i(x, 8), Vector2i(x + 1, 8))
	for pair: Array in [[Vector2i(4, 8), Vector2i(5, 7)], [Vector2i(5, 7), Vector2i(6, 6)], [Vector2i(6, 6), Vector2i(7, 5)], [Vector2i(7, 5), Vector2i(8, 5)]]:
		w.net.place_edge(pair[0], pair[1])
	var a: int = w.net.station_at(Vector2i(1, 8)).id
	var b: int = w.net.station_at(Vector2i(8, 8)).id
	var c: int = w.net.station_at(Vector2i(8, 5)).id
	check_eq(w.sim.trains.create_line([a, c] as Array[int]), LR.OK, "A-C via l'aiguillage")
	check_eq(w.sim.trains.create_line([a, c, b] as Array[int]), LR.NO_ROUTE, "C-B exige un demi-tour hors gare : refusé")
	check_eq(w.sim.trains.last_blocked_leg, [c, b] as Array[int], "le tronçon bloquant est identifié")
	var message: String = w.sim.trains.line_error_message(LR.NO_ROUTE)
	check(message.contains("demi-tour") and message.contains("terminus ou une boucle"), "message : demi-tour hors gare")
	w.net.place_station(Vector2i(15, 15), 0)
	var isolated: int = w.net.station_at(Vector2i(15, 15)).id
	check_eq(w.sim.trains.create_line([a, isolated] as Array[int]), LR.NO_ROUTE, "gare isolée refusée")
	check(w.sim.trains.line_error_message(LR.NO_ROUTE).contains("pas reliées"), "message : gares non reliées")
	_launch(w, [a, c] as Array[int])
	_run(w, 400)
	check(w.arrivals.size() >= 4, "A-C-A-C parcouru")
	for i: int in w.arrivals.size():
		check_eq(w.arrivals[i].y, c if i % 2 == 0 else a, "alternance C, A")


func test_broken_track_waits_and_resumes() -> void:
	var w: World = _world()
	var s: Array[int] = _straight(w)
	_launch(w, [s[0], s[1]] as Array[int])
	var train: Train = w.sim.trains.trains.values()[0]
	_run(w, 20)  # en route, cases 2..~4
	check_eq(train.state, Train.State.RUNNING, "en route")
	check(not w.net.remove_edge(train.path[train.seg], train.path[train.seg + 1]), "segment occupé : suppression refusée")
	check(w.net.remove_edge(Vector2i(9, 5), Vector2i(10, 5)), "segment éloigné : suppression acceptée")
	_run(w, 100)
	check_eq(train.state, Train.State.WAITING_ROUTE, "le train attend devant la rupture")
	check_eq(w.arrivals.size(), 0, "aucune arrivée")
	var stopped_at: Vector2 = train.pos
	_run(w, 20)
	check_near_v(train.pos, stopped_at, "immobile pendant l'attente")
	w.net.place_edge(Vector2i(9, 5), Vector2i(10, 5))
	_run(w, 60)
	check(w.arrivals.size() >= 1, "le train repart après reconnexion")
	check_eq(w.arrivals[0].y, s[1], "et atteint la gare visée")


func test_station_in_use_cannot_be_removed() -> void:
	var w: World = _world()
	var s: Array[int] = _straight(w)
	check(w.net.remove_station(Vector2i(20, 5)), "gare libre supprimable")
	_launch(w, [s[0], s[1]] as Array[int])
	check(not w.net.remove_station(Vector2i(2, 5)), "gare d'une ligne protégée")
	w.sim.trains.clear_lines_and_trains()
	check(w.net.remove_station(Vector2i(2, 5)), "supprimable après retrait de la ligne")


func test_determinism_and_independence_from_frame_rate() -> void:
	var checksums: Array[int] = []
	for delta: float in [0.02, 0.1, 0.05]:
		var w: World = _world()
		var s: Array[int] = _straight(w)
		_launch(w, [s[0], s[1], s[2]] as Array[int])
		for _i: int in roundi(120.0 / delta):
			w.sim.advance(delta)
		checksums.append(w.sim.state_checksum())
	check_eq(checksums[0], checksums[1], "50 FPS = 10 FPS")
	check_eq(checksums[0], checksums[2], "50 FPS = 20 FPS")
	check(checksums[0] != 0, "checksum non trivial")


func test_interpolation_alpha_in_range() -> void:
	var w: World = _world()
	w.sim.advance(0.07)
	check(w.sim.alpha() > 0.3 and w.sim.alpha() < 0.4, "alpha = 0,07 / 0,2")
