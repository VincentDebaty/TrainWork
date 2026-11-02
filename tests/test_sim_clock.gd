extends "res://tests/test_case.gd"

const GameSimulation = preload("res://src/sim/game_simulation.gd")
const SimParams = preload("res://src/sim/sim_params.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const WorldMap = preload("res://src/core/world_map.gd")


func _sim() -> GameSimulation:
	return GameSimulation.new(SimParams.new(0.2), 25, RailNetwork.new(WorldMap.new(8, 8, 1, 1)))


func _run(deltas: Array[float], repeats: int) -> int:
	var sim: GameSimulation = _sim()
	for _i: int in repeats:
		for d: float in deltas:
			sim.advance(d)
	return sim.tick


## 10 s de temps réel découpées de façons différentes => même nombre de pas (50).
func test_tick_count_independent_of_frame_splitting() -> void:
	check_eq(_run([0.02] as Array[float], 500), 50, "50 FPS")
	check_eq(_run([0.04] as Array[float], 250), 50, "25 FPS")
	check_eq(_run([0.1] as Array[float], 100), 50, "10 FPS")
	check_eq(_run([0.016, 0.034, 0.05] as Array[float], 100), 50, "cadence irrégulière")
	check_eq(_run([0.5] as Array[float], 20), 50, "gros pas de 0,5 s")


func test_sim_time_matches_ticks() -> void:
	var sim: GameSimulation = _sim()
	sim.advance(1.0)
	check_eq(sim.tick, 5, "1 s = 5 pas")
	check_near(sim.sim_time_sec(), 1.0, "temps de simulation")


func test_remainder_is_carried_over() -> void:
	var sim: GameSimulation = _sim()
	check_eq(sim.advance(0.15), 0, "pas assez pour un pas")
	check_eq(sim.advance(0.05), 1, "le reste s'accumule")


func test_spiral_guard_caps_steps() -> void:
	var sim: GameSimulation = _sim()
	check_eq(sim.advance(60.0), 25, "plafond de pas par frame")
	check_eq(sim.advance(0.0), 0, "retard abandonné, pas de rattrapage infini")


func test_negative_delta_ignored() -> void:
	var sim: GameSimulation = _sim()
	sim.advance(-5.0)
	check_eq(sim.tick, 0, "delta négatif ignoré")
