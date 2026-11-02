extends RefCounted
## Projection isométrique 2:1 fixe. Seule la couche de rendu et la saisie
## l'utilisent : la simulation reste sur la grille logique (x, y).
##
## Convention : l'axe x de la grille descend vers la droite, l'axe y vers la gauche.
## Le coin haut du losange de la case (0, 0) est à l'origine du monde.

var tile_size: Vector2


func _init(p_tile_size: Vector2 = Vector2(128.0, 64.0)) -> void:
	tile_size = p_tile_size


## Coordonnées de grille (éventuellement fractionnaires) -> monde.
func grid_to_world(grid: Vector2) -> Vector2:
	return Vector2(
		(grid.x - grid.y) * tile_size.x * 0.5,
		(grid.x + grid.y) * tile_size.y * 0.5,
	)


## Monde -> coordonnées de grille fractionnaires.
func world_to_grid(world: Vector2) -> Vector2:
	var diff: float = world.x / (tile_size.x * 0.5)  # x - y
	var sum: float = world.y / (tile_size.y * 0.5)  # x + y
	return Vector2((sum + diff) * 0.5, (sum - diff) * 0.5)


func world_to_cell(world: Vector2) -> Vector2i:
	var grid: Vector2 = world_to_grid(world)
	return Vector2i(floori(grid.x), floori(grid.y))


func cell_center(cell: Vector2i) -> Vector2:
	return grid_to_world(Vector2(cell) + Vector2(0.5, 0.5))


## Sommets du losange : haut, droite, bas, gauche.
func cell_corners(cell: Vector2i) -> PackedVector2Array:
	var c: Vector2 = Vector2(cell)
	return PackedVector2Array([
		grid_to_world(c),
		grid_to_world(c + Vector2(1.0, 0.0)),
		grid_to_world(c + Vector2(1.0, 1.0)),
		grid_to_world(c + Vector2(0.0, 1.0)),
	])


## Boîte englobante monde d'une carte de `size` cases.
func map_bounds(size: Vector2i) -> Rect2:
	var top: Vector2 = grid_to_world(Vector2.ZERO)
	var right: Vector2 = grid_to_world(Vector2(size.x, 0))
	var bottom: Vector2 = grid_to_world(Vector2(size))
	var left: Vector2 = grid_to_world(Vector2(0, size.y))
	var min_pt: Vector2 = top.min(right).min(bottom).min(left)
	var max_pt: Vector2 = top.max(right).max(bottom).max(left)
	return Rect2(min_pt, max_pt - min_pt)
