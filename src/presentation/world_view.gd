extends Node2D
## Rendu placeholder de la carte (losanges colorés). Ne dessine que les cases
## visibles. Lit la carte et la caméra, ne modifie rien.

const Terrain = preload("res://src/core/terrain.gd")
const CameraMath = preload("res://src/core/camera_math.gd")

const TERRAIN_COLORS: Dictionary = {
	Terrain.Type.PLAINS: Color("8fb35a"),
	Terrain.Type.FOREST: Color("3f7a3c"),
	Terrain.Type.HILL: Color("a89870"),
	Terrain.Type.WATER: Color("4a88b8"),
	Terrain.Type.ROCK: Color("9c958a"),
}
const BORDER_COLOR: Color = Color("2b2118")
const GRID_COLOR: Color = Color(0.0, 0.0, 0.0, 0.18)
const SELECTION_COLOR: Color = Color("ffd24a")
const NO_CELL: Vector2i = Vector2i(-1, -1)

var _map: RefCounted
var _projection: RefCounted
var _camera: Camera2D
var _draw_grid: bool = false
var _selected_cell: Vector2i = NO_CELL


func setup(map: RefCounted, projection: RefCounted, camera: Camera2D, draw_grid: bool) -> void:
	_map = map
	_projection = projection
	_camera = camera
	_draw_grid = draw_grid
	_camera.view_changed.connect(queue_redraw)
	queue_redraw()


func select_cell(cell: Vector2i) -> void:
	_selected_cell = cell
	queue_redraw()


func _draw() -> void:
	if _map == null:
		return
	var visible: Rect2 = CameraMath.visible_world_rect(_camera.position, _camera.zoom.x, get_viewport_rect().size)
	var first: Vector2i
	var last: Vector2i
	var range_cells: Array[Vector2i] = _visible_cell_range(visible)
	first = range_cells[0]
	last = range_cells[1]
	for y: int in range(first.y, last.y + 1):
		for x: int in range(first.x, last.x + 1):
			var cell: Vector2i = Vector2i(x, y)
			var corners: PackedVector2Array = _projection.cell_corners(cell)
			draw_colored_polygon(corners, _cell_color(cell))
			if _draw_grid:
				draw_polyline(corners + PackedVector2Array([corners[0]]), GRID_COLOR, 1.0)
	_draw_map_border()
	if _map.in_bounds(_selected_cell):
		var corners: PackedVector2Array = _projection.cell_corners(_selected_cell)
		draw_polyline(corners + PackedVector2Array([corners[0]]), SELECTION_COLOR, 4.0)


## Plage de cases (min, max inclus) couvrant le rectangle monde visible, bornée à la carte.
func _visible_cell_range(visible: Rect2) -> Array[Vector2i]:
	var min_cell: Vector2i = Vector2i(_map.width, _map.height)
	var max_cell: Vector2i = Vector2i(-1, -1)
	for corner: Vector2 in [visible.position, Vector2(visible.end.x, visible.position.y), visible.end, Vector2(visible.position.x, visible.end.y)]:
		var cell: Vector2i = _projection.world_to_cell(corner)
		min_cell = min_cell.min(cell)
		max_cell = max_cell.max(cell)
	min_cell = min_cell.max(Vector2i.ZERO)
	max_cell = max_cell.min(Vector2i(_map.width - 1, _map.height - 1))
	return [min_cell, max_cell]


func _cell_color(cell: Vector2i) -> Color:
	var base: Color = TERRAIN_COLORS[_map.get_terrain(cell)]
	# Légère variation par case pour que le défilement soit lisible sur les grandes plaines.
	var shade: float = float((cell.x * 7 + cell.y * 13) % 3 - 1) * 0.02
	return base.lightened(shade) if shade >= 0.0 else base.darkened(-shade)


func _draw_map_border() -> void:
	var w: int = _map.width
	var h: int = _map.height
	var outline: PackedVector2Array = PackedVector2Array([
		_projection.grid_to_world(Vector2(0, 0)),
		_projection.grid_to_world(Vector2(w, 0)),
		_projection.grid_to_world(Vector2(w, h)),
		_projection.grid_to_world(Vector2(0, h)),
		_projection.grid_to_world(Vector2(0, 0)),
	])
	draw_polyline(outline, BORDER_COLOR, 6.0)
