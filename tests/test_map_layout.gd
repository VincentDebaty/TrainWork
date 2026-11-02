extends "res://tests/test_case.gd"
## Carte du prototype (générateur v2, scénario dispersé) : déterminisme, rivière et pont,
## environnements des sites, directions et distances depuis le dépôt.

const Fixture = preload("res://tests/game_fixture.gd")
const Terrain = preload("res://src/core/terrain.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const RailPlanner = preload("res://src/rail/rail_planner.gd")
const Dir = preload("res://src/rail/direction.gd")

var _f: Fixture = Fixture.new()


func _site(world: RefCounted, type_id: String) -> RefCounted:
	for id: int in world.sim.industry.buildings:
		if world.sim.industry.buildings[id].type_id == type_id:
			return world.sim.industry.buildings[id]
	return null


func test_map_is_80_by_80_and_reproducible() -> void:
	var a: RefCounted = _f.new_world()
	var b: RefCounted = _f.new_world()
	check_eq(a.map.size(), Vector2i(80, 80), "carte 80 x 80")
	check_eq(a.map.generator_version, 2, "générateur v2")
	check_eq(a.map.checksum(), b.map.checksum(), "même scénario => même carte")
	check(a.map.bridge_cells.size() >= 2, "un site de pont (%d cases)" % a.map.bridge_cells.size())


## Garde-fou : si ce nombre change, la carte du prototype a changé.
func test_pinned_checksum_v2() -> void:
	check_eq(_f.new_world().map.checksum(), PINNED_V2, "empreinte de la carte v2")


## Écran : x vers le sud-est, y vers le sud-ouest. Direction écran = (x - y, x + y).
func test_sites_are_dispersed_around_the_depot() -> void:
	var w: RefCounted = _f.new_world()
	var depot: Vector2 = _site(w, "depot").center_grid()
	var expected: Dictionary = {
		"coal_mine": ["nord-ouest", Vector2(-1, -1), 15, 20],
		"sawmill": ["sud-ouest", Vector2(-1, 1), 15, 20],
		"city": ["sud-est", Vector2(1, 1), 25, 30],
		"quarry": ["nord-est", Vector2(1, -1), 25, 35],
		"iron_mine": ["sud", Vector2(0, 1), 30, 40],
		"steelworks": ["est", Vector2(1, 0), 25, 35],
	}
	for type_id: String in expected:
		var offset: Vector2 = _site(w, type_id).center_grid() - depot
		var screen: Vector2 = Vector2(offset.x - offset.y, offset.x + offset.y).normalized()
		var rule: Array = expected[type_id]
		check(screen.dot(Vector2(rule[1]).normalized()) > 0.9, "%s au %s du dépôt (écran %s)" % [type_id, rule[0], str(screen)])
		var distance: float = offset.length()
		check(distance >= rule[2] - 1 and distance <= rule[3] + 1, "%s à %.0f cases (attendu %d-%d)" % [type_id, distance, rule[2], rule[3]])


func test_each_resource_has_its_environment() -> void:
	var w: RefCounted = _f.new_world()
	var wanted: Dictionary = {"sawmill": Terrain.Type.FOREST, "quarry": Terrain.Type.ROCK,
			"coal_mine": Terrain.Type.HILL, "iron_mine": Terrain.Type.HILL}
	for type_id: String in wanted:
		var site: RefCounted = _site(w, type_id)
		var count: int = 0
		for y: int in range(site.cell.y - 8, site.cell.y + 11):
			for x: int in range(site.cell.x - 8, site.cell.x + 11):
				if w.map.in_bounds(Vector2i(x, y)) and w.map.get_terrain(Vector2i(x, y)) == wanted[type_id]:
					count += 1
		check(count >= 20, "%s entouré de %s (%d cases)" % [type_id, Terrain.display_name(wanted[type_id]), count])


func test_room_around_every_site_for_stations() -> void:
	var w: RefCounted = _f.new_world()
	for id: int in w.sim.industry.buildings:
		var site: RefCounted = w.sim.industry.buildings[id]
		var free: int = 0
		for y: int in range(site.cell.y - 2, site.cell.y + site.size.y + 2):
			for x: int in range(site.cell.x - 2, site.cell.x + site.size.x + 2):
				var cell: Vector2i = Vector2i(x, y)
				if w.map.in_bounds(cell) and not site.contains(cell) and w.map.get_terrain(cell) == Terrain.Type.PLAINS:
					free += 1
		check(free >= 12, "%s : %d cases libres pour une gare" % [site.type_id, free])


## Aucune voie ne franchit la rivière sans le pont : recherche sur toute la carte.
func test_river_blocks_the_quarry_until_the_bridge_unlocks() -> void:
	var w: RefCounted = _f.new_world()
	var depot_side: Vector2i = Vector2i(40, 36)
	var quarry_side: Vector2i = Vector2i(40, 14)
	check_eq(RailPlanner.new().find_route(w.network, depot_side, quarry_side, 80).size(), 0, "niveau 1 : aucun tracé vers la carrière")
	var bridge: Vector2i = w.map.bridge_cells.keys()[0]
	var land: Vector2i = Vector2i(-1, -1)
	for d: int in 8:
		var n: Vector2i = bridge + Dir.VECTORS[d]
		if w.map.in_bounds(n) and w.map.get_terrain(n) == Terrain.Type.PLAINS:
			land = n
	check_eq(w.network.check_edge(land, bridge), RailNetwork.Result.BRIDGE_LOCKED, "message : pont au niveau 2")
	w.sim.progression.set_level(2)
	check_eq(w.network.check_edge(land, bridge), RailNetwork.Result.OK, "niveau 2 : le pont accepte les rails")
	var route: Array[Vector2i] = RailPlanner.new().find_route(w.network, depot_side, quarry_side, 80)
	check(route.size() > 0, "niveau 2 : tracé vers la carrière par le pont")
	var crosses: bool = false
	for cell: Vector2i in route:
		crosses = crosses or w.map.bridge_cells.has(cell)
	check(crosses, "le tracé passe par le pont")
	var water_off_bridge: bool = false
	for cell: Vector2i in route:
		water_off_bridge = water_off_bridge or (w.map.get_terrain(cell) == Terrain.Type.WATER and not w.map.bridge_cells.has(cell))
	check(not water_off_bridge, "jamais d'eau hors du pont")


func test_bridge_segments_cost_more() -> void:
	var w: RefCounted = _f.new_world()
	w.sim.progression.set_level(2)
	var bridge: Vector2i = w.map.bridge_cells.keys()[0]
	var land: Vector2i = Vector2i(-1, -1)
	for d: int in 8:
		var n: Vector2i = bridge + Dir.VECTORS[d]
		if w.map.in_bounds(n) and w.map.get_terrain(n) == Terrain.Type.PLAINS:
			land = n
	check_eq(w.sim.construction.edge_cost(land, bridge), 5000, "segment de pont : 5 pièces")
	check_eq(w.sim.construction.edge_cost(Vector2i(30, 33), Vector2i(31, 33)), 1000, "rail ordinaire : 1 pièce")


func test_future_sites_are_hidden_but_reserved() -> void:
	var w: RefCounted = _f.new_world()
	var quarry: RefCounted = _site(w, "quarry")
	check(not w.sim.industry.is_active(quarry), "carrière invisible au niveau 1")
	check_eq(w.network.place_station(quarry.cell, 0), RailNetwork.Result.RESERVED, "construire dessus : site réservé")
	check(RailNetwork.result_text(RailNetwork.Result.RESERVED).contains("réservé"), "message sans nommer le bâtiment")


func test_minimal_level_one_network_and_line() -> void:
	var w: RefCounted = _f.new_world()
	check(_f.sample.build_level1(w), "réseau du niveau 1")
	check(_f.line(w, _f.level1_line(w)), "ligne mine, dépôt, scierie, dépôt, ville praticable")
	check(w.sim.economy.wallet_milli >= 100000, "au moins la moitié du budget reste (%d)" % w.sim.economy.wallet_milli)


const PINNED_V2: int = 8146171567246908175
