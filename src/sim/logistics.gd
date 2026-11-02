extends RefCounted
## Chargement et déchargement à l'arrêt d'un train, selon le besoin réel (avis de
## conception 002, option D2-A) :
##  - décharge seulement ce que les consommateurs de la gare peuvent recevoir ;
##    le reste reste à bord ;
##  - charge seulement ce que les consommateurs des AUTRES gares de la ligne demandent
##    (pas seulement les suivantes : prévu pour les futures correspondances) ;
##  - revenu crédité au moment où le consommateur reçoit, base + distance ferroviaire
##    la plus courte entre la gare d'origine du lot et la gare de livraison.

signal delivered(good: String, quantity: int, station_id: int, revenue_milli: int)

var content: RefCounted
var industry: RefCounted
var economy: RefCounted
var network: RefCounted
## Niveau et objectifs (null : pas de progression).
var progression: RefCounted = null


func _init(p_content: RefCounted, p_industry: RefCounted, p_economy: RefCounted, p_network: RefCounted) -> void:
	content = p_content
	industry = p_industry
	economy = p_economy
	network = p_network


## Effectue décharge puis charge. Renvoie le nombre de pas de manutention
## (proportionnel au volume déplacé, au moins 0).
func handle_stop(train: RefCounted, station_id: int, line: RefCounted) -> int:
	var moved: int = _unload(train, station_id)
	moved += _load(train, station_id, line)
	var rate: int = maxi(content.logistic("load_units_per_tick", 2), 1)
	return ceili(float(moved) / float(rate))


func price_milli(good: String, origin_station: int, destination_station: int) -> int:
	var data: Dictionary = content.goods[good]
	var distance: int = 0
	if origin_station != destination_station:
		distance = maxi(network.find_station_path(origin_station, destination_station).size() - 1, 0)
	return data["base_price_milli"] + distance * data["dist_price_milli"]


func _unload(train: RefCounted, station_id: int) -> int:
	var moved: int = 0
	for good: String in train.cargo.goods():
		for building: RefCounted in industry.consumers_at(station_id, good):
			var amount: int = mini(industry.input_room(building, good), train.cargo.total(good))
			if amount <= 0:
				continue
			var role: String = content.building_role(building.type_id)
			for lot: Vector2i in train.cargo.take(good, amount):
				building.inputs[good] = building.inputs.get(good, 0) + lot.y
				industry.delivered[good] = industry.delivered.get(good, 0) + lot.y
				# Matériaux de construction livrés au dépôt : pas de revenu (D-017).
				var revenue: int = 0 if role == "depot" else lot.y * price_milli(good, lot.x, station_id)
				economy.credit(revenue)
				if role == "city" and progression != null:
					progression.record_city_delivery(good, lot.y)
				delivered.emit(good, lot.y, station_id, revenue)
				moved += lot.y
	return moved


func _load(train: RefCounted, station_id: int, line: RefCounted) -> int:
	var moved: int = 0
	var stock: RefCounted = industry.warehouse(station_id)
	for good: String in content.good_ids():
		if train.cargo.capacity(good) <= 0:
			continue  # pas de wagon pour ce produit (non débloqué)
		var demand: int = 0
		var seen: Dictionary = {}
		for other: int in line.station_ids:
			if other != station_id and not seen.has(other):
				seen[other] = true
				demand += industry.demand_at(other, good)
		demand -= train.cargo.total(good)  # déjà à bord pour ces consommateurs
		var amount: int = mini(mini(stock.total(good), train.cargo.free_room(good)), demand)
		if amount <= 0:
			continue
		for lot: Vector2i in stock.take(good, amount):
			moved += train.cargo.add(good, lot.x, lot.y)
	return moved
