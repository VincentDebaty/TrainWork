extends "res://tests/test_case.gd"


func test_config_resource_loads_with_sane_values() -> void:
	var cfg: Resource = load("res://data/world_config.tres")
	check(cfg != null, "data/world_config.tres se charge")
	if cfg == null:
		return
	check(cfg.map_width > 0 and cfg.map_height > 0, "taille de carte positive")
	check(cfg.zoom_min > 0.0 and cfg.zoom_min < cfg.zoom_max, "bornes de zoom cohérentes")
	check(cfg.zoom_default >= cfg.zoom_min and cfg.zoom_default <= cfg.zoom_max, "zoom par défaut dans les bornes")
	check(cfg.sim_step_sec > 0.0, "pas de simulation positif")
	check_near(cfg.tile_width / cfg.tile_height, 2.0, "losange 2:1")


func test_main_scene_instantiates() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	check(scene != null, "scenes/main.tscn se charge")
	if scene == null:
		return
	var main: Node = scene.instantiate()
	main.save_enabled = false
	tree.root.add_child(main)
	check(main.get_node("Camera").view_zoom() > 0.0, "caméra configurée par Main")
	for node_name: String in ["WorldView", "RailView", "TrainView", "BuildController", "Hud/BuildToolbar"]:
		check(main.get_node_or_null(node_name) != null, "nœud %s présent" % node_name)
	var view: Rect2 = Rect2(Vector2.ZERO, main.get_viewport().get_visible_rect().size)
	check(view.encloses(main.get_node("Hud/BuildToolbar").get_global_rect()), "la barre d'outils reste dans l'écran")
	check(view.has_point(main.get_node("Hud/Info").get_global_rect().position), "le HUD reste dans l'écran")
	main.queue_free()


func test_main_saves_and_resumes_the_same_game() -> void:
	var path: String = "user://test_main_save.json"
	var store: RefCounted = (load("res://src/persistence/save_store.gd") as GDScript).new(path)
	store.delete()
	var scene: PackedScene = load("res://scenes/main.tscn")
	var first: Node = scene.instantiate()
	first.save_path = path
	tree.root.add_child(first)
	check_eq(first._simulation.economy.wallet_milli, 200000, "nouvelle partie : 200 pièces")
	first._simulation.construction.place_station(Vector2i(16, 38), 0)
	first._simulation.advance_ticks(40)
	first._camera.set_view(first._camera.position + Vector2(300, 120), 1.6)
	check(first.save_now(), "sauvegarde écrite")
	var expected: Dictionary = (load("res://src/persistence/save_game.gd") as GDScript).new().serialize(first._world, {}, 1)
	var camera_pos: Vector2 = first._camera.position
	first.save_enabled = false
	tree.root.remove_child(first)
	first.free()
	var second: Node = scene.instantiate()
	second.save_path = path
	tree.root.add_child(second)
	var got: Dictionary = (load("res://src/persistence/save_game.gd") as GDScript).new().serialize(second._world, {}, 1)
	check_eq(got["network"], expected["network"], "rails et gares repris")
	check_eq(got["sim"]["economy"], expected["sim"]["economy"], "pièces reprises (190)")
	check(second._simulation.tick >= expected["sim"]["tick"], "simulation reprise (+ rattrapage éventuel)")
	check_near_v(second._camera.position, camera_pos, "dernier cadrage conservé", 0.5)
	check_near(second._camera.view_zoom(), 1.6, "dernier zoom conservé")
	second.save_enabled = false
	second.queue_free()
	store.delete()
