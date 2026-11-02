extends RefCounted
## Une partie : carte, réseau, simulation. Construit les objets dans l'ordre voulu, sans
## nœud ni rendu. Sert au démarrage de Main, à la sauvegarde/reprise et aux tests.

const MapGenerator = preload("res://src/core/map_generator.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const GameSimulation = preload("res://src/sim/game_simulation.gd")
const SimParams = preload("res://src/sim/sim_params.gd")

var cfg: Resource
var content: RefCounted
var map: RefCounted
var network: RailNetwork
var sim: GameSimulation


## Crée une partie vide (carte et simulation, sans bâtiments ni pièces). Le scénario fixe
## la carte (taille, graine, version) et sa disposition : environnement des sites,
## rivière, site de pont. Sans scénario : la carte de la configuration.
func build(p_cfg: Resource, p_content: RefCounted, scenario: Dictionary = {}) -> void:
	cfg = p_cfg
	content = p_content
	var spec: Dictionary = scenario.get("map", {})
	map = MapGenerator.generate(spec.get("width", cfg.map_width), spec.get("height", cfg.map_height),
			spec.get("seed", cfg.map_seed), spec.get("generator_version", cfg.generator_version), layout_of(scenario))
	network = RailNetwork.new(map)
	var params: SimParams = SimParams.new(cfg.sim_step_sec, cfg.train_speed_cells_per_sec,
			cfg.station_dwell_sec, cfg.no_route_retry_sec, cfg.max_trains)
	sim = GameSimulation.new(params, cfg.sim_max_steps_per_frame, network, content)
	var bridge_level: int = scenario.get("bridge", {}).get("unlock_level", 2)
	network.water_crossing = func(cell: Vector2i) -> int:
		if not map.bridge_cells.has(cell):
			return 0
		return 1 if sim.progression.level >= bridge_level else 2


## Disposition pour le générateur : emprises (taille lue dans le contenu), environnements,
## rivière et pont. C'est cette structure qu'une génération procédurale produirait.
func layout_of(scenario: Dictionary) -> Dictionary:
	if scenario.is_empty():
		return {}
	var sites: Array = []
	for entry: Dictionary in scenario.get("buildings", []):
		var size: Vector2i = content.building_size(entry["type"])
		sites.append({"cell": entry["cell"], "size": [size.x, size.y], "biome": entry.get("biome", {}),
				"clearing": entry.get("clearing", 2)})
	return {"sites": sites, "river": scenario.get("river", {}), "bridge": scenario.get("bridge", {})}


## Nouvelle partie : bâtiments du scénario et pièces de départ.
func new_game(scenario: Dictionary) -> void:
	sim.industry.load_scenario(scenario)
	sim.economy.wallet_milli = content.build_cost("start_coins_milli", 0)
