extends "res://tests/test_case.gd"

const Content = preload("res://src/data/content.gd")
const GameSimulation = preload("res://src/sim/game_simulation.gd")
const SimParams = preload("res://src/sim/sim_params.gd")
const GoodsStock = preload("res://src/sim/goods_stock.gd")
const Building = preload("res://src/sim/building.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const WorldMap = preload("res://src/core/world_map.gd")
const Terrain = preload("res://src/core/terrain.gd")

const LR = preload("res://src/sim/train_simulator.gd").LineResult


class World:
	var content: Content
	var net: RailNetwork
	var sim: GameSimulation
	var deliveries: Array[Dictionary] = []


func _content() -> Content:
	var content: Content = Content.new()
	assert(content.load_from(), content.error)
	return content


## Mine en (2,2) 3x3, gare S1 en (6,3) ; ville en (20,2) 4x4, gare S2 en (18,3) ;
## voie droite entre les deux ; pas de ligne tant que le test ne la crée pas.
func _world(with_rails: bool = true, content: Content = null) -> World:
	var w: World = World.new()
	w.content = content if content != null else _content()
	w.net = RailNetwork.new(WorldMap.new(40, 40, 1, 1))
	w.sim = GameSimulation.new(SimParams.new(0.2, 2.0, 3.0, 1.0, 1), 25, w.net, w.content)
	w.sim.industry.add_building("coal_mine", Vector2i(2, 2))
	w.sim.industry.add_building("city", Vector2i(20, 2))
	w.net.place_station(Vector2i(6, 3), 0)
	w.net.place_station(Vector2i(18, 3), 0)
	if with_rails:
		for x: int in range(6, 18):
			w.net.place_edge(Vector2i(x, 3), Vector2i(x + 1, 3))
	w.sim.logistics.delivered.connect(func(good: String, qty: int, station: int, revenue: int) -> void:
		w.deliveries.append({"good": good, "qty": qty, "station": station, "revenue": revenue, "tick": w.sim.tick}))
	return w


func _launch(w: World) -> void:
	var s1: int = w.net.station_at(Vector2i(6, 3)).id
	var s2: int = w.net.station_at(Vector2i(18, 3)).id
	check_eq(w.sim.trains.create_line([s1, s2] as Array[int]), LR.OK, "ligne créée")
	check_eq(w.sim.trains.add_train(w.sim.trains.last_created_line_id), LR.OK, "train affecté")


func _run(w: World, ticks: int) -> void:
	for _i: int in ticks:
		w.sim._step()


func test_content_loads_and_validates() -> void:
	var content: Content = Content.new()
	check(content.load_from(), "content.json valide : %s" % content.error)
	check(content.goods.has("coal") and content.goods.has("wood"), "charbon et bois")
	check_eq(content.building_size("city"), Vector2i(4, 4), "taille lue en entiers")
	check_eq(content.buildings["coal_mine"]["cycle_ticks"], 15, "entiers, pas des flottants")
	check_eq(content.unlocked_goods(1), ["coal", "wood"] as Array[String], "produits du niveau 1")
	check_eq(content.unlocked_goods(3).size(), 5, "5 produits au niveau 3")
	check_eq(content.wagon_for("coal"), "coal_wagon", "un wagon par produit")
	check_eq(content.max_trains_for_level(1, 9), 1, "1 train au niveau 1")
	check_eq(content.max_trains_for_level(3, 9), 2, "2 trains au niveau 3")
	var bad: Content = Content.new()
	check(not bad.load_from("res://data/inexistant.json"), "fichier absent refusé")


func test_scenario_buildings_are_on_buildable_free_ground() -> void:
	var content: Content = _content()
	var scenario: Variant = Content.parse_file("res://data/scenario_level1.json")
	check(scenario is Dictionary, "scénario lisible")
	var map: WorldMap = (load("res://tests/game_fixture.gd") as GDScript).new().new_world().map
	var occupied: Dictionary = {}
	for entry: Dictionary in scenario["buildings"]:
		var size: Vector2i = content.building_size(entry["type"])
		var origin: Vector2i = Vector2i(entry["cell"][0], entry["cell"][1])
		for dx: int in size.x:
			for dy: int in size.y:
				var cell: Vector2i = origin + Vector2i(dx, dy)
				check(map.in_bounds(cell), "%s dans la carte" % str(cell))
				check(Terrain.is_buildable(map.get_terrain(cell)), "%s %s hors de l'eau" % [entry["type"], str(cell)])
				check(not occupied.has(cell), "%s sans chevauchement" % str(cell))
				occupied[cell] = true


func test_goods_stock_invariants() -> void:
	var stock: GoodsStock = GoodsStock.new(10)
	check_eq(stock.add("coal", 1, 7), 7, "ajout")
	check_eq(stock.add("coal", 2, 7), 3, "plafonné à la capacité")
	check_eq(stock.total("coal"), 10, "total")
	check_eq(stock.free_room("coal"), 0, "plein")
	var lots: Array[Vector2i] = stock.take("coal", 8)
	check_eq(lots, [Vector2i(1, 7), Vector2i(2, 1)] as Array[Vector2i], "plus anciens d'abord, origine conservée")
	check_eq(stock.total("coal"), 2, "reste")
	check_eq(stock.take("coal", 99).size(), 1, "retrait plafonné au contenu")
	check_eq(stock.total("coal"), 0, "jamais négatif")
	check_eq(stock.take("wood", 5).size(), 0, "produit absent")
	check_eq(stock.add("coal", 1, -4), 0, "quantité négative ignorée")
	stock.set_capacity("wood", 3)
	check_eq(stock.add("wood", 1, 9), 3, "capacité par produit")


func test_association_nearest_within_radius_and_shared() -> void:
	var w: World = _world(false)
	var mine: Building = w.sim.industry.building_at(Vector2i(3, 3))
	var s1: int = w.net.station_at(Vector2i(6, 3)).id
	check_eq(mine.station_id, s1, "mine rattachée à S1 (distance 2)")
	check_eq(w.sim.industry.building_at(Vector2i(21, 3)).station_id, w.net.station_at(Vector2i(18, 3)).id, "ville rattachée à S2")
	w.net.place_station(Vector2i(10, 10), 0)
	check_eq(mine.station_id, s1, "une gare hors rayon ne change rien")
	var near: int = w.net.place_station(Vector2i(5, 3), 0)
	check_eq(near, RailNetwork.Result.OK, "gare plus proche posée")
	check_eq(mine.station_id, w.net.station_at(Vector2i(5, 3)).id, "rattachement à la plus proche")
	w.net.remove_station(Vector2i(5, 3))
	check_eq(mine.station_id, s1, "retour à S1 quand la gare disparaît")
	w.net.remove_station(Vector2i(6, 3))
	check_eq(mine.station_id, 0, "aucune gare à portée : non rattachée")


func test_shared_station_serves_two_buildings() -> void:
	var w: World = _world(false)
	w.sim.industry.add_building("sawmill", Vector2i(2, 5))
	var sawmill: Building = w.sim.industry.building_at(Vector2i(3, 6))
	check_eq(sawmill.station_id, w.net.station_at(Vector2i(6, 3)).id, "scierie (2..4 x 5..7) : S1 à distance 2")
	_run(w, 100)
	var stock: GoodsStock = w.sim.industry.warehouse(sawmill.station_id)
	check(stock.total("coal") > 0 and stock.total("wood") > 0, "un entrepôt, deux produits séparés")


func test_association_does_not_move_stock() -> void:
	var w: World = _world(false)
	var s1: int = w.net.station_at(Vector2i(6, 3)).id
	_run(w, 60)
	var in_s1: int = w.sim.industry.warehouse(s1).total("coal")
	check(in_s1 > 0, "du charbon a été transféré à S1")
	w.net.place_station(Vector2i(5, 3), 0)
	check_eq(w.sim.industry.warehouse(s1).total("coal"), in_s1, "le stock de S1 ne bouge pas quand une gare plus proche apparaît")


func test_producer_stops_when_output_full_and_resumes() -> void:
	var w: World = _world(false)
	w.net.remove_station(Vector2i(6, 3))  # plus de gare : rien ne sort de la mine
	var mine: Building = w.sim.industry.building_at(Vector2i(3, 3))
	_run(w, 400)
	check_eq(mine.outputs["coal"], 20, "sortie plafonnée à 20")
	check_eq(mine.state, Building.State.OUTPUT_FULL, "état : sortie pleine")
	var produced: int = w.sim.industry.produced["coal"]
	_run(w, 100)
	check_eq(w.sim.industry.produced["coal"], produced, "ne produit plus tant que la sortie est pleine")
	mine.outputs["coal"] -= 6
	w.sim.industry.consumed["coal"] = w.sim.industry.consumed.get("coal", 0) + 6  # retrait pour le bilan
	_run(w, 40)
	check(w.sim.industry.produced["coal"] > produced, "reprend dès qu'il y a de la place")


func test_no_output_without_inputs_and_exact_recipe() -> void:
	var content: Content = _content()
	content.goods["plank"] = {"name": "Planche", "base_price_milli": 4000, "dist_price_milli": 0, "color": "#fff"}
	content.buildings["plank_mill"] = {"name": "Menuiserie", "size": [2, 2], "inputs": {"wood": 2}, "outputs": {"plank": 1},
			"cycle_ticks": 5, "input_cap": 10, "output_cap": 10, "color": "#fff"}
	var w: World = _world(false, content)
	var mill: Building = w.sim.industry.add_building("plank_mill", Vector2i(30, 30))
	_run(w, 100)
	check_eq(w.sim.industry.produced.get("plank", 0), 0, "aucune planche sans intrant")
	check_eq(mill.state, Building.State.WAITING_INPUT, "attend des intrants")
	mill.inputs["wood"] = 6
	w.sim.industry.consumed["wood"] = w.sim.industry.consumed.get("wood", 0) - 6  # intrants apportés de l'extérieur : bilan
	_run(w, 100)
	check_eq(w.sim.industry.produced["plank"], 3, "6 bois => exactement 3 planches")
	check_eq(mill.inputs["wood"], 0, "intrants consommés")


func test_full_chain_mine_station_train_station_city() -> void:
	var w: World = _world()
	_launch(w)
	var wallet_before_arrival: int = 0
	var first_delivery_tick: int = -1
	var cargo_seen: bool = false
	var mine: Building = w.sim.industry.building_at(Vector2i(3, 3))
	var city: Building = w.sim.industry.building_at(Vector2i(21, 3))
	var train: RefCounted = w.sim.trains.trains.values()[0]
	var wallet_prev: int = 0
	for _i: int in 1500:
		w.sim._step()
		# Bilan matière à chaque pas.
		for good: String in ["coal", "wood"]:
			check_eq(w.sim.industry.produced.get(good, 0) - w.sim.industry.consumed.get(good, 0),
					w.sim.matter_in_system(good), "bilan matière %s au pas %d" % [good, w.sim.tick])
		# Capacités.
		check(city.inputs["coal"] <= 30 and city.inputs["coal"] >= 0, "stock d'entrée de la ville dans [0, 30]")
		check(train.cargo.total("coal") <= 10 and train.cargo.total("wood") == 0, "cargaison dans la capacité, pas de bois sans scierie")
		check(w.sim.economy.wallet_milli >= 0, "solde jamais négatif")
		if train.cargo.total("coal") > 0:
			cargo_seen = true
			if first_delivery_tick < 0:
				wallet_before_arrival = w.sim.economy.wallet_milli
				check_eq(w.sim.economy.wallet_milli, 0, "aucune pièce tant que rien n'est livré")
		# Les pièces ne bougent que lors d'une livraison.
		if w.sim.economy.wallet_milli != wallet_prev:
			var this_tick: Array = w.deliveries.filter(func(d: Dictionary) -> bool: return d["tick"] == w.sim.tick)
			check(not this_tick.is_empty(), "variation des pièces au pas %d sans livraison" % w.sim.tick)
		wallet_prev = w.sim.economy.wallet_milli
		if first_delivery_tick < 0 and not w.deliveries.is_empty():
			first_delivery_tick = w.sim.tick
	check(cargo_seen, "le train a transporté du charbon")
	check(first_delivery_tick > 0, "au moins une livraison")
	check(w.sim.industry.delivered.get("coal", 0) > 0, "la ville a reçu du charbon")
	var revenue: int = 0
	var units: int = 0
	for d: Dictionary in w.deliveries:
		revenue += d["revenue"]
		units += d["qty"]
		check_eq(d["revenue"], d["qty"] * (3000 + 12 * 150), "prix = base + 12 segments x distance, par unité livrée")
		check_eq(d["station"], w.net.station_at(Vector2i(18, 3)).id, "livré à la gare de la ville")
	check_eq(w.sim.economy.wallet_milli, revenue, "pièces = somme des livraisons, une seule fois")
	check_eq(units, w.sim.industry.delivered["coal"], "unités livrées = registre")
	check(city.inputs["coal"] + w.sim.industry.consumed.get("coal", 0) >= units, "la ville a consommé ou stocke ce qu'elle a reçu")
	check(mine.outputs["coal"] <= 20, "sortie de la mine plafonnée")


func test_train_loads_only_what_someone_demands() -> void:
	var w: World = _world()
	w.net.remove_station(Vector2i(18, 3))
	w.net.place_station(Vector2i(18, 3), 0)  # même gare, mais aucun consommateur à sa portée
	w.sim.industry.buildings.erase(w.sim.industry.building_at(Vector2i(21, 3)).id)
	w.sim.industry.refresh_associations()
	_launch(w)
	var train: RefCounted = w.sim.trains.trains.values()[0]
	_run(w, 600)
	check_eq(train.cargo.total("coal"), 0, "personne ne demande de charbon : le train n'en charge pas")
	var s1: int = w.net.station_at(Vector2i(6, 3)).id
	check_eq(w.sim.industry.warehouse(s1).total("coal"), 40, "le charbon s'accumule dans l'entrepôt jusqu'à sa capacité")
	check_eq(w.deliveries.size(), 0, "aucun revenu")


func test_full_city_leaves_cargo_aboard() -> void:
	var w: World = _world()
	var city: Building = w.sim.industry.building_at(Vector2i(21, 3))
	_launch(w)
	var train: RefCounted = w.sim.trains.trains.values()[0]
	_run(w, 200)  # le train a chargé et livré une première fois
	city.inputs["coal"] = 30  # ville pleine
	w.sim.industry.consumed["coal"] = w.sim.industry.consumed.get("coal", 0) - (30 - 0)  # bilan : stock injecté
	var delivered_before: int = w.sim.industry.delivered.get("coal", 0)
	var aboard_before: int = train.cargo.total("coal")
	_run(w, 5)
	check(city.inputs["coal"] <= 30, "capacité de la ville respectée")
	check(w.sim.industry.delivered.get("coal", 0) >= delivered_before, "aucune livraison négative")
	if train.state == 0 and aboard_before > 0:
		check(train.cargo.total("coal") <= aboard_before, "cargaison non livrée conservée à bord")


func test_handling_time_is_proportional_to_volume() -> void:
	var content: Content = _content()
	content.logistics["load_units_per_tick"] = 1  # 1 unité/pas : 10 unités => 10 pas ; on veut dépasser l'arrêt minimal (15)
	var w: World = _world(true, content)
	var s1: int = w.net.station_at(Vector2i(6, 3)).id
	_run(w, 400)  # l'entrepôt de S1 se remplit
	var s2: int = w.net.station_at(Vector2i(18, 3)).id
	w.sim.trains.create_line([s1, s2] as Array[int])
	w.sim.trains.add_train(w.sim.trains.last_created_line_id)
	var train: RefCounted = w.sim.trains.trains.values()[0]
	check_eq(train.cargo.total("coal"), 10, "wagon rempli au départ")
	check_eq(train.dwell_left, 15, "10 unités à 1/pas : 10 pas < arrêt minimal 15")
	var content2: Content = _content()
	content2.logistics["load_units_per_tick"] = 1
	content2.wagons["coal_wagon"]["capacity"] = 30
	var w2: World = _world(true, content2)
	_run(w2, 400)
	var a: int = w2.net.station_at(Vector2i(6, 3)).id
	var b: int = w2.net.station_at(Vector2i(18, 3)).id
	w2.sim.trains.create_line([a, b] as Array[int])
	w2.sim.trains.add_train(w2.sim.trains.last_created_line_id)
	var big: RefCounted = w2.sim.trains.trains.values()[0]
	check_eq(big.cargo.total("coal"), 30, "30 unités chargées")
	check_eq(big.dwell_left, 30, "arrêt allongé : 30 unités à 1 par pas")


func test_determinism_and_frame_rate_independence() -> void:
	var sums: Array[int] = []
	for delta: float in [0.02, 0.1, 0.05]:
		var w: World = _world()
		_launch(w)
		for _i: int in roundi(240.0 / delta):
			w.sim.advance(delta)
		sums.append(w.sim.state_checksum())
	check_eq(sums[0], sums[1], "50 FPS = 10 FPS")
	check_eq(sums[0], sums[2], "50 FPS = 20 FPS")


func test_economy_never_negative() -> void:
	var w: World = _world(false)
	check(not w.sim.economy.spend(1), "dépense impossible à solde nul")
	w.sim.economy.credit(5000)
	check(w.sim.economy.spend(5000), "dépense exacte acceptée")
	check(not w.sim.economy.spend(1), "plus rien")
	check_eq(w.sim.economy.wallet_milli, 0, "solde à zéro, jamais négatif")
	check(not w.sim.economy.spend(-5), "dépense négative refusée")


func test_buildings_block_rails_and_stations() -> void:
	var w: World = _world(false)
	check_eq(w.net.place_station(Vector2i(3, 3), 0), RailNetwork.Result.OCCUPIED, "pas de gare sur la mine")
	check_eq(w.net.place_edge(Vector2i(5, 3), Vector2i(5, 4)), RailNetwork.Result.OK, "rail à côté de la mine : permis")
	check_eq(w.net.place_edge(Vector2i(3, 3), Vector2i(4, 3)), RailNetwork.Result.OCCUPIED, "pas de rail sur la mine")
	check_eq(w.net.place_edge(Vector2i(21, 1), Vector2i(21, 2)), RailNetwork.Result.OCCUPIED, "pas de rail sur la ville")



## Reproduit la partie de Vincent (2026-11-02) : en revenant de la carrière, le train passe
## par la ville avant le dépôt. La pierre doit d'abord aller au dépôt (priorité du GDD).
func test_depot_gets_its_materials_even_if_the_city_comes_first() -> void:
	var content: Content = _content()
	var w: World = World.new()
	w.content = content
	w.net = RailNetwork.new(WorldMap.new(40, 40, 1, 1))
	w.sim = GameSimulation.new(SimParams.new(0.2, 2.0, 3.0, 1.0, 1), 25, w.net, content)
	w.sim.progression.set_level(2)
	w.sim.industry.add_building("quarry", Vector2i(3, 5))  # gare Q en (6,3)
	w.sim.industry.add_building("city", Vector2i(11, 5))  # gare C en (12,3)
	w.sim.industry.add_building("depot", Vector2i(23, 5))  # gare D en (24,3)
	for x: int in [6, 12, 24]:
		w.net.place_station(Vector2i(x, 3), 0)
	for x: int in range(6, 24):
		w.net.place_edge(Vector2i(x, 3), Vector2i(x + 1, 3))
	var q: int = w.net.station_at(Vector2i(6, 3)).id
	var c: int = w.net.station_at(Vector2i(12, 3)).id
	var d: int = w.net.station_at(Vector2i(24, 3)).id
	check_eq(w.sim.trains.create_line([q, c, d] as Array[int]), LR.OK, "ligne carrière, ville, dépôt")
	check_eq(w.sim.trains.add_train(w.sim.trains.last_created_line_id), LR.OK, "train")
	var depot: Building = w.sim.progression.depot()
	var ticks: int = 0
	while depot.inputs.get("stone", 0) < 20 and ticks < 3000:
		w.sim._step()
		ticks += 1
	check_eq(depot.inputs.get("stone", 0), 20, "le dépôt reçoit ses 20 pierres (%d pas)" % ticks)
	check_eq(w.sim.progression.city_delivered.get("stone", 0), 0, "la ville, pourtant sur le chemin, n'a rien pris avant que le dépôt soit servi")
	for good: String in ["stone"]:
		check_eq(w.sim.matter_balance(good), 0, "bilan matière %s" % good)
