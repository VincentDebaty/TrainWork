extends RefCounted
## Générateur de carte, déterministe : uniquement des entiers et un hachage maison (pas
## de RandomNumberGenerator ni de bruit flottant), pour que la même entrée donne la même
## carte sur toute plateforme et toute version de Godot.
##
## Version 1 : carte de test M0-M4 (rivière nord-sud, massifs aléatoires).
## Version 2 : carte pilotée par une disposition (`layout`, tirée du scénario) : plaine
## clairsemée, environnement de chaque site (forêt, collines, roche), clairières autour
## des bâtiments, rivière en polyligne, site de pont. Une génération procédurale future
## pourra produire la même structure de disposition au lieu de la lire dans un fichier.

const Terrain = preload("res://src/core/terrain.gd")
const WorldMap = preload("res://src/core/world_map.gd")
const Dir = preload("res://src/rail/direction.gd")

## Décalage horizontal de la rivière selon y (motif répété tous les 16 rangs), version 1.
const RIVER_OFFSETS: Array[int] = [0, 0, 1, 1, 2, 2, 2, 1, 1, 0, 0, -1, -1, -2, -2, -1]
const BIOMES: Dictionary = {"forest": Terrain.Type.FOREST, "hills": Terrain.Type.HILL, "rock": Terrain.Type.ROCK}


static func generate(width: int, height: int, map_seed: int, generator_version: int, layout: Dictionary = {}) -> WorldMap:
	if generator_version >= 2 and not layout.is_empty():
		return _generate_v2(width, height, map_seed, generator_version, layout)
	var map: WorldMap = WorldMap.new(width, height, map_seed, generator_version)
	for y: int in height:
		var river_x: int = (width >> 1) + RIVER_OFFSETS[y % RIVER_OFFSETS.size()]
		for x: int in width:
			map.set_terrain(Vector2i(x, y), _terrain_at(x, y, river_x, map_seed))
	return map


static func _terrain_at(x: int, y: int, river_x: int, map_seed: int) -> int:
	if x == river_x or x == river_x + 1:
		return Terrain.Type.WATER
	# Zones par blocs de 4x4 cases : collines et forêts forment des massifs.
	var block: int = _hash(x >> 2, y >> 2, map_seed) % 100
	if block < 12:
		return Terrain.Type.HILL
	if block < 40 and _hash(x, y, map_seed + 1) % 100 < 85:
		return Terrain.Type.FOREST
	return Terrain.Type.PLAINS


## `layout` : {"sites": [{"cell": [x, y], "size": [w, h], "biome": {"type", "radius"},
## "clearing": n}], "river": {"points": [[x, y], ...]}, "bridge": {"center": [x, y], "radius": n}}.
static func _generate_v2(width: int, height: int, map_seed: int, generator_version: int, layout: Dictionary) -> WorldMap:
	var map: WorldMap = WorldMap.new(width, height, map_seed, generator_version)
	# 1. Plaine avec un décor clairsemé (petits bosquets et buttes), loin des sites.
	for y: int in height:
		for x: int in width:
			map.set_terrain(Vector2i(x, y), _decor_at(x, y, map_seed))
	var sites: Array = layout.get("sites", [])
	# 2. Environnement propre à chaque site.
	for site: Dictionary in sites:
		var biome: Dictionary = site.get("biome", {})
		if BIOMES.has(biome.get("type", "")):
			_stamp(map, site, BIOMES[biome["type"]], biome.get("radius", 5), map_seed)
	# 3. Clairières : l'emprise et une couronne restent en plaine (place pour les gares).
	for site: Dictionary in sites:
		_clear(map, site, site.get("clearing", 2))
	# 4. Rivière, puis site de pont.
	_draw_river(map, layout.get("river", {}).get("points", []))
	var bridge: Dictionary = layout.get("bridge", {})
	if bridge.has("center"):
		var center: Vector2i = Vector2i(bridge["center"][0], bridge["center"][1])
		var radius: int = bridge.get("radius", 1)
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				var cell: Vector2i = center + Vector2i(dx, dy)
				if map.in_bounds(cell) and map.get_terrain(cell) == Terrain.Type.WATER:
					map.bridge_cells[cell] = true
	return map


@warning_ignore("integer_division")
static func _decor_at(x: int, y: int, map_seed: int) -> int:
	var block: int = _hash(x / 5, y / 5, map_seed) % 100
	if block < 5:
		return Terrain.Type.HILL if _hash(x, y, map_seed + 2) % 100 < 70 else Terrain.Type.PLAINS
	if block < 15:
		return Terrain.Type.FOREST if _hash(x, y, map_seed + 1) % 100 < 70 else Terrain.Type.PLAINS
	return Terrain.Type.PLAINS


## Disque d'environnement autour du centre de l'emprise (coordonnées doublées : entiers exacts).
static func _stamp(map: WorldMap, site: Dictionary, terrain: int, radius: int, map_seed: int) -> void:
	var cx2: int = site["cell"][0] * 2 + site["size"][0]
	var cy2: int = site["cell"][1] * 2 + site["size"][1]
	var r2: int = (2 * radius) * (2 * radius)
	for y: int in range(site["cell"][1] - radius - 1, site["cell"][1] + site["size"][1] + radius + 1):
		for x: int in range(site["cell"][0] - radius - 1, site["cell"][0] + site["size"][0] + radius + 1):
			var cell: Vector2i = Vector2i(x, y)
			var dx: int = 2 * x + 1 - cx2
			var dy: int = 2 * y + 1 - cy2
			# Lisière irrégulière : quelques cases restent en plaine.
			if map.in_bounds(cell) and dx * dx + dy * dy <= r2 and _hash(x, y, map_seed + 7) % 100 < 88:
				map.set_terrain(cell, terrain)


static func _clear(map: WorldMap, site: Dictionary, ring: int) -> void:
	for y: int in range(site["cell"][1] - ring, site["cell"][1] + site["size"][1] + ring):
		for x: int in range(site["cell"][0] - ring, site["cell"][0] + site["size"][0] + ring):
			if map.in_bounds(Vector2i(x, y)):
				map.set_terrain(Vector2i(x, y), Terrain.Type.PLAINS)


## Rivière continue d'un point à l'autre, épaissie pour qu'aucun rail ne puisse la
## franchir en diagonale entre deux cases d'eau.
static func _draw_river(map: WorldMap, points: Array) -> void:
	for i: int in range(1, points.size()):
		var a: Vector2i = Vector2i(points[i - 1][0], points[i - 1][1])
		var b: Vector2i = Vector2i(points[i][0], points[i][1])
		for cell: Vector2i in Dir.step_path(a, b):
			for offset: Vector2i in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1)]:
				if map.in_bounds(cell + offset):
					map.set_terrain(cell + offset, Terrain.Type.WATER)


## Hachage entier 2D. Les entiers GDScript sont sur 64 bits avec débordement défini.
static func _hash(x: int, y: int, map_seed: int) -> int:
	var h: int = x * 374761393 + y * 668265263 + map_seed * 2147483647
	h = (h ^ (h >> 13)) * 1274126177
	return (h ^ (h >> 16)) & 0x7fffffff
