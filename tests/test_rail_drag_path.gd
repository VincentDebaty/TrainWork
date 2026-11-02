extends "res://tests/test_case.gd"

const RailDragPath = preload("res://src/rail/rail_drag_path.gd")


func test_adjacent_cells_accumulate() -> void:
	var drag: RailDragPath = RailDragPath.new()
	drag.begin(Vector2i(0, 0))
	drag.extend_to(Vector2i(1, 0))
	drag.extend_to(Vector2i(2, 1))
	check_eq(drag.cells.size(), 3, "3 cases")
	check_eq(drag.edges().size(), 2, "2 segments")


func test_jump_is_filled() -> void:
	var drag: RailDragPath = RailDragPath.new()
	drag.begin(Vector2i(0, 0))
	drag.extend_to(Vector2i(4, 2))
	check_eq(drag.cells.size(), 5, "saut comblé : 2 diagonales + 2 droites")
	for e: Vector4i in drag.edges():
		check(absi(e.z - e.x) <= 1 and absi(e.w - e.y) <= 1, "segments entre voisins")


func test_backtracking_removes_last_step() -> void:
	var drag: RailDragPath = RailDragPath.new()
	drag.begin(Vector2i(0, 0))
	drag.extend_to(Vector2i(1, 0))
	drag.extend_to(Vector2i(2, 0))
	drag.extend_to(Vector2i(1, 0))
	check_eq(drag.cells.back(), Vector2i(1, 0), "recul d'une case")
	check_eq(drag.cells.size(), 2, "le pas annulé disparaît")
	drag.extend_to(Vector2i(0, 0))
	check_eq(drag.edges().size(), 0, "retour au départ : aucun segment")


func test_same_cell_is_noop_and_cap() -> void:
	var drag: RailDragPath = RailDragPath.new()
	drag.begin(Vector2i(0, 0))
	drag.extend_to(Vector2i(0, 0))
	check_eq(drag.cells.size(), 1, "même case ignorée")
	drag.extend_to(Vector2i(1000, 0))
	check(drag.cells.size() <= RailDragPath.MAX_CELLS, "longueur plafonnée")
