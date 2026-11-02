extends RefCounted
## Parties de test prêtes à l'emploi : contenu réel, scénario dispersé, réseau d'exemple.
## Aucune assertion ici : les tests vérifient.

const Content = preload("res://src/data/content.gd")
const GameWorld = preload("res://src/sim/game_world.gd")
const WorldConfig = preload("res://src/data/world_config.gd")
const SampleNetwork = preload("res://src/dev/sample_network.gd")

const LR = preload("res://src/sim/train_simulator.gd").LineResult

var sample: SampleNetwork = SampleNetwork.new()


## Partie neuve : contenu réel, scénario, pièces de départ.
func new_world() -> GameWorld:
	var content: Content = Content.new()
	content.load_from()
	var scenario: Dictionary = Content.parse_file("res://data/scenario_level1.json")
	var world: GameWorld = GameWorld.new()
	world.build(WorldConfig.new(), content, scenario)
	world.new_game(scenario)
	return world


## Crée une ligne et y affecte `trains` trains. Renvoie false au premier échec.
func line(world: GameWorld, stations: Array[int], trains: int = 1) -> bool:
	if world.sim.trains.create_line(stations) != LR.OK:
		return false
	for _i: int in trains:
		if world.sim.trains.add_train(world.sim.trains.last_created_line_id) != LR.OK:
			return false
	return true


func level1_line(world: GameWorld) -> Array[int]:
	return sample.level1_line(world)


func run(world: GameWorld, ticks: int) -> void:
	world.sim.advance_ticks(ticks)
