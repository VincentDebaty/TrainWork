extends RefCounted
## Données de la carte : grille logique de terrains. Aucune dépendance au rendu.

const Terrain = preload("res://src/core/terrain.gd")

var width: int
var height: int
var map_seed: int
var generator_version: int
var _cells: PackedByteArray = PackedByteArray()
## Cases d'eau où un pont peut porter des rails (site de pont désigné par le scénario).
var bridge_cells: Dictionary = {}  # Vector2i -> true


func _init(p_width: int, p_height: int, p_seed: int, p_generator_version: int) -> void:
	width = p_width
	height = p_height
	map_seed = p_seed
	generator_version = p_generator_version
	_cells.resize(width * height)
	_cells.fill(Terrain.Type.PLAINS)


func size() -> Vector2i:
	return Vector2i(width, height)


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < width and cell.y < height


func get_terrain(cell: Vector2i) -> int:
	return _cells[cell.y * width + cell.x]


func set_terrain(cell: Vector2i, terrain: int) -> void:
	_cells[cell.y * width + cell.x] = terrain


## Empreinte stable du contenu (tests de reproductibilité et, plus tard, de sauvegarde).
func checksum() -> int:
	var h: int = 1469598103934665603
	for c: int in _cells:
		h = (h ^ c) * 1099511628211
	var bridges: Array = bridge_cells.keys()
	bridges.sort()
	for cell: Vector2i in bridges:
		h = (h ^ (cell.x * 4099 + cell.y)) * 1099511628211
	return h
