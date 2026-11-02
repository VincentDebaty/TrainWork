extends "res://tests/test_case.gd"

const RailGraph = preload("res://src/rail/rail_graph.gd")
const Dir = preload("res://src/rail/direction.gd")


func _line(graph: RailGraph, from: Vector2i, step: Vector2i, count: int) -> void:
	for i: int in count:
		graph.add_edge(from + step * i, from + step * (i + 1))


func test_directions() -> void:
	for d: int in 8:
		check_eq(Dir.from_delta(Dir.VECTORS[d]), d, "from_delta inverse de VECTORS")
		check_eq(Dir.VECTORS[Dir.opposite(d)], -Dir.VECTORS[d], "opposé %d" % d)
	check_eq(Dir.from_delta(Vector2i(2, 0)), -1, "non voisin")
	check(Dir.is_diagonal(1) and not Dir.is_diagonal(0), "diagonales")
	check(Dir.turn_ok(0, 1) and Dir.turn_ok(0, 7) and Dir.turn_ok(0, 0), "virages <= 45°")
	check(not Dir.turn_ok(0, 2) and not Dir.turn_ok(0, 4), "virage 90° et demi-tour refusés")


func test_step_path() -> void:
	var path: Array[Vector2i] = Dir.step_path(Vector2i(0, 0), Vector2i(3, 1))
	check_eq(path, [Vector2i(0, 0), Vector2i(1, 1), Vector2i(2, 1), Vector2i(3, 1)] as Array[Vector2i], "diagonale puis droite")
	check_eq(Dir.step_path(Vector2i(2, 2), Vector2i(2, 2)).size(), 1, "même case")


func test_edges_are_undirected_with_stable_ids() -> void:
	var g: RailGraph = RailGraph.new()
	var id: int = g.add_edge(Vector2i(0, 0), Vector2i(1, 0))
	check(id > 0, "id attribué")
	check(g.has_edge(Vector2i(1, 0), Vector2i(0, 0)), "non orienté")
	check_eq(g.edge_id(Vector2i(1, 0), Vector2i(0, 0)), id, "même id dans les deux sens")
	check_eq(g.add_edge(Vector2i(1, 0), Vector2i(0, 0)), 0, "doublon refusé")
	check_eq(g.add_edge(Vector2i(0, 0), Vector2i(2, 0)), 0, "non voisin refusé")
	var id2: int = g.add_edge(Vector2i(1, 0), Vector2i(2, 0))
	check(id2 > id, "ids croissants")
	g.remove_edge(Vector2i(0, 0), Vector2i(1, 0))
	check_eq(g.add_edge(Vector2i(0, 0), Vector2i(1, 0)), id2 + 1, "un id n'est jamais réutilisé")


func test_degree_masks_and_cleanup() -> void:
	var g: RailGraph = RailGraph.new()
	g.add_edge(Vector2i(5, 5), Vector2i(6, 5))
	g.add_edge(Vector2i(5, 5), Vector2i(4, 5))
	check_eq(g.degree(Vector2i(5, 5)), 2, "degré 2")
	check(not g.is_switch(Vector2i(5, 5)), "pas un aiguillage")
	g.remove_edge(Vector2i(5, 5), Vector2i(6, 5))
	g.remove_edge(Vector2i(5, 5), Vector2i(4, 5))
	check(not g.has_cell(Vector2i(5, 5)), "case sans voie oubliée")
	check_eq(g.edge_count(), 0, "plus de segment")


func test_switch_is_derived_from_degree() -> void:
	var g: RailGraph = RailGraph.new()
	_line(g, Vector2i(0, 5), Vector2i(1, 0), 4)  # voie droite (0,5)..(4,5)
	check_eq(g.switch_count(), 0, "voie simple : aucun aiguillage")
	g.add_edge(Vector2i(2, 5), Vector2i(3, 4))  # embranchement diagonal
	check(g.is_switch(Vector2i(2, 5)), "case de degré 3 = aiguillage")
	check_eq(g.switch_count(), 1, "un aiguillage")
	g.remove_edge(Vector2i(2, 5), Vector2i(3, 4))
	check_eq(g.switch_count(), 0, "l'aiguillage disparaît avec l'embranchement")


func test_continuity_break_and_reconnection() -> void:
	var g: RailGraph = RailGraph.new()
	_line(g, Vector2i(0, 0), Vector2i(1, 0), 6)
	check(g.is_connected_cells(Vector2i(0, 0), Vector2i(6, 0)), "voie continue")
	check_eq(g.find_path(Vector2i(0, 0), Vector2i(6, 0)).size(), 7, "chemin de 7 cases")
	g.remove_edge(Vector2i(3, 0), Vector2i(4, 0))
	check(not g.is_connected_cells(Vector2i(0, 0), Vector2i(6, 0)), "rupture")
	check_eq(g.find_path(Vector2i(0, 0), Vector2i(6, 0)).size(), 0, "plus de chemin")
	check(g.is_connected_cells(Vector2i(0, 0), Vector2i(3, 0)), "tronçon amont intact")
	g.add_edge(Vector2i(3, 0), Vector2i(4, 0))
	check(g.is_connected_cells(Vector2i(0, 0), Vector2i(6, 0)), "reconnexion")
	check_eq(g.find_path(Vector2i(0, 0), Vector2i(6, 0)).size(), 7, "chemin retrouvé")


func test_path_takes_branch_through_switch() -> void:
	var g: RailGraph = RailGraph.new()
	_line(g, Vector2i(0, 5), Vector2i(1, 0), 4)  # tronc
	g.add_edge(Vector2i(2, 5), Vector2i(3, 4))  # branche
	g.add_edge(Vector2i(3, 4), Vector2i(4, 4))
	var path: Array[Vector2i] = g.find_path(Vector2i(0, 5), Vector2i(4, 4))
	check_eq(path.size(), 5, "tronc puis branche")
	check_eq(path[2], Vector2i(2, 5), "passe par l'aiguillage")
	check_eq(path[3], Vector2i(3, 4), "prend la branche")
	check_eq(g.find_path(Vector2i(4, 4), Vector2i(0, 5)).size(), 5, "de la branche vers le tronc, côté ouest (virage 45°)")
	check_eq(g.find_path(Vector2i(4, 4), Vector2i(4, 5)).size(), 0, "côté est : rebroussement à 135°, refusé")


func test_path_refuses_sharp_turns() -> void:
	var g: RailGraph = RailGraph.new()
	# Coin à 90° forcé directement dans le graphe (le réseau le refuserait).
	g.add_edge(Vector2i(0, 0), Vector2i(1, 0))
	g.add_edge(Vector2i(1, 0), Vector2i(1, 1))
	check(g.is_connected_cells(Vector2i(0, 0), Vector2i(1, 1)), "topologiquement connecté")
	check_eq(g.find_path(Vector2i(0, 0), Vector2i(1, 1)).size(), 0, "mais pas praticable par un train")


func test_path_endpoints() -> void:
	var g: RailGraph = RailGraph.new()
	g.add_edge(Vector2i(0, 0), Vector2i(1, 0))
	check_eq(g.find_path(Vector2i(0, 0), Vector2i(0, 0)).size(), 1, "départ = arrivée")
	check_eq(g.find_path(Vector2i(0, 0), Vector2i(9, 9)).size(), 0, "arrivée hors réseau")
