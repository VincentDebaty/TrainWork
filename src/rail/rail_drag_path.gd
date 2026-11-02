extends RefCounted
## Chemin tracé au doigt : suite de cases voisines. Pur (testable sans scène).
##  - un saut de plusieurs cases est comblé (diagonales puis ligne droite) ;
##  - revenir sur la case précédente efface le dernier pas (annulation par recul).

const Dir = preload("res://src/rail/direction.gd")

const MAX_CELLS: int = 400

var cells: Array[Vector2i] = []


func clear() -> void:
	cells.clear()


func begin(cell: Vector2i) -> void:
	cells.clear()
	cells.append(cell)


func extend_to(cell: Vector2i) -> void:
	if cells.is_empty():
		begin(cell)
		return
	var path: Array[Vector2i] = Dir.step_path(cells.back(), cell)
	for i: int in range(1, path.size()):
		_push(path[i])


## Segments du tracé (Vector4i), dans l'ordre.
func edges() -> Array[Vector4i]:
	var result: Array[Vector4i] = []
	for i: int in range(1, cells.size()):
		result.append(Dir.pair(cells[i - 1], cells[i]))
	return result


func _push(cell: Vector2i) -> void:
	if cells.size() >= 2 and cell == cells[cells.size() - 2]:
		cells.pop_back()
	elif cells.size() < MAX_CELLS and cell != cells.back():
		cells.append(cell)
