extends "res://tests/test_case.gd"

const RailNetwork = preload("res://src/rail/rail_network.gd")
const WorldMap = preload("res://src/core/world_map.gd")
const Terrain = preload("res://src/core/terrain.gd")
const Dir = preload("res://src/rail/direction.gd")

const R = RailNetwork.Result


func _network() -> RailNetwork:
	return RailNetwork.new(WorldMap.new(16, 16, 1, 1))  # tout en plaine


func _lay_line(net: RailNetwork, y: int, x0: int, x1: int) -> void:
	for x: int in range(x0, x1):
		net.place_edge(Vector2i(x, y), Vector2i(x + 1, y))


func test_basic_placement_and_rejections() -> void:
	var net: RailNetwork = _network()
	check_eq(net.place_edge(Vector2i(2, 2), Vector2i(3, 2)), R.OK, "pose simple")
	check_eq(net.place_edge(Vector2i(3, 2), Vector2i(2, 2)), R.ALREADY_EXISTS, "doublon")
	check_eq(net.place_edge(Vector2i(2, 2), Vector2i(4, 2)), R.NOT_ADJACENT, "non voisin")
	check_eq(net.place_edge(Vector2i(15, 2), Vector2i(16, 2)), R.OUT_OF_BOUNDS, "hors carte")
	check_eq(net.graph.edge_count(), 1, "un seul segment posé")


func test_water_blocks_rails_and_stations() -> void:
	var net: RailNetwork = _network()
	net.map.set_terrain(Vector2i(5, 5), Terrain.Type.WATER)
	check_eq(net.place_edge(Vector2i(4, 5), Vector2i(5, 5)), R.BLOCKED_TERRAIN, "rail sur l'eau")
	check_eq(net.place_station(Vector2i(5, 5), 0), R.BLOCKED_TERRAIN, "gare sur l'eau")


func test_diagonal_crossing_refused() -> void:
	var net: RailNetwork = _network()
	check_eq(net.place_edge(Vector2i(2, 2), Vector2i(3, 3)), R.OK, "première diagonale")
	check_eq(net.place_edge(Vector2i(3, 2), Vector2i(2, 3)), R.CROSSING, "diagonale croisée")
	check_eq(net.place_edge(Vector2i(3, 2), Vector2i(4, 3)), R.OK, "diagonale parallèle")


func test_sharp_turn_refused_but_gentle_turn_ok() -> void:
	var net: RailNetwork = _network()
	net.place_edge(Vector2i(3, 3), Vector2i(4, 3))
	check_eq(net.place_edge(Vector2i(4, 3), Vector2i(4, 4)), R.SHARP_TURN, "virage à 90°")
	check_eq(net.place_edge(Vector2i(4, 3), Vector2i(5, 4)), R.OK, "virage à 45°")
	check_eq(net.place_edge(Vector2i(4, 3), Vector2i(3, 2)), R.OK, "autre côté : embranchement 45° (aiguillage)")
	check(net.graph.is_switch(Vector2i(4, 3)), "aiguillage automatique")
	# T franc à 90° refusé : le segment perpendiculaire n'a aucun partenaire.
	check_eq(net.place_edge(Vector2i(3, 3), Vector2i(3, 4)), R.SHARP_TURN, "T à 90° refusé")


func test_station_axis_constraints() -> void:
	var net: RailNetwork = _network()
	check_eq(net.place_station(Vector2i(4, 4), 0), R.OK, "gare axe 0")
	check_eq(net.place_station(Vector2i(4, 4), 0), R.STATION_EXISTS, "case occupée")
	check_eq(net.place_station(Vector2i(6, 6), 7), R.BAD_ORIENTATION, "orientation invalide")
	check_eq(net.place_edge(Vector2i(4, 4), Vector2i(5, 4)), R.OK, "raccord sur l'axe (direction 0)")
	check_eq(net.place_edge(Vector2i(4, 4), Vector2i(3, 4)), R.OK, "raccord sur l'axe (direction 4)")
	check_eq(net.place_edge(Vector2i(4, 4), Vector2i(4, 5)), R.STATION_AXIS, "raccord hors axe")
	check_eq(net.place_edge(Vector2i(4, 4), Vector2i(5, 5)), R.STATION_AXIS, "diagonale hors axe")


func test_station_cannot_be_placed_on_crossing_rails() -> void:
	var net: RailNetwork = _network()
	_lay_line(net, 4, 2, 6)
	check_eq(net.place_station(Vector2i(4, 4), 1), R.STATION_AXIS, "voie existante hors axe")
	check_eq(net.place_station(Vector2i(4, 4), 0), R.OK, "voie existante sur l'axe")
	check(net.remove_station(Vector2i(4, 4)), "suppression de gare")
	check(net.graph.has_edge(Vector2i(4, 4), Vector2i(5, 4)), "les rails restent")


func test_stations_have_stable_ids() -> void:
	var net: RailNetwork = _network()
	net.place_station(Vector2i(1, 1), 0)
	net.place_station(Vector2i(8, 8), 2)
	var first: int = net.station_at(Vector2i(1, 1)).id
	var second: int = net.station_at(Vector2i(8, 8)).id
	check(first != second, "ids distincts")
	net.remove_station(Vector2i(1, 1))
	net.place_station(Vector2i(1, 1), 0)
	check(net.station_at(Vector2i(1, 1)).id > second, "id jamais réutilisé")


func test_station_to_station_path_break_and_reconnect() -> void:
	var net: RailNetwork = _network()
	net.place_station(Vector2i(2, 5), 0)
	net.place_station(Vector2i(9, 5), 0)
	_lay_line(net, 5, 2, 9)
	var a: int = net.station_at(Vector2i(2, 5)).id
	var b: int = net.station_at(Vector2i(9, 5)).id
	check_eq(net.find_station_path(a, b).size(), 8, "voie continue entre deux gares")
	net.remove_edge(Vector2i(5, 5), Vector2i(6, 5))
	check_eq(net.find_station_path(a, b).size(), 0, "rupture")
	net.place_edge(Vector2i(5, 5), Vector2i(6, 5))
	check_eq(net.find_station_path(a, b).size(), 8, "reconnexion")


func test_switch_gives_two_destinations() -> void:
	var net: RailNetwork = _network()
	net.place_station(Vector2i(1, 8), 0)
	net.place_station(Vector2i(8, 8), 0)
	net.place_station(Vector2i(8, 5), 0)
	_lay_line(net, 8, 1, 8)
	# Branche : (4,8) -> (5,7) -> (6,6) -> (7,5) -> (8,5), en virages de 45°.
	for pair: Array in [[Vector2i(4, 8), Vector2i(5, 7)], [Vector2i(5, 7), Vector2i(6, 6)], [Vector2i(6, 6), Vector2i(7, 5)], [Vector2i(7, 5), Vector2i(8, 5)]]:
		check_eq(net.place_edge(pair[0], pair[1]), R.OK, "branche %s" % str(pair))
	check(net.graph.is_switch(Vector2i(4, 8)), "aiguillage en (4,8)")
	var origin: int = net.station_at(Vector2i(1, 8)).id
	check(net.find_station_path(origin, net.station_at(Vector2i(8, 8)).id).size() > 0, "destination tronc")
	check(net.find_station_path(origin, net.station_at(Vector2i(8, 5)).id).size() > 0, "destination branche")


func test_simulation_does_not_modify_network() -> void:
	var net: RailNetwork = _network()
	net.place_edge(Vector2i(3, 3), Vector2i(4, 3))
	var before_edges: int = net.graph.edge_count()
	var before_id: int = net.graph.next_id()
	var count: Array = [0]
	net.changed.connect(func() -> void: count[0] += 1)
	var plan: Array[Vector4i] = [
		Dir.pair(Vector2i(4, 3), Vector2i(5, 3)),
		Dir.pair(Vector2i(5, 3), Vector2i(5, 4)),  # virage à 90° : refusé
		Dir.pair(Vector2i(5, 3), Vector2i(6, 4)),
	]
	var results: Array[int] = net.simulate_edges(plan)
	check_eq(results, [R.OK, R.SHARP_TURN, R.OK] as Array[int], "résultats de l'aperçu")
	check_eq(net.graph.edge_count(), before_edges, "réseau inchangé")
	check_eq(net.graph.next_id(), before_id, "compteur d'ids restauré")
	check_eq(count[0], 0, "pas de signal changed")


func test_place_edges_reports_and_emits_once() -> void:
	var net: RailNetwork = _network()
	var count: Array = [0]
	net.changed.connect(func() -> void: count[0] += 1)
	var plan: Array[Vector4i] = [
		Dir.pair(Vector2i(2, 2), Vector2i(3, 2)),
		Dir.pair(Vector2i(3, 2), Vector2i(3, 3)),  # 90° refusé
		Dir.pair(Vector2i(3, 2), Vector2i(4, 2)),
		Dir.pair(Vector2i(2, 2), Vector2i(3, 2)),  # doublon : ignoré
	]
	var report: Dictionary = net.place_edges(plan)
	check_eq(report["placed"], 2, "deux segments posés")
	check_eq(report["refused"].get(R.SHARP_TURN, 0), 1, "un virage refusé")
	check_eq(report["refused"].size(), 1, "doublon non compté")
	check_eq(count[0], 1, "un seul signal")


func test_remove_edges_at_cell() -> void:
	var net: RailNetwork = _network()
	_lay_line(net, 3, 1, 5)
	check_eq(net.remove_edges_at(Vector2i(3, 3)), 2, "deux segments retirés")
	check(not net.graph.is_connected_cells(Vector2i(1, 3), Vector2i(5, 3)), "voie coupée")
	check_eq(net.remove_edges_at(Vector2i(10, 10)), 0, "case vide")
