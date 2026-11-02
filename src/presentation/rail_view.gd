extends Node2D
## Rendu placeholder des rails, aiguillages, gares et de l'aperçu de tracé.
## Lit le réseau et le contrôleur d'outils, ne modifie rien.

const Dir = preload("res://src/rail/direction.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const BuildController = preload("res://src/presentation/build_controller.gd")

const RAIL_COLOR: Color = Color("3b322c")
const RAIL_LIGHT: Color = Color("c9bba8")
const SWITCH_COLOR: Color = Color("f08a24")
const STATION_COLOR: Color = Color("a8322d")
const STATION_AXIS_COLOR: Color = Color("f4efe6")
const PREVIEW_OK: Color = Color(0.25, 0.85, 0.3, 0.75)
const PREVIEW_EXISTS: Color = Color(0.6, 0.7, 0.85, 0.6)
const PREVIEW_BAD: Color = Color(0.9, 0.2, 0.2, 0.8)
const PREVIEW_ERASE: Color = Color(0.95, 0.55, 0.1, 0.8)
const LINE_COLOR: Color = Color(1.0, 0.85, 0.2, 0.9)
const BRIDGE_COLOR: Color = Color("8a6a45")

var _network: RailNetwork
var _projection: RefCounted
var _build: Node


func setup(network: RailNetwork, projection: RefCounted, camera: Camera2D, build: Node) -> void:
	_network = network
	_projection = projection
	_build = build
	network.changed.connect(queue_redraw)
	camera.view_changed.connect(queue_redraw)
	build.preview_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if _network == null:
		return
	_draw_bridge_sites()
	var edges: Array[Vector4i] = _network.graph.edges()
	for e: Vector4i in edges:
		draw_line(_center(e.x, e.y), _center(e.z, e.w), RAIL_COLOR, 10.0)
	for e: Vector4i in edges:
		draw_line(_center(e.x, e.y), _center(e.z, e.w), RAIL_LIGHT, 3.0)
	for cell: Vector2i in _network.graph.cells():
		if _network.graph.is_switch(cell):
			draw_circle(_projection.cell_center(cell), 12.0, SWITCH_COLOR)
	for station: RefCounted in _network.stations():
		_draw_station(station)
	_draw_preview()
	_draw_pending_line()
	_draw_head()


## Site de pont débloqué : tablier en bois sur l'eau, où les rails peuvent passer.
func _draw_bridge_sites() -> void:
	for cell: Vector2i in _network.map.bridge_cells:
		if _network.is_bridge_open(cell):
			var corners: PackedVector2Array = _projection.cell_corners(cell)
			draw_colored_polygon(corners, BRIDGE_COLOR)
			draw_polyline(corners + PackedVector2Array([corners[0]]), RAIL_COLOR, 2.0)


func _draw_station(station: RefCounted) -> void:
	var center: Vector2 = _projection.cell_center(station.cell)
	var corners: PackedVector2Array = _projection.cell_corners(station.cell)
	var shrunk: PackedVector2Array = PackedVector2Array()
	for corner: Vector2 in corners:
		shrunk.append(center + (corner - center) * 0.75)
	draw_colored_polygon(shrunk, STATION_COLOR)
	var axis: Vector2 = _projection.grid_to_world(Vector2(Dir.VECTORS[station.orientation])) * 0.4
	draw_line(center - axis, center + axis, STATION_AXIS_COLOR, 12.0)


func _draw_preview() -> void:
	var edges: Array[Vector4i] = _build.preview_edges
	var erasing: bool = _build.mode == BuildController.Mode.ERASE
	for i: int in edges.size():
		var color: Color = PREVIEW_ERASE
		if not erasing:
			var result: int = _build.preview_results[i]
			color = PREVIEW_OK if result == RailNetwork.Result.OK \
				else PREVIEW_EXISTS if result == RailNetwork.Result.ALREADY_EXISTS \
				else PREVIEW_BAD
		draw_line(_center(edges[i].x, edges[i].y), _center(edges[i].z, edges[i].w), color, 16.0)


func _draw_head() -> void:
	if _build.mode == BuildController.Mode.RAIL and _build.has_head:
		draw_arc(_projection.cell_center(_build.head), 26.0, 0.0, TAU, 32, LINE_COLOR, 6.0)


func _draw_pending_line() -> void:
	var ids: Array[int] = _build.pending_stations
	var font: Font = ThemeDB.fallback_font
	for i: int in ids.size():
		var station: RefCounted = _network.station_by_id(ids[i])
		if station == null:
			continue
		var center: Vector2 = _projection.cell_center(station.cell)
		if i > 0:
			var previous: RefCounted = _network.station_by_id(ids[i - 1])
			if previous != null:
				draw_dashed_line(_projection.cell_center(previous.cell), center, LINE_COLOR, 5.0, 14.0)
		draw_circle(center + Vector2(0, -34), 20.0, LINE_COLOR)
		draw_string(font, center + Vector2(-8, -26), str(i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.BLACK)


func _center(x: int, y: int) -> Vector2:
	return _projection.cell_center(Vector2i(x, y))
