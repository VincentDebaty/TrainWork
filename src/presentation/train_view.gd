extends Node2D
## Rendu placeholder des trains, interpolé entre deux pas de simulation. Lit la
## simulation, ne la modifie pas.

const Dir = preload("res://src/rail/direction.gd")
const Train = preload("res://src/sim/train.gd")

const BODY_COLOR: Color = Color("1f2a44")
const DWELL_COLOR: Color = Color("4a5a7a")
const WAIT_COLOR: Color = Color("b02a2a")
const CHIMNEY_COLOR: Color = Color("f4efe6")
const HALF_LENGTH: float = 34.0
const WIDTH: float = 26.0

var _simulation: RefCounted
var _projection: RefCounted


func setup(simulation: RefCounted, projection: RefCounted) -> void:
	_simulation = simulation
	_projection = projection


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _simulation == null:
		return
	var alpha: float = _simulation.alpha()
	for id: int in _simulation.trains.trains:
		var train: Train = _simulation.trains.trains[id]
		var grid: Vector2 = train.prev_pos.lerp(train.pos, alpha)
		var center: Vector2 = _projection.grid_to_world(grid)
		center += _quay_offset(train)
		var heading: Vector2 = _projection.grid_to_world(Vector2(Dir.VECTORS[train.heading])).normalized()
		var color: Color = BODY_COLOR
		if train.state == Train.State.DWELLING:
			color = DWELL_COLOR
		elif train.state == Train.State.WAITING_ROUTE:
			color = WAIT_COLOR
		draw_line(center - heading * HALF_LENGTH, center + heading * HALF_LENGTH, color, WIDTH)
		draw_circle(center + heading * HALF_LENGTH, WIDTH * 0.5, color)
		draw_circle(center + heading * (HALF_LENGTH * 0.55), 6.0, CHIMNEY_COLOR)


## Deux trains dans la même gare (deux quais) sont dessinés l'un à côté de l'autre.
func _quay_offset(train: Train) -> Vector2:
	for id: int in _simulation.trains.trains:
		var other: Train = _simulation.trains.trains[id]
		if other.id != train.id and other.pos.distance_to(train.pos) < 0.9 and train.cell == other.cell:
			var side: float = 1.0 if train.id > other.id else -1.0
			return Vector2(0, 22.0 * side)
	return Vector2.ZERO
