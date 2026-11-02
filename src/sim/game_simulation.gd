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
## Coûts d'exploitation accumulés (milli-pièces x pas), prélevés minute par minute.
var _upkeep_accum: int = 0


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
	return (tick * 2654435761) ^ trains.state_checksum() ^ industry.checksum() ^ economy.checksum() ^ progression.checksum() ^ (_upkeep_accum * 977)


## Unités d'un produit présentes partout (bâtiments, entrepôts, trains).
func matter_in_system(good: String) -> int:
	var sum: int = industry.stored(good)
	for id: int in trains.trains:
		sum += trains.trains[id].cargo.total(good)
	return sum


## Produits en entrepôt à cette gare qu'aucune ligne ne peut emmener vers un consommateur :
## aucune ligne passant par la gare ne dessert une autre gare dont un bâtiment en accepte.
func stranded_goods(station_id: int) -> Array[String]:
	var stranded: Array[String] = []
	var stock: RefCounted = industry.warehouses.get(station_id)
	if stock == null:
		return stranded
	for good: String in stock.goods():
		var served: bool = false
		for line_id: int in trains.lines:
			var stations: Array[int] = trains.lines[line_id].station_ids
			if not (station_id in stations):
				continue
			for other: int in stations:
				if other != station_id and not industry.consumers_at(other, good).is_empty():
					served = true
		if not served:
			stranded.append(good)
	return stranded


## Écart du bilan matière d'un produit : produit - consommé - perdu - présent. Toujours 0.
func matter_balance(good: String) -> int:
	return industry.produced.get(good, 0) - industry.consumed.get(good, 0) - industry.lost.get(good, 0) - matter_in_system(good)


func _step() -> void:
	tick += 1
	industry.step()
	trains.step(tick)
	_charge_upkeep()


## Coût d'exploitation courant, en milli-pièces par minute de jeu (avis ChatGPT 005).
func upkeep_rate_milli_per_min() -> int:
	var rate: int = trains.network.graph.edge_count() * content.operating_cost("rail_milli_per_segment_per_min")
	for id: int in trains.trains:
		var waiting: bool = trains.trains[id].state >= 2  # WAITING_ROUTE, WAITING_CLEARANCE : immobilisé
		rate += content.operating_cost("train_idle_milli_per_min" if waiting else "train_active_milli_per_min")
	return rate


## Accumule le coût à chaque pas (entiers exacts) et le prélève par minute de jeu.
@warning_ignore("integer_division")
func _charge_upkeep() -> void:
	var ticks_per_min: int = roundi(60.0 / clock.step_sec)
	_upkeep_accum += upkeep_rate_milli_per_min()
	if _upkeep_accum >= ticks_per_min * 1000:
		var due: int = _upkeep_accum / ticks_per_min
		_upkeep_accum -= due * ticks_per_min
		economy.charge(due)


# --- Sauvegarde ---------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"tick": tick, "clock_accum": clock.accumulator_usec(), "upkeep_accum": _upkeep_accum, "economy": economy.to_dict(),
			"progression": progression.to_dict(), "industry": industry.to_dict(), "trains": trains.to_dict()}


## Restaure l'état ; le réseau doit l'avoir été avant (voir SaveGame).
func load_dict(data: Dictionary) -> void:
	tick = data["tick"]
	clock.set_accumulator_usec(data["clock_accum"])
	_upkeep_accum = data.get("upkeep_accum", 0)
	economy.load_dict(data["economy"])
	progression.load_dict(data["progression"])
	industry.load_dict(data["industry"])
	trains.load_dict(data["trains"])
	trains.apply_level()
