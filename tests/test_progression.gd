extends "res://tests/test_case.gd"

const Fixture = preload("res://tests/game_fixture.gd")
const Progression = preload("res://src/sim/progression.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const Building = preload("res://src/sim/building.gd")
const Dir = preload("res://src/rail/direction.gd")

var _f: Fixture = Fixture.new()


func _depot(world: RefCounted) -> Building:
	return world.sim.progression.depot()


func test_new_game_starts_at_level_one_with_budget() -> void:
	var w: RefCounted = _f.new_world()
	check_eq(w.sim.progression.level, 1, "niveau 1")
	check_eq(w.sim.economy.wallet_milli, 200000, "200 pièces de départ")
	check_eq(w.sim.trains.max_trains(), 1, "1 train au niveau 1")


func test_initial_network_fits_budget_with_margin() -> void:
	var w: RefCounted = _f.new_world()
	check(_f.sample.build_level1(w), "réseau minimal du niveau 1 posé : mine, scierie, ville")
	var spent: int = 200000 - w.sim.economy.wallet_milli
	check(spent <= 100000, "le réseau minimal coûte au plus la moitié du budget (%d milli-pièces)" % spent)
	check(spent >= 60000, "les bâtiments sont dispersés : le réseau n'est pas trivial (%d)" % spent)
	check(_f.line(w, _f.level1_line(w)), "la ligne du niveau 1 est praticable")


func test_locked_buildings_are_inert_but_reserve_their_ground() -> void:
	var w: RefCounted = _f.new_world()
	var quarry: Building = w.sim.industry.building_at(Vector2i(39, 18))
	check(quarry != null and quarry.type_id == "quarry", "la carrière existe")
	check(not w.sim.industry.is_active(quarry), "verrouillée au niveau 1")
	check(w.sim.industry.is_active(w.sim.industry.building_at(Vector2i(28, 40))), "la mine est active")
	_f.sample.station(w, "quarry")
	_f.run(w, 600)
	check_eq(quarry.station_id, 0, "pas de rattachement tant qu'elle est verrouillée")
	check_eq(w.sim.industry.produced.get("stone", 0), 0, "ne produit pas")
	check_eq(w.network.place_station(Vector2i(39, 18), 0), RailNetwork.Result.RESERVED, "son emplacement est réservé, sans le dévoiler")


func test_depot_wants_exactly_the_next_level_materials() -> void:
	var w: RefCounted = _f.new_world()
	var depot: Building = _depot(w)
	check(depot != null, "dépôt actif")
	check_eq(w.sim.industry.input_cap(depot, "wood"), 20, "20 bois")
	check_eq(w.sim.industry.input_cap(depot, "coal"), 20, "20 charbon")
	check_eq(w.sim.industry.input_cap(depot, "stone"), 0, "pas de pierre au niveau 1")
	check(not w.sim.industry.accepts(depot, "stone"), "n'accepte pas la pierre")
	depot.inputs["wood"] = 20
	check_eq(w.sim.industry.input_room(depot, "wood"), 0, "plein : 20/20")


func test_city_demands_only_unlocked_goods() -> void:
	var w: RefCounted = _f.new_world()
	var city: Building = w.sim.industry.building_at(Vector2i(59, 40))
	check(w.sim.industry.accepts(city, "coal") and w.sim.industry.accepts(city, "wood"), "charbon et bois")
	check(not w.sim.industry.accepts(city, "stone") and not w.sim.industry.accepts(city, "steel"), "ni pierre ni acier au niveau 1")
	w.sim.progression.set_level(2)
	check(w.sim.industry.accepts(city, "stone") and not w.sim.industry.accepts(city, "steel"), "la pierre au niveau 2")
	w.sim.progression.set_level(3)
	check(w.sim.industry.accepts(city, "steel"), "l'acier au niveau 3")


func test_depot_has_priority_and_pays_nothing() -> void:
	var w: RefCounted = _f.new_world()
	_f.sample.build_level1(w)
	var depot_station: int = _f.sample.id_of(w, "depot")
	var city_station: int = _f.sample.id_of(w, "city")
	var at_depot: Array[Building] = w.sim.industry.consumers_at(depot_station, "coal")
	check_eq(at_depot.size(), 1, "le dépôt a sa propre gare")
	check_eq(at_depot[0].type_id, "depot", "le dépôt est desservi")
	check_eq(w.sim.industry.consumers_at(city_station, "coal")[0].type_id, "city", "la ville est une destination distincte")
	_f.line(w, _f.level1_line(w))
	_f.run(w, 3000)
	var depot: Building = _depot(w)
	check(depot.inputs.get("coal", 0) > 0, "le dépôt a reçu du charbon")
	check(depot.inputs.get("coal", 0) <= 20 and depot.inputs.get("wood", 0) <= 20, "plafonné aux besoins du niveau")
	# Revenu = uniquement les livraisons à la ville.
	var city: Building = w.sim.industry.building_at(Vector2i(59, 40))
	var city_units: int = w.sim.progression.city_delivered.get("coal", 0) + w.sim.progression.city_delivered.get("wood", 0)
	check(city_units > 0, "la ville a aussi été livrée")
	check(w.sim.economy.revenue_milli > 0, "revenus générés")
	for good: String in ["coal", "wood"]:
		check_eq(w.sim.matter_balance(good), 0, "bilan matière %s" % good)
	check(city != null, "ville présente")


func test_upgrade_requires_coins_materials_and_objectives() -> void:
	var w: RefCounted = _f.new_world()
	var prog: Progression = w.sim.progression
	var depot: Building = _depot(w)
	check(not prog.can_upgrade(), "rien de réuni")
	w.sim.economy.wallet_milli = 75000
	check(not prog.can_upgrade(), "pièces seules : insuffisant")
	depot.inputs["wood"] = 20
	depot.inputs["coal"] = 20
	check(not prog.can_upgrade(), "pièces + matériaux sans objectif : insuffisant")
	prog.city_delivered = {"coal": 40}
	check(not prog.can_upgrade(), "40 unités mais d'un seul produit : insuffisant")
	prog.city_delivered = {"coal": 30, "wood": 10}
	check(prog.can_upgrade(), "tout est réuni")
	w.sim.economy.wallet_milli = 74999
	check(not prog.can_upgrade(), "il manque une fraction de pièce")
	check_eq(prog.upgrade(), Progression.Result.NOT_READY, "amélioration refusée")
	check_eq(prog.level, 1, "niveau inchangé")


func test_upgrade_consumes_coins_and_materials_and_resets_objectives() -> void:
	var w: RefCounted = _f.new_world()
	var prog: Progression = w.sim.progression
	var depot: Building = _depot(w)
	w.sim.economy.wallet_milli = 100000
	depot.inputs["wood"] = 20
	depot.inputs["coal"] = 20
	w.sim.industry.produced["wood"] = 20  # matière injectée, pour garder le bilan à l'équilibre
	w.sim.industry.produced["coal"] = 20
	prog.city_delivered = {"coal": 25, "wood": 25}
	var levels: Array[int] = []
	prog.level_changed.connect(func(l: int) -> void: levels.append(l))
	check_eq(prog.upgrade(), Progression.Result.OK, "amélioration")
	check_eq(prog.level, 2, "niveau 2")
	check_eq(levels, [2] as Array[int], "signal émis")
	check_eq(w.sim.economy.wallet_milli, 25000, "75 pièces débitées")
	check_eq(depot.inputs.get("wood", 0), 0, "bois du dépôt consommé")
	check_eq(depot.inputs.get("coal", 0), 0, "charbon du dépôt consommé")
	check(prog.city_delivered.is_empty(), "objectifs recomptés depuis le début du niveau")
	for good: String in ["wood", "coal"]:
		check_eq(w.sim.matter_balance(good), 0, "bilan matière %s après amélioration" % good)
	check_eq(w.sim.industry.input_cap(depot, "stone"), 20, "le dépôt attend maintenant 20 pierre")
	check(w.sim.industry.is_active(w.sim.industry.building_at(Vector2i(39, 18))), "la carrière est débloquée")


func test_unlocks_wagons_and_train_capacity() -> void:
	var w: RefCounted = _f.new_world()
	_f.sample.build_level1(w)
	_f.line(w, _f.level1_line(w))
	var train: RefCounted = w.sim.trains.trains.values()[0]
	check_eq(train.cargo.capacity("stone"), 0, "pas de wagon pierre au niveau 1")
	check_eq(train.cargo.capacity("coal"), 10, "wagon charbon")
	w.sim.progression.set_level(2)
	check_eq(train.cargo.capacity("stone"), 10, "wagon pierre ajouté au train existant")
	check_eq(train.cargo.capacity("steel"), 0, "pas encore d'acier")
	check_eq(w.sim.trains.max_trains(), 1, "toujours 1 train au niveau 2")
	w.sim.progression.set_level(3)
	check_eq(train.cargo.capacity("steel"), 10, "wagon acier au niveau 3")
	check_eq(w.sim.trains.max_trains(), 2, "2 trains au niveau 3")


func test_upgrade_refused_without_depot_or_at_max_level() -> void:
	var w: RefCounted = _f.new_world()
	w.sim.progression.set_level(3)
	check_eq(w.sim.progression.upgrade(), Progression.Result.MAX_LEVEL, "niveau maximal")
	var w2: RefCounted = _f.new_world()
	w2.sim.industry.buildings.erase(_depot(w2).id)
	check_eq(w2.sim.progression.upgrade(), Progression.Result.NO_DEPOT, "pas de dépôt")


func test_construction_costs_refunds_and_never_negative() -> void:
	var w: RefCounted = _f.new_world()
	var c: RefCounted = w.sim.construction
	var edges: Array[Vector4i] = [Dir.pair(Vector2i(44, 33), Vector2i(45, 33)), Dir.pair(Vector2i(45, 33), Vector2i(46, 33))]
	check_eq(c.quote_edges(edges), 2000, "2 rails : 2 pièces")
	w.sim.economy.wallet_milli = 100000
	var report: Dictionary = c.place_edges(edges)
	check_eq(report["placed"], 2, "posés")
	check_eq(w.sim.economy.wallet_milli, 98000, "2 pièces débitées")
	check(c.remove_edge(Vector2i(45, 33), Vector2i(46, 33)), "retrait")
	check_eq(w.sim.economy.wallet_milli, 98500, "50 % remboursés")
	check_eq(c.place_station(Vector2i(44, 33), 0), RailNetwork.Result.OK, "gare")
	check_eq(w.sim.economy.wallet_milli, 88500, "gare : 10 pièces")
	check(c.remove_station(Vector2i(44, 33)), "retrait de gare")
	check_eq(w.sim.economy.wallet_milli, 93500, "5 pièces remboursées")
	# Solde insuffisant : refus total, solde intact.
	w.sim.economy.wallet_milli = 1500
	var big: Array[Vector4i] = []
	for x: int in range(46, 52):
		big.append(Dir.pair(Vector2i(x, 33), Vector2i(x + 1, 33)))
	var refused: Dictionary = c.place_edges(big)
	check(refused["insufficient"] and refused["placed"] == 0, "pose trop chère refusée en entier")
	check_eq(refused["needed"], 6000, "montant nécessaire indiqué")
	check_eq(w.sim.economy.wallet_milli, 1500, "solde intact")
	check_eq(c.place_station(Vector2i(48, 33), 0), RailNetwork.Result.INSUFFICIENT_FUNDS, "gare refusée faute de pièces")
	check_eq(w.network.station_count(), 0, "aucune gare posée")


func test_construction_undo_is_money_neutral() -> void:
	var w: RefCounted = _f.new_world()
	var c: RefCounted = w.sim.construction
	var edges: Array[Vector4i] = [Dir.pair(Vector2i(44, 33), Vector2i(45, 33)), Dir.pair(Vector2i(45, 33), Vector2i(46, 33))]
	var placed: Array[Vector4i] = c.place_edges(edges)["placed_edges"]
	check_eq(c.undo_added(placed), 0, "annulation de la pose")
	check_eq(w.sim.economy.wallet_milli, 200000, "remboursement intégral à l'annulation")
	c.place_edges(edges)
	c.remove_edge(Vector2i(44, 33), Vector2i(45, 33))
	var after_removal: int = w.sim.economy.wallet_milli
	check(c.undo_removed([Dir.pair(Vector2i(44, 33), Vector2i(45, 33))] as Array[Vector4i]), "annulation du retrait")
	check_eq(w.sim.economy.wallet_milli, after_removal - 500, "le remboursement est rendu")
	w.sim.economy.wallet_milli = 0
	check(not c.undo_removed([Dir.pair(Vector2i(44, 33), Vector2i(45, 33))] as Array[Vector4i]), "annulation impossible sans pièces")
	check(w.sim.economy.wallet_milli >= 0, "solde jamais négatif")


func test_clearing_trains_records_the_lost_cargo() -> void:
	var w: RefCounted = _f.new_world()
	_f.sample.build_level1(w)
	_f.line(w, _f.level1_line(w))
	_f.run(w, 900)
	w.sim.trains.clear_lines_and_trains()
	for good: String in ["coal", "wood"]:
		check_eq(w.sim.matter_balance(good), 0, "bilan %s après retrait des trains" % good)
	w.network.remove_station(_f.sample.cell_of("mine"))
	for good: String in ["coal", "wood"]:
		check_eq(w.sim.matter_balance(good), 0, "bilan %s après suppression de la gare" % good)


## Critère de validation de M5 (avis de ChatGPT) : partir du niveau 1, gagner des pièces,
## alimenter le dépôt et atteindre le niveau 3 sans toucher aux données.
func test_full_playthrough_from_level_one_to_three() -> void:
	var w: RefCounted = _f.new_world()
	var prog: Progression = w.sim.progression
	check(_f.sample.build_level1(w), "réseau du niveau 1 dans le budget")
	check(_f.line(w, _f.level1_line(w)), "ligne du niveau 1")
	var reached: Dictionary = {}
	var ticks: int = 0
	while prog.level < 3 and ticks < 60000:
		w.sim.advance_ticks(50)
		ticks += 50
		check(w.sim.economy.wallet_milli >= 0, "solde jamais négatif (pas %d)" % ticks)
		if prog.can_upgrade():
			check_eq(prog.upgrade(), Progression.Result.OK, "amélioration à partir du niveau %d" % prog.level)
			reached[prog.level] = ticks
			w.sim.trains.clear_lines_and_trains()
			if prog.level == 2:
				check(_f.sample.build_quarry(w), "gare, pont et voie de la carrière payés")
				check(_f.line(w, _f.sample.level2_line(w)), "ligne du niveau 2")
			elif prog.level == 3:
				check(_f.sample.build_steel(w) and _f.sample.build_iron(w), "aciérie et mine de fer raccordées et payées")
				check(_f.line(w, _f.sample.full_line(w), 2), "ligne du niveau 3 avec 2 trains")
	check_eq(prog.level, 3, "niveau 3 atteint en %d pas (%d s de jeu)" % [ticks, ticks / 5])
	check(reached.has(2) and reached.has(3), "niveaux 2 et 3 franchis dans l'ordre")
	check_eq(w.sim.trains.trains.size(), 2, "deux trains au niveau 3")
	# Niveau 3 : la chaîne du fer à l'acier fonctionne et l'acier arrive en ville.
	var steel_ticks: int = 0
	while w.sim.industry.delivered.get("steel", 0) == 0 and steel_ticks < 20000:
		w.sim.advance_ticks(50)
		steel_ticks += 50
	check(w.sim.industry.delivered.get("steel", 0) > 0, "de l'acier a été livré à la ville (%d pas)" % steel_ticks)
	check(w.sim.industry.produced.get("steel", 0) > 0 and w.sim.industry.produced.get("iron_ore", 0) > 0, "minerai extrait et acier produit")
	check(w.sim.trains.deadlocked.is_empty(), "pas d'interblocage")
	for good: String in w.content.good_ids():
		check_eq(w.sim.matter_balance(good), 0, "bilan matière %s" % good)
