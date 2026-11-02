extends "res://tests/test_case.gd"

const Fixture = preload("res://tests/game_fixture.gd")
const SaveGame = preload("res://src/persistence/save_game.gd")
const SaveStore = preload("res://src/persistence/save_store.gd")
const OfflineCatchup = preload("res://src/sim/offline_catchup.gd")
const Content = preload("res://src/data/content.gd")

const TEST_SAVE: String = "user://test_save_game.json"

var _f: Fixture = Fixture.new()


## Partie avancée et riche : niveau 3, deux trains en route, marchandises partout.
func _rich_world() -> RefCounted:
	var w: RefCounted = _f.new_world()
	w.sim.progression.set_level(3)
	w.sim.economy.wallet_milli = 100000
	w.sim.economy.wallet_milli = 1000000
	_f.sample.build_level1(w)
	_f.sample.build_quarry(w)
	_f.sample.build_steel(w)
	_f.sample.build_iron(w)
	_f.line(w, _f.sample.full_line(w), 2)
	_f.run(w, 1300)
	return w


func _restored_copy(source: RefCounted) -> RefCounted:
	var data: Variant = SaveGame.from_json(SaveGame.to_json(SaveGame.new().serialize(source, {}, 1000)))
	var copy: RefCounted = _f.new_world()
	# Partie vierge : sans bâtiments du scénario, pour que tout vienne de la sauvegarde.
	copy.sim.industry.buildings.clear()
	check_eq(SaveGame.new().restore(copy, data), "", "restauration sans erreur")
	return copy


func test_round_trip_restores_the_exact_state() -> void:
	var a: RefCounted = _rich_world()
	check(a.sim.trains.trains.size() == 2 and a.sim.industry.produced.size() > 0, "partie bien remplie")
	var b: RefCounted = _restored_copy(a)
	var save: SaveGame = SaveGame.new()
	check_eq(save.serialize(b, {}, 1000), save.serialize(a, {}, 1000), "même état logique après rechargement")
	check_eq(b.sim.state_checksum(), a.sim.state_checksum(), "même empreinte")
	check_eq(b.sim.tick, a.sim.tick, "même pas de simulation")
	check_eq(b.sim.economy.wallet_milli, a.sim.economy.wallet_milli, "mêmes pièces")
	check_eq(b.sim.progression.level, 3, "même niveau")
	check_eq(b.network.graph.edge_count(), a.network.graph.edge_count(), "mêmes rails")
	check_eq(b.network.station_count(), a.network.station_count(), "mêmes gares")
	for id: int in a.sim.trains.trains:
		var ta: RefCounted = a.sim.trains.trains[id]
		var tb: RefCounted = b.sim.trains.trains[id]
		check_eq([tb.cell, tb.progress_milli, tb.state, tb.path.size()], [ta.cell, ta.progress_milli, ta.state, ta.path.size()], "train %d : même position logique" % id)
		check_eq(tb.cargo.checksum(), ta.cargo.checksum(), "train %d : même cargaison" % id)
	for good: String in a.content.good_ids():
		check_eq(b.sim.matter_balance(good), 0, "bilan matière %s conservé" % good)


func test_simulation_continues_identically_after_loading() -> void:
	var a: RefCounted = _rich_world()
	var b: RefCounted = _restored_copy(a)
	for i: int in 20:
		a.sim.advance_ticks(50)
		b.sim.advance_ticks(50)
		if a.sim.state_checksum() != b.sim.state_checksum():
			check(false, "divergence après %d pas" % ((i + 1) * 50))
			return
	check(true, "1000 pas identiques")
	check_eq(SaveGame.new().serialize(b, {}, 1), SaveGame.new().serialize(a, {}, 1), "états identiques après la reprise")


func test_round_trip_survives_json_text_and_frame_rate() -> void:
	var a: RefCounted = _rich_world()
	var b: RefCounted = _restored_copy(a)
	var delta: float = 0.07
	var elapsed: float = 0.0
	while elapsed < 60.0:
		a.sim.advance(delta)
		b.sim.advance(delta)
		elapsed += delta
	check_eq(b.sim.state_checksum(), a.sim.state_checksum(), "l'accumulateur d'horloge est restauré : même résultat en temps réel")


func test_save_is_versioned_and_incompatible_saves_are_refused() -> void:
	var w: RefCounted = _rich_world()
	var save: SaveGame = SaveGame.new()
	var data: Dictionary = save.serialize(w, {}, 1)
	check_eq(data["save_version"], SaveGame.SAVE_VERSION, "version écrite")
	check_eq(save.check(w, data), "", "sauvegarde valide")
	var wrong_version: Dictionary = data.duplicate(true)
	wrong_version["save_version"] = 99
	check(save.check(w, wrong_version).contains("incompatible"), "version inconnue refusée")
	var wrong_map: Dictionary = data.duplicate(true)
	wrong_map["map"]["seed"] = 7
	check(save.check(w, wrong_map).contains("carte"), "autre carte refusée")
	var incomplete: Dictionary = data.duplicate(true)
	incomplete.erase("sim")
	check(save.check(w, incomplete).contains("incomplète"), "sauvegarde incomplète refusée")
	var fresh: RefCounted = _f.new_world()
	check(save.restore(fresh, wrong_version) != "", "restauration refusée")
	check_eq(fresh.network.graph.edge_count(), 0, "partie intacte après un refus")


func test_map_is_not_duplicated_in_the_save() -> void:
	var w: RefCounted = _rich_world()
	var text: String = SaveGame.to_json(SaveGame.new().serialize(w, {}, 1))
	check(text.length() < 60000, "sauvegarde compacte (%d octets)" % text.length())
	var data: Dictionary = SaveGame.from_json(text)
	check(not data["map"].has("cells"), "la carte n'est stockée que par sa graine")


func test_camera_view_is_kept() -> void:
	var w: RefCounted = _f.new_world()
	var data: Variant = SaveGame.from_json(SaveGame.to_json(SaveGame.new().serialize(w, {"x": 1234.5, "y": -87.25, "zoom": 1.75}, 1)))
	check_near(data["view"]["x"], 1234.5, "cadrage x")
	check_near(data["view"]["y"], -87.25, "cadrage y")
	check_near(data["view"]["zoom"], 1.75, "zoom")


func test_store_writes_atomically_and_falls_back_to_backup() -> void:
	var store: SaveStore = SaveStore.new(TEST_SAVE)
	store.delete()
	check(not store.exists(), "rien au départ")
	var w: RefCounted = _rich_world()
	var first: Dictionary = SaveGame.new().serialize(w, {}, 111)
	check(store.save(first), "première sauvegarde")
	check(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "pas de fichier temporaire laissé")
	_f.run(w, 100)
	var second: Dictionary = SaveGame.new().serialize(w, {}, 222)
	check(store.save(second), "seconde sauvegarde")
	check_eq(store.load_data()["saved_unix"], 222, "la dernière est lue")
	# Fermeture brutale pendant une écriture : le fichier principal est corrompu.
	var broken: FileAccess = FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	broken.store_string('{"save_version": 1, "sim": {')
	broken.close()
	var loaded: Variant = store.load_data()
	check(loaded != null, "repli sur la copie de secours")
	check_eq(loaded["saved_unix"], 111, "on retrouve la sauvegarde précédente")
	check_eq(SaveGame.new().check(_f.new_world(), loaded), "", "et elle est utilisable")
	store.delete()
	check(not store.exists() and store.load_data() == null, "suppression complète")


func test_store_refuses_to_replace_a_good_save_with_unwritable_data() -> void:
	var store: SaveStore = SaveStore.new(TEST_SAVE)
	store.delete()
	check(store.save({"save_version": 1, "saved_unix": 5}), "écriture simple")
	check(not SaveStore.new("user://dossier_inexistant/x.json").save({"a": 1}), "écriture impossible signalée")
	check_eq(store.load_data()["saved_unix"], 5, "l'ancienne sauvegarde reste")
	store.delete()


func test_offline_catch_up_is_capped_and_isolated() -> void:
	var w: RefCounted = _rich_world()
	var tick_before: int = w.sim.tick
	var catch_up: OfflineCatchup = OfflineCatchup.new()
	var short: Dictionary = catch_up.catch_up(w.sim, 30.0)
	check_eq(short["ticks"], 150, "30 s = 150 pas")
	check(not short["capped"], "sous le plafond")
	var long: Dictionary = catch_up.catch_up(w.sim, 86400.0)
	check(long["capped"], "24 h dépassent le plafond du prototype")
	check_eq(long["ticks"], 3000, "plafonné à 10 minutes de jeu (3000 pas)")
	check_eq(w.sim.tick, tick_before + 150 + 3000, "le temps de simulation a avancé d'autant")
	check_eq(catch_up.catch_up(w.sim, -50.0)["ticks"], 0, "durée négative ignorée")
	for good: String in w.content.good_ids():
		check_eq(w.sim.matter_balance(good), 0, "bilan matière %s après rattrapage" % good)
