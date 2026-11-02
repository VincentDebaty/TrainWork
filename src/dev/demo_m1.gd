extends Node
## Scène de démonstration (développement uniquement) : charge le jeu au niveau 3, y pose le
## réseau d'exemple complet (voir SampleNetwork) et lance deux trains sur la ligne qui
## dessert tous les bâtiments. Ne touche pas à la vraie sauvegarde.
## Lancer : godot --path . res://scenes/dev_demo_m1.tscn

const MAIN_SCENE: PackedScene = preload("res://scenes/main.tscn")
const SampleNetwork = preload("res://src/dev/sample_network.gd")


func _ready() -> void:
	var main: Node = MAIN_SCENE.instantiate()
	main.save_enabled = false
	add_child(main)
	var world: RefCounted = main._world
	world.sim.progression.set_level(3)  # deux trains autorisés
	world.sim.economy.wallet_milli = 1000000
	var sample: SampleNetwork = SampleNetwork.new()
	sample.build_level1(world)
	sample.build_quarry(world)
	sample.build_steel(world)
	sample.build_iron(world)
	var trains: RefCounted = world.sim.trains
	trains.create_line(sample.full_line(world))
	trains.add_train(trains.last_created_line_id)
	trains.add_train(trains.last_created_line_id)
	main._camera.set_view(main._projection.cell_center(Vector2i(14, 30)), 0.5)
