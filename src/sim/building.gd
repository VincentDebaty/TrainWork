extends RefCounted
## Bâtiment (mine, scierie, ville…) : emprise rectangulaire, stocks d'entrée et de sortie
## séparés, cycle de production. La logique est dans Industry.

enum State { WAITING_INPUT, PRODUCING, OUTPUT_FULL }

const STATE_NAMES: Dictionary = {
	State.WAITING_INPUT: "attend des intrants",
	State.PRODUCING: "en production",
	State.OUTPUT_FULL: "sortie pleine",
}

var id: int
var type_id: String
var cell: Vector2i  # coin haut de l'emprise
var size: Vector2i
var inputs: Dictionary = {}  # produit -> quantité
var outputs: Dictionary = {}
var cycle_running: bool = false
var progress: int = 0
var state: int = State.WAITING_INPUT
var station_id: int = 0  # gare de rattachement, 0 si aucune


func _init(p_id: int, p_type_id: String, p_cell: Vector2i, p_size: Vector2i) -> void:
	id = p_id
	type_id = p_type_id
	cell = p_cell
	size = p_size


func contains(c: Vector2i) -> bool:
	return c.x >= cell.x and c.y >= cell.y and c.x < cell.x + size.x and c.y < cell.y + size.y


## Distance (Chebyshev, en cases) de `c` à l'emprise ; 0 si `c` est dedans.
func distance_to(c: Vector2i) -> int:
	var dx: int = maxi(maxi(cell.x - c.x, c.x - (cell.x + size.x - 1)), 0)
	var dy: int = maxi(maxi(cell.y - c.y, c.y - (cell.y + size.y - 1)), 0)
	return maxi(dx, dy)


## Carré de la distance euclidienne (en cases) de `c` à l'emprise : départage deux gares
## à égale distance de Chebyshev.
func distance_sq_to(c: Vector2i) -> int:
	var dx: int = maxi(maxi(cell.x - c.x, c.x - (cell.x + size.x - 1)), 0)
	var dy: int = maxi(maxi(cell.y - c.y, c.y - (cell.y + size.y - 1)), 0)
	return dx * dx + dy * dy


func center_grid() -> Vector2:
	return Vector2(cell) + Vector2(size) * 0.5


func to_dict() -> Dictionary:
	return {"id": id, "type": type_id, "cell": [cell.x, cell.y], "inputs": inputs.duplicate(), "outputs": outputs.duplicate(),
			"cycle_running": cycle_running, "progress": progress, "state": state}
