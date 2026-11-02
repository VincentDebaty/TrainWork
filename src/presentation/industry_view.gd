extends Node2D
## Rendu placeholder des bâtiments (emprise colorée, nom, stocks), de leur lien avec
## leur gare, et du rayon de desserte des gares en mode Gare. Lit la simulation,
## ne la modifie pas.

const BuildController = preload("res://src/presentation/build_controller.gd")

const BORDER_COLOR: Color = Color("2b2118")
const LINK_COLOR: Color = Color(1.0, 0.85, 0.2, 0.9)
const NO_STATION_COLOR: Color = Color(0.9, 0.2, 0.2, 0.95)
const RADIUS_COLOR: Color = Color(1.0, 0.85, 0.2, 0.18)
const RADIUS_BORDER: Color = Color(1.0, 0.85, 0.2, 0.6)
const FONT_SIZE: int = 22

var _simulation: RefCounted
var _network: RefCounted
var _projection: RefCounted
var _build: Node


func setup(simulation: RefCounted, network: RefCounted, projection: RefCounted, build: Node) -> void:
	_simulation = simulation
	_network = network
	_projection = projection
	_build = build


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _simulation == null:
		return
	var industry: RefCounted = _simulation.industry
	var content: RefCounted = _simulation.content
	if _build.mode == BuildController.Mode.STATION:
		_draw_station_radii(content.logistic("station_radius", 2))
	var font: Font = ThemeDB.fallback_font
	for id: int in industry.buildings:
		var building: RefCounted = industry.buildings[id]
		var type: Dictionary = content.buildings[building.type_id]
		var active: bool = industry.is_active(building)
		var corners: PackedVector2Array = PackedVector2Array([
			_projection.grid_to_world(Vector2(building.cell)),
			_projection.grid_to_world(Vector2(building.cell + Vector2i(building.size.x, 0))),
			_projection.grid_to_world(Vector2(building.cell + building.size)),
			_projection.grid_to_world(Vector2(building.cell + Vector2i(0, building.size.y))),
		])
		var center: Vector2 = _projection.grid_to_world(building.center_grid())
		if not active:
			continue  # site d'un niveau à venir : invisible, seul son environnement le trahit
		draw_colored_polygon(corners, Color(type["color"]))
		draw_polyline(corners + PackedVector2Array([corners[0]]), BORDER_COLOR, 5.0)
		_label(font, center + Vector2(0, -8), type["name"])
		_label(font, center + Vector2(0, 20), _stock_text(industry, content, building, type))
		_draw_link(industry, building, center)


func _draw_link(industry: RefCounted, building: RefCounted, center: Vector2) -> void:
	if building.station_id == 0:
		_label(ThemeDB.fallback_font, center + Vector2(0, 48), "sans gare", NO_STATION_COLOR)
		return
	var station: RefCounted = _network.station_by_id(building.station_id)
	if station != null:
		draw_dashed_line(center, _projection.cell_center(station.cell), LINK_COLOR, 4.0, 12.0)


func _draw_station_radii(radius: int) -> void:
	for station: RefCounted in _network.stations():
		var low: Vector2i = station.cell - Vector2i(radius, radius)
		var high: Vector2i = station.cell + Vector2i(radius + 1, radius + 1)
		var corners: PackedVector2Array = PackedVector2Array([
			_projection.grid_to_world(Vector2(low)),
			_projection.grid_to_world(Vector2(high.x, low.y)),
			_projection.grid_to_world(Vector2(high)),
			_projection.grid_to_world(Vector2(low.x, high.y)),
		])
		draw_colored_polygon(corners, RADIUS_COLOR)
		draw_polyline(corners + PackedVector2Array([corners[0]]), RADIUS_BORDER, 3.0)


func _stock_text(industry: RefCounted, content: RefCounted, building: RefCounted, type: Dictionary) -> String:
	var parts: PackedStringArray = []
	for good: String in building.outputs:
		parts.append("%s %d/%d" % [content.good_name(good), building.outputs[good], type["output_cap"]])
	for good: String in industry.active_inputs(building):
		parts.append("%s %d/%d" % [content.good_name(good), building.inputs.get(good, 0), industry.input_cap(building, good)])
	return " | ".join(parts)


func _label(font: Font, position: Vector2, text: String, color: Color = Color.WHITE) -> void:
	var size: Vector2 = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var origin: Vector2 = position - Vector2(size.x * 0.5, 0)
	draw_string_outline(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, 6, Color.BLACK)
	draw_string(font, origin, text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, color)
