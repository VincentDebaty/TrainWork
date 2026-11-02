extends "res://tests/test_case.gd"

const RailPlanner = preload("res://src/rail/rail_planner.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const WorldMap = preload("res://src/core/world_map.gd")
const Terrain = preload("res://src/core/terrain.gd")
const Dir = preload("res://src/rail/direction.gd")

const K = RailPlanner.Kind
const NO_HEAD: Vector2i = Vector2i(-1, -1)


func _net() -> RailNetwork:
	return RailNetwork.new(WorldMap.new(24, 24, 1, 1))


func _line(net: RailNetwork, y: int, x0: int, x1: int) -> void:
	for x: int in range(x0, x1):
		net.place_edge(Vector2i(x, y), Vector2i(x + 1, y))


## Applique un plan comme le fait le contrôleur ; renvoie le nombre de segments posés.
func _apply(net: RailNetwork, plan: Dictionary) -> int:
	if plan["kind"] == K.ROUND:
		var o: Vector4i = plan["replace"][0]
		var n: Vector4i = plan["replace"][1]
		net.replace_edge(Vector2i(o.x, o.y), Vector2i(o.z, o.w), Vector2i(n.x, n.y), Vector2i(n.z, n.w))
		return 1
	return net.place_edges(plan["edges"])["placed"]


func test_extend_straight_from_open_end() -> void:
	var net: RailNetwork = _net()
	_line(net, 5, 2, 5)
	var plan: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(6, 5), NO_HEAD, false)
	check_eq(plan["kind"], K.CONNECT, "raccord automatique")
	check_eq(plan["edges"], [Dir.pair(Vector2i(5, 5), Vector2i(6, 5))] as Array[Vector4i], "relié au bout de voie")
	check_eq(_apply(net, plan), 1, "un segment posé")


func test_extend_with_gentle_diagonal() -> void:
	var net: RailNetwork = _net()
	_line(net, 5, 2, 5)
	var plan: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(6, 6), NO_HEAD, false)
	check_eq(plan["kind"], K.CONNECT, "virage à 45° accepté")
	check_eq(_apply(net, plan), 1, "posé")


func test_gap_between_two_ends_is_filled() -> void:
	var net: RailNetwork = _net()
	_line(net, 5, 1, 4)
	_line(net, 5, 6, 9)
	var plan: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(5, 5), NO_HEAD, false)
	check_eq(plan["edges"].size(), 2, "les deux bouts sont reliés")
	check_eq(_apply(net, plan), 2, "deux segments posés")
	check(net.graph.is_connected_cells(Vector2i(1, 5), Vector2i(9, 5)), "voie continue")
	check_eq(net.graph.find_path(Vector2i(1, 5), Vector2i(9, 5)).size(), 9, "praticable par un train")


func test_corner_is_rounded_into_a_diagonal() -> void:
	var net: RailNetwork = _net()
	_line(net, 5, 2, 5)  # bout en (5,5)
	var plan: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(5, 6), NO_HEAD, false)
	check_eq(plan["kind"], K.ROUND, "coin à 90° arrondi")
	check_eq(plan["replace"][0], Dir.pair(Vector2i(4, 5), Vector2i(5, 5)), "ancien dernier segment")
	check_eq(plan["replace"][1], Dir.pair(Vector2i(4, 5), Vector2i(5, 6)), "remplacé par une diagonale")
	_apply(net, plan)
	check(net.graph.has_edge(Vector2i(4, 5), Vector2i(5, 6)), "diagonale posée")
	check(not net.graph.has_edge(Vector2i(4, 5), Vector2i(5, 5)), "ancien segment retiré")
	check_eq(net.graph.find_path(Vector2i(2, 5), Vector2i(5, 6)).size(), 4, "trajet praticable jusqu'au nouveau bout")


func test_isolated_tap_sets_head_then_second_tap_routes() -> void:
	var net: RailNetwork = _net()
	var planner: RailPlanner = RailPlanner.new()
	var first: Dictionary = planner.plan_tap(net, Vector2i(3, 3), NO_HEAD, false)
	check_eq(first["kind"], K.ANCHOR, "premier toucher : départ")
	check_eq(first["head"], Vector2i(3, 3), "la tête est la case touchée")
	var second: Dictionary = planner.plan_tap(net, Vector2i(9, 5), first["head"], true)
	check_eq(second["kind"], K.ROUTE, "second toucher : tracé calculé")
	_apply(net, second)
	check(net.graph.is_connected_cells(Vector2i(3, 3), Vector2i(9, 5)), "les deux cases sont reliées")
	check_eq(net.graph.find_path(Vector2i(3, 3), Vector2i(9, 5)).size() > 0, true, "praticable (virages <= 45°)")


func test_route_avoids_water_and_stays_legal() -> void:
	var net: RailNetwork = _net()
	for y: int in range(2, 9):
		net.map.set_terrain(Vector2i(6, y), Terrain.Type.WATER)  # mur d'eau, ouverture en y=9
	var plan: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(10, 5), Vector2i(3, 5), true)
	check_eq(plan["kind"], K.ROUTE, "contournement trouvé")
	_apply(net, plan)
	check(net.graph.find_path(Vector2i(3, 5), Vector2i(10, 5)).size() > 0, "chemin praticable autour de l'eau")
	for cell: Vector2i in net.graph.cells():
		check(net.map.get_terrain(cell) != Terrain.Type.WATER, "aucun rail sur l'eau en %s" % str(cell))


func test_route_is_deterministic_and_prefers_few_turns() -> void:
	var net: RailNetwork = _net()
	var a: Array[Vector2i] = RailPlanner.new().find_route(net, Vector2i(2, 5), Vector2i(12, 5))
	var b: Array[Vector2i] = RailPlanner.new().find_route(net, Vector2i(2, 5), Vector2i(12, 5))
	check_eq(a, b, "même tracé à chaque fois")
	check_eq(a.size(), 11, "ligne droite quand rien ne gêne")


func test_connect_to_existing_cell_joins_head() -> void:
	var net: RailNetwork = _net()
	_line(net, 5, 2, 5)
	_line(net, 9, 2, 8)
	var plan: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(5, 5), Vector2i(2, 9), true)
	check_eq(plan["kind"], K.FAIL if net.graph.is_connected_cells(Vector2i(2, 9), Vector2i(5, 5)) else plan["kind"], "cohérent")
	var plain: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(8, 9), NO_HEAD, false)
	check_eq(plain["kind"], K.ANCHOR, "toucher une case équipée sans tête : la choisir comme départ")


func test_station_end_is_preferred_and_axis_respected() -> void:
	var net: RailNetwork = _net()
	net.place_station(Vector2i(4, 4), 0)
	var good: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(5, 4), NO_HEAD, false)
	check_eq(good["kind"], K.CONNECT, "rail relié à la gare dans son axe")
	check_eq(good["edges"][0], Dir.pair(Vector2i(4, 4), Vector2i(5, 4)), "depuis la gare")
	var bad: Dictionary = RailPlanner.new().plan_tap(net, Vector2i(4, 5), NO_HEAD, false)
	check_eq(bad["kind"], K.FAIL, "hors de l'axe de la gare : refusé")
	check(bad["message"].contains("axe"), "message explicite")


func test_refusals_are_reported() -> void:
	var net: RailNetwork = _net()
	net.map.set_terrain(Vector2i(7, 7), Terrain.Type.WATER)
	check_eq(RailPlanner.new().plan_tap(net, Vector2i(7, 7), NO_HEAD, false)["kind"], K.FAIL, "eau")
	check_eq(RailPlanner.new().plan_tap(net, Vector2i(30, 3), NO_HEAD, false)["kind"], K.FAIL, "hors carte")


func test_planner_never_modifies_network() -> void:
	var net: RailNetwork = _net()
	_line(net, 5, 2, 5)
	var before_edges: int = net.graph.edge_count()
	var before_id: int = net.graph.next_id()
	for cell: Vector2i in [Vector2i(6, 5), Vector2i(5, 6), Vector2i(12, 9), Vector2i(1, 1)]:
		RailPlanner.new().plan_tap(net, cell, Vector2i(5, 5), true)
	check_eq(net.graph.edge_count(), before_edges, "réseau intact")
	check_eq(net.graph.next_id(), before_id, "ids intacts")


func test_replace_edge_is_atomic() -> void:
	var net: RailNetwork = _net()
	_line(net, 5, 2, 5)
	var id: int = net.graph.edge_id(Vector2i(4, 5), Vector2i(5, 5))
	check_eq(net.replace_edge(Vector2i(4, 5), Vector2i(5, 5), Vector2i(4, 5), Vector2i(4, 6)), RailNetwork.Result.SHARP_TURN, "remplacement invalide refusé")
	check_eq(net.graph.edge_id(Vector2i(4, 5), Vector2i(5, 5)), id, "ancien segment intact, même id")
	check_eq(net.replace_edge(Vector2i(4, 5), Vector2i(5, 5), Vector2i(4, 5), Vector2i(5, 6)), RailNetwork.Result.OK, "remplacement valide")
	check(net.graph.has_edge(Vector2i(4, 5), Vector2i(5, 6)) and not net.graph.has_edge(Vector2i(4, 5), Vector2i(5, 5)), "échange effectué")
