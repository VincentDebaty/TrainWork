extends RefCounted
## Gare (données). M1 : une case, un axe, type fret. Les stocks viendront en M3.

var id: int
var cell: Vector2i
## Axe de la voie à travers la gare : 0..3 (voir direction.gd, AXIS_NAMES).
var orientation: int
var type: String = "freight"
var station_name: String


func _init(p_id: int, p_cell: Vector2i, p_orientation: int) -> void:
	id = p_id
	cell = p_cell
	orientation = p_orientation
	station_name = "Gare %d" % p_id
