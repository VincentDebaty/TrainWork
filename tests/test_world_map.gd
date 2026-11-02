extends "res://tests/test_case.gd"

const MapGenerator = preload("res://src/core/map_generator.gd")
const Terrain = preload("res://src/core/terrain.gd")


func test_generation_is_reproducible() -> void:
	var a: RefCounted = MapGenerator.generate(64, 64, 1865, 1)
	var b: RefCounted = MapGenerator.generate(64, 64, 1865, 1)
	check_eq(a.checksum(), b.checksum(), "même seed => même carte")


func test_seed_changes_map() -> void:
	var a: RefCounted = MapGenerator.generate(64, 64, 1865, 1)
	var b: RefCounted = MapGenerator.generate(64, 64, 1866, 1)
	check(a.checksum() != b.checksum(), "seed différente => carte différente")


## Garde-fou : si ce nombre change, la carte de test a changé (voir docs/DECISIONS.md).
func test_pinned_checksum() -> void:
	var map: RefCounted = MapGenerator.generate(64, 64, 1865, 1)
	check_eq(map.checksum(), PINNED_CHECKSUM, "empreinte de la carte de test v1")


func test_all_terrains_present_and_river_continuous() -> void:
	var map: RefCounted = MapGenerator.generate(64, 64, 1865, 1)
	var counts: Dictionary = {}
	for y: int in 64:
		var water_in_row: int = 0
		for x: int in 64:
			var t: int = map.get_terrain(Vector2i(x, y))
			counts[t] = counts.get(t, 0) + 1
			if t == Terrain.Type.WATER:
				water_in_row += 1
		check_eq(water_in_row, 2, "rivière de 2 cases de large, rang %d" % y)
	for t: int in [Terrain.Type.PLAINS, Terrain.Type.FOREST, Terrain.Type.HILL, Terrain.Type.WATER]:
		check(counts.get(t, 0) > 0, "terrain %s présent" % Terrain.display_name(t))


func test_bounds() -> void:
	var map: RefCounted = MapGenerator.generate(8, 5, 1, 1)
	check(map.in_bounds(Vector2i(7, 4)), "dernier coin dedans")
	check(not map.in_bounds(Vector2i(8, 0)), "x hors limite")
	check(not map.in_bounds(Vector2i(0, -1)), "y négatif hors limite")


const PINNED_CHECKSUM: int = -2710221674165089106
