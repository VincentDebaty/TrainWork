extends RefCounted
## Bâtiments, entrepôts de gare et production.
##
## Trois stocks distincts (exigence de conception) :
##  - stocks des bâtiments : `Building.inputs` / `Building.outputs` ;
##  - stocks des gares : `warehouses` (lots avec gare d'origine) ;
##  - cargaison transportée : `Train.cargo` (voir TrainSimulator).
## Registre matière : pour chaque produit, produit - consommé = somme des stocks
## (bâtiments + entrepôts + trains), à tout instant.

const Building = preload("res://src/sim/building.gd")
const GoodsStock = preload("res://src/sim/goods_stock.gd")

var content: RefCounted
var network: RefCounted
## Niveau du dépôt (voir Progression) ; fourni par GameSimulation. Sans lui : niveau 1.
var progression: RefCounted = null
var buildings: Dictionary = {}  # id -> Building
var warehouses: Dictionary = {}  # id de gare -> GoodsStock
var produced: Dictionary = {}  # produit -> unités produites
var consumed: Dictionary = {}  # produit -> unités consommées (sorties du système)
var delivered: Dictionary = {}  # produit -> unités reçues par des consommateurs
var lost: Dictionary = {}  # produit -> unités détruites (gare supprimée, trains retirés)
var _next_building_id: int = 1


func _init(p_content: RefCounted, p_network: RefCounted) -> void:
	content = p_content
	network = p_network
	if network != null:
		network.changed.connect(refresh_associations)
		network.cell_blocker = func(cell: Vector2i) -> int:
			var building: Building = building_at(cell)
			if building == null:
				return 0
			return 1 if is_active(building) else 2


# --- Construction du monde ----------------------------------------------------

func add_building(type_id: String, cell: Vector2i) -> Building:
	if not content.buildings.has(type_id):
		return null
	var building: Building = Building.new(_next_building_id, type_id, cell, content.building_size(type_id))
	_next_building_id += 1
	for good: String in content.buildings[type_id]["inputs"]:
		building.inputs[good] = 0
	for good: String in content.buildings[type_id]["outputs"]:
		building.outputs[good] = 0
	if content.building_role(type_id) == "depot":
		for level_key: String in content.progression:
			for good: String in content.progression[level_key].get("materials", {}):
				building.inputs[good] = 0
	buildings[building.id] = building
	refresh_associations()
	return building


func load_scenario(scenario: Dictionary) -> void:
	for entry: Dictionary in scenario.get("buildings", []):
		add_building(entry["type"], Vector2i(entry["cell"][0], entry["cell"][1]))


func building_at(cell: Vector2i) -> Building:
	for id: int in buildings:
		if buildings[id].contains(cell):
			return buildings[id]
	return null


## Rattache chaque bâtiment à la gare la plus proche dans le rayon de desserte
## (égalité : plus petit id). Les stocks ne sont jamais déplacés.
func refresh_associations() -> void:
	var radius: int = content.logistic("station_radius", 2)
	for id: int in buildings:
		var building: Building = buildings[id]
		var best_station: int = 0
		var best_distance: int = radius + 1
		var best_sq: int = 0
		if network != null and is_active(building):
			# La plus proche (Chebyshev), puis la plus proche en ligne droite, puis le plus petit id.
			for station: RefCounted in network.stations():
				var distance: int = building.distance_to(station.cell)
				var sq: int = building.distance_sq_to(station.cell)
				if distance < best_distance or (distance == best_distance and best_station != 0 and sq < best_sq):
					best_distance = distance
					best_sq = sq
					best_station = station.id
		building.station_id = best_station
	# Les entrepôts de gares supprimées disparaissent avec elles.
	for station_id: int in warehouses.keys():
		if network != null and network.station_by_id(station_id) == null:
			for good: String in warehouses[station_id].goods():
				record_loss(good, warehouses[station_id].total(good))
			warehouses.erase(station_id)


func record_loss(good: String, quantity: int) -> void:
	if quantity > 0:
		lost[good] = lost.get(good, 0) + quantity


func warehouse(station_id: int) -> GoodsStock:
	if not warehouses.has(station_id):
		warehouses[station_id] = GoodsStock.new(content.logistic("station_warehouse_cap", 40))
	return warehouses[station_id]


# --- Demande -------------------------------------------------------------------

func level() -> int:
	return progression.level if progression != null else 1


## Un bâtiment est actif (visible, produit, rattaché) une fois son niveau atteint.
func is_active(building: Building) -> bool:
	return content.building_unlock_level(building.type_id) <= level()


## Intrants que le bâtiment consomme actuellement, avec leur quantité par cycle. Une
## ville ne demande que les produits débloqués ; le dépôt demande les matériaux du
## prochain niveau (quantité totale requise).
func active_inputs(building: Building) -> Dictionary:
	var type: Dictionary = content.buildings[building.type_id]
	var role: String = content.building_role(building.type_id)
	if role == "depot":
		return content.progression_for(level()).get("materials", {})
	if role == "city":
		var wanted: Dictionary = {}
		for good: String in type["inputs"]:
			if content.is_good_unlocked(good, level()):
				wanted[good] = type["inputs"][good]
		return wanted
	return type["inputs"]


## Capacité d'entrée pour un produit : pour le dépôt, la quantité requise.
## Intrants qui manquent pour démarrer un cycle (vide si rien ne manque).
func missing_inputs(building: Building) -> Array[String]:
	var missing: Array[String] = []
	var needs: Dictionary = active_inputs(building)
	for good: String in needs:
		if building.inputs.get(good, 0) < needs[good]:
			missing.append(good)
	return missing


func input_cap(building: Building, good: String) -> int:
	if content.building_role(building.type_id) == "depot":
		return active_inputs(building).get(good, 0)
	return content.buildings[building.type_id]["input_cap"]


func accepts(building: Building, good: String) -> bool:
	return is_active(building) and active_inputs(building).has(good)


## Priorité de livraison : matériaux de construction (dépôt), puis industries, puis villes.
func priority(building: Building) -> int:
	match content.building_role(building.type_id):
		"depot":
			return 0
		"industry":
			return 1
	return 2


## Bâtiments rattachés à la gare qui acceptent `good`, par priorité puis par id.
func consumers_at(station_id: int, good: String) -> Array[Building]:
	var result: Array[Building] = []
	for id: int in buildings:
		var building: Building = buildings[id]
		if building.station_id == station_id and accepts(building, good):
			result.append(building)
	result.sort_custom(func(a: Building, b: Building) -> bool:
		return priority(a) < priority(b) or (priority(a) == priority(b) and a.id < b.id))
	return result


func input_room(building: Building, good: String) -> int:
	return maxi(input_cap(building, good) - building.inputs.get(good, 0), 0)


## Quantité que les consommateurs rattachés à la gare peuvent encore recevoir.
func demand_at(station_id: int, good: String) -> int:
	var sum: int = 0
	for building: Building in consumers_at(station_id, good):
		sum += input_room(building, good)
	return sum


# --- Pas de simulation ---------------------------------------------------------

func step() -> void:
	for id: int in buildings:
		var building: Building = buildings[id]
		if not is_active(building) or content.building_role(building.type_id) == "depot":
			continue
		_produce(building)
		_push_outputs(building)


func _produce(building: Building) -> void:
	var type: Dictionary = content.buildings[building.type_id]
	if content.building_role(building.type_id) == "city":
		_consume_city(building, type)
		return
	if building.cycle_running:
		building.progress += 1
		if building.progress >= type["cycle_ticks"]:
			for good: String in type["outputs"]:
				building.outputs[good] += type["outputs"][good]
				produced[good] = produced.get(good, 0) + type["outputs"][good]
				building.produced_total[good] = building.produced_total.get(good, 0) + type["outputs"][good]
			building.cycle_running = false
			building.progress = 0
	if building.cycle_running:
		building.state = Building.State.PRODUCING
		return
	# Démarrage d'un cycle : tous les intrants présents ET place pour chaque sortie.
	var needs: Dictionary = active_inputs(building)
	for good: String in needs:
		if building.inputs[good] < needs[good]:
			building.state = Building.State.WAITING_INPUT
			return
	for good: String in type["outputs"]:
		if building.outputs[good] + type["outputs"][good] > type["output_cap"]:
			building.state = Building.State.OUTPUT_FULL
			return
	for good: String in needs:
		building.inputs[good] -= needs[good]
		consumed[good] = consumed.get(good, 0) + needs[good]
	building.cycle_running = true
	building.progress = 0
	building.state = Building.State.PRODUCING


## Ville (avis ChatGPT 005, option A, conforme au GDD) : chaque produit débloqué est consommé
## indépendamment, à son rythme ; un produit manquant ne bloque jamais les autres, donc les
## livraisons des autres produits continuent d'être acceptées et payées.
func _consume_city(building: Building, type: Dictionary) -> void:
	building.cycle_running = false
	building.progress += 1
	if building.progress < type["cycle_ticks"]:
		return
	building.progress = 0
	var any: bool = false
	var needs: Dictionary = active_inputs(building)
	for good: String in needs:
		if building.inputs.get(good, 0) >= needs[good]:
			building.inputs[good] -= needs[good]
			consumed[good] = consumed.get(good, 0) + needs[good]
			any = true
	building.state = Building.State.PRODUCING if any else Building.State.WAITING_INPUT


## Transfert automatique bâtiment -> entrepôt de sa gare (chariots décoratifs).
func _push_outputs(building: Building) -> void:
	if building.outputs.is_empty():
		return
	if building.station_id == 0:
		return
	var rate: int = content.logistic("building_transfer_per_tick", 1)
	var stock: GoodsStock = warehouse(building.station_id)
	for good: String in building.outputs:
		var amount: int = mini(mini(rate, building.outputs[good]), stock.free_room(good))
		if amount > 0:
			building.outputs[good] -= stock.add(good, building.station_id, amount)


# --- Registre matière et empreinte --------------------------------------------

## Unités d'un produit présentes dans les bâtiments et les entrepôts (hors trains).
func stored(good: String) -> int:
	var sum: int = 0
	for id: int in buildings:
		sum += buildings[id].inputs.get(good, 0) + buildings[id].outputs.get(good, 0)
	for station_id: int in warehouses:
		sum += warehouses[station_id].total(good)
	return sum


func to_dict() -> Dictionary:
	var building_list: Array = []
	for id: int in buildings:
		building_list.append(buildings[id].to_dict())
	var warehouse_list: Array = []
	for station_id: int in warehouses:
		warehouse_list.append([station_id, warehouses[station_id].to_dict()])
	return {"buildings": building_list, "warehouses": warehouse_list, "produced": produced.duplicate(),
			"consumed": consumed.duplicate(), "delivered": delivered.duplicate(), "lost": lost.duplicate(), "next_building_id": _next_building_id}


## Restaure les bâtiments et stocks. Le réseau doit déjà être restauré (rattachement aux gares).
func load_dict(data: Dictionary) -> void:
	buildings.clear()
	warehouses.clear()
	for entry: Dictionary in data["buildings"]:
		var type_id: String = entry["type"]
		var building: Building = Building.new(entry["id"], type_id, Vector2i(entry["cell"][0], entry["cell"][1]), content.building_size(type_id))
		building.inputs = entry["inputs"].duplicate()
		building.outputs = entry["outputs"].duplicate()
		building.cycle_running = entry["cycle_running"]
		building.progress = entry["progress"]
		building.state = entry["state"]
		building.produced_total = entry.get("produced_total", {}).duplicate()
		buildings[building.id] = building
	for entry: Array in data["warehouses"]:
		var stock: GoodsStock = GoodsStock.new(0)
		stock.load_dict(entry[1])
		warehouses[entry[0]] = stock
	produced = data["produced"].duplicate()
	consumed = data["consumed"].duplicate()
	delivered = data["delivered"].duplicate()
	lost = data["lost"].duplicate()
	_next_building_id = data["next_building_id"]
	refresh_associations()


func checksum() -> int:
	var h: int = 1469598103934665603
	for id: int in buildings:
		var b: Building = buildings[id]
		var values: Array = [b.id, b.station_id, b.progress, int(b.cycle_running), b.state]
		for good: String in b.inputs:
			values.append(b.inputs[good])
		for good: String in b.outputs:
			values.append(b.outputs[good])
		for v: int in values:
			h = (h ^ v) * 1099511628211
	var warehouse_sum: int = 0
	for station_id: int in warehouses:
		warehouse_sum ^= (station_id ^ warehouses[station_id].checksum()) * 1099511628211  # indépendant de l'ordre
	return (h ^ warehouse_sum) * 1099511628211
