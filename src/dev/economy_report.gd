extends SceneTree
## Mesure de l'économie (développement) : joue des scénarios automatiques identiques avant
## et après un réglage, et imprime les mêmes indicateurs. Lancer : scripts/measure_economy.sh
##  A : partie optimale (réseau d'exemple, chaque bâtiment raccordé dès son déblocage).
##  B : comme la partie de Vincent : la carrière n'est raccordée que 20 min après le N2.

const Content = preload("res://src/data/content.gd")
const GameWorld = preload("res://src/sim/game_world.gd")
const WorldConfig = preload("res://src/data/world_config.gd")
const SampleNetwork = preload("res://src/dev/sample_network.gd")

const TICKS_PER_MIN: int = 300
const LIMIT_MIN: int = 240


func _init() -> void:
	_report("A, réseau optimal", 0)
	_report("B, carrière raccordée 20 min après le N2", 20)
	quit()


func _new_world() -> GameWorld:
	var content: Content = Content.new()
	content.load_from()
	var scenario: Dictionary = Content.parse_file("res://data/scenario_level1.json")
	var world: GameWorld = GameWorld.new()
	world.build(WorldConfig.new(), content, scenario)
	world.new_game(scenario)
	return world


func _report(name: String, quarry_delay_min: int) -> void:
	var w: GameWorld = _new_world()
	var sample: SampleNetwork = SampleNetwork.new()
	var sim: RefCounted = w.sim
	sample.build_level1(w)
	_line(w, sample.level1_line(w), 1)
	var level2_tick: int = -1
	var level3_tick: int = -1
	var coins_at: Dictionary = {}
	var quarry_built: bool = false
	var window_start_revenue: int = -1
	var window_revenue: int = -1
	var tick: int = 0
	while tick < LIMIT_MIN * TICKS_PER_MIN and level3_tick < 0:
		sim.advance_ticks(50)
		tick += 50
		if sim.progression.can_upgrade():
			sim.progression.upgrade()
			coins_at[sim.progression.level] = sim.economy.wallet_milli / 1000.0
			if sim.progression.level == 2:
				level2_tick = tick
				window_start_revenue = sim.economy.revenue_milli
			else:
				level3_tick = tick
				sim.trains.clear_lines_and_trains()
				sample.build_steel(w)
				sample.build_iron(w)
				_line(w, sample.full_line(w), 2)
		if level2_tick >= 0 and not quarry_built and tick >= level2_tick + quarry_delay_min * TICKS_PER_MIN:
			if quarry_delay_min > 0:
				window_revenue = sim.economy.revenue_milli - window_start_revenue
			quarry_built = true
			sim.trains.clear_lines_and_trains()
			sample.build_quarry(w)
			_line(w, sample.level2_line(w), 1)
	var upkeep: float = sim.economy.get("upkeep_milli") / 1000.0 if "upkeep_milli" in sim.economy else 0.0
	print("== %s" % name)
	print("   N2 : %s  |  N3 : %s" % [_minutes(level2_tick), _minutes(level3_tick)])
	print("   pièces juste après l'amélioration : N2 %.0f  |  N3 %.0f" % [coins_at.get(2, -1.0), coins_at.get(3, -1.0)])
	if quarry_delay_min > 0:
		print("   revenu pendant les %d min sans carrière : %.0f pièces" % [quarry_delay_min, window_revenue / 1000.0])
	print("   à la fin : revenu cumulé %.0f, dépenses d'exploitation %.0f, solde %.0f" % [
		sim.economy.revenue_milli / 1000.0, upkeep, sim.economy.wallet_milli / 1000.0])


func _line(w: GameWorld, stations: Array[int], trains: int) -> void:
	w.sim.trains.create_line(stations)
	for _i: int in trains:
		w.sim.trains.add_train(w.sim.trains.last_created_line_id)


func _minutes(tick: int) -> String:
	return "non atteint" if tick < 0 else "%.1f min" % (tick / float(TICKS_PER_MIN))
