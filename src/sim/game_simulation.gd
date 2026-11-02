extends RefCounted
## Simulation du jeu : horloge à pas fixe, industrie, économie, lignes et trains.
## Ne référence AUCUN nœud ni la caméra.

const SimClock = preload("res://src/sim/sim_clock.gd")
const SimParams = preload("res://src/sim/sim_params.gd")
const TrainSimulator = preload("res://src/sim/train_simulator.gd")
const Industry = preload("res://src/sim/industry.gd")
const Economy = preload("res://src/sim/economy.gd")
const Logistics = preload("res://src/sim/logistics.gd")
const Progression = preload("res://src/sim/progression.gd")
const Construction = preload("res://src/sim/construction.gd")
const Content = preload("res://src/data/content.gd")

var tick: int = 0
var clock: SimClock
var content: Content
var economy: Economy
var industry: Industry
var logistics: Logistics
var progression: Progression
var construction: Construction
var trains: TrainSimulator


## `p_content` : contenu de jeu ; sans contenu, simulation sans marchandises.
func _init(params: SimParams, max_steps_per_advance: int, network: RefCounted, p_content: Content = null) -> void:
	clock = SimClock.new(params.step_sec, max_steps_per_advance)
	content = p_content if p_content != null else Content.new()
	economy = Economy.new()
	industry = Industry.new(content, network)
	logistics = Logistics.new(content, industry, economy, network)
	trains = TrainSimulator.new(network, params)
	trains.content = content
	trains.logistics = logistics
	logistics.booked_elsewhere = trains.booked_by_others
	progression = Progression.new(content, industry, economy)
	progression.trains = trains
	industry.progression = progression
	logistics.progression = progression
	trains.progression = progression
	construction = Construction.new(content, economy, network)


## Fait avancer la simulation de `delta_sec` secondes réelles. Renvoie le nombre de pas exécutés.
func advance(delta_sec: float) -> int:
	var steps: int = clock.consume(delta_sec)
	for _i: int in steps:
		_step()
	return steps


## Exécute `count` pas sans passer par l'horloge (rattrapage hors ligne, tests).
func advance_ticks(count: int) -> void:
	for _i: int in count:
		_step()


func sim_time_sec() -> float:
	return tick * clock.step_sec


## Fraction du pas en cours, pour l'interpolation visuelle.
func alpha() -> float:
	return clock.alpha()


## Empreinte de l'état logique.
func state_checksum() -> int:
	return (tick * 2654435761) ^ trains.state_checksum() ^ industry.checksum() ^ economy.checksum() ^ progression.checksum()


## Unités d'un produit présentes partout (bâtiments, entrepôts, trains).
func matter_in_system(good: String) -> int:
	var sum: int = industry.stored(good)
	for id: int in trains.trains:
		sum += trains.trains[id].cargo.total(good)
	return sum


## Écart du bilan matière d'un produit : produit - consommé - perdu - présent. Toujours 0.
func matter_balance(good: String) -> int:
	return industry.produced.get(good, 0) - industry.consumed.get(good, 0) - industry.lost.get(good, 0) - matter_in_system(good)


func _step() -> void:
	tick += 1
	industry.step()
	trains.step(tick)


# --- Sauvegarde ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"tick": tick, "clock_accum": clock.accumulator_usec(), "economy": economy.to_dict(),
			"progression": progression.to_dict(), "industry": industry.to_dict(), "trains": trains.to_dict()}


## Restaure l'état ; le réseau doit l'avoir été avant (voir SaveGame).
func load_dict(data: Dictionary) -> void:
	tick = data["tick"]
	clock.set_accumulator_usec(data["clock_accum"])
	economy.load_dict(data["economy"])
	progression.load_dict(data["progression"])
	industry.load_dict(data["industry"])
	trains.load_dict(data["trains"])
	trains.apply_level()
