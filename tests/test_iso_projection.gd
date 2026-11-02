extends "res://tests/test_case.gd"

const IsoProjection = preload("res://src/core/iso_projection.gd")


func test_known_values() -> void:
	var proj: IsoProjection = IsoProjection.new(Vector2(128, 64))
	check_near_v(proj.grid_to_world(Vector2(0, 0)), Vector2(0, 0), "origine")
	check_near_v(proj.grid_to_world(Vector2(1, 0)), Vector2(64, 32), "x+1 descend à droite")
	check_near_v(proj.grid_to_world(Vector2(0, 1)), Vector2(-64, 32), "y+1 descend à gauche")
	check_near_v(proj.grid_to_world(Vector2(1, 1)), Vector2(0, 64), "diagonale")


func test_round_trip() -> void:
	var proj: IsoProjection = IsoProjection.new(Vector2(128, 64))
	for g: Vector2 in [Vector2(0, 0), Vector2(3.5, 7.25), Vector2(63.9, 0.1), Vector2(-2, 5)]:
		check_near_v(proj.world_to_grid(proj.grid_to_world(g)), g, "aller-retour %s" % str(g), 0.0001)


func test_cell_picking() -> void:
	var proj: IsoProjection = IsoProjection.new(Vector2(128, 64))
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(10, 4), Vector2i(63, 63), Vector2i(5, 30)]:
		check_eq(proj.world_to_cell(proj.cell_center(cell)), cell, "centre de %s" % str(cell))
		for corner: Vector2 in proj.cell_corners(cell):
			var inside: Vector2 = corner.lerp(proj.cell_center(cell), 0.1)
			check_eq(proj.world_to_cell(inside), cell, "près d'un sommet de %s" % str(cell))


func test_map_bounds_contain_all_corners() -> void:
	var proj: IsoProjection = IsoProjection.new(Vector2(128, 64))
	var bounds: Rect2 = proj.map_bounds(Vector2i(64, 64))
	check_near_v(bounds.position, Vector2(-4096, 0), "coin haut-gauche")
	check_near_v(bounds.size, Vector2(8192, 4096), "taille")
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(63, 0), Vector2i(0, 63), Vector2i(63, 63)]:
		for corner: Vector2 in proj.cell_corners(cell):
			check(bounds.grow(0.01).has_point(corner), "sommet %s dans les limites" % str(corner))
