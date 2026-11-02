extends RefCounted
## Chargement et déchargement à l'arrêt d'un train, selon le besoin réel (avis de
## conception 002, option D2-A), avec une destination précise pour chaque unité :
##  - à chaque arrêt, la cargaison est RÉSERVÉE pour des gares du parcours, par priorité
##    (GDD : matériaux de construction du dépôt, puis intrants industriels, puis villes),
##    dans la limite de leur demande non encore réservée (tous trains confondus) ;
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
## Quantité déjà réservée par les AUTRES trains : `booked_elsewhere(gare, produit, id_train) -> int`.
var booked_elsewhere: Callable = Callable()


func _init(p_content: RefCounted, p_industry: RefCounted, p_economy: RefCounted, p_network: RefCounted) -> void:
	content = p_content
	industry = p_industry
	economy = p_economy
	network = p_network


## Effectue décharge puis charge. Renvoie le nombre de pas de manutention
## (proportionnel au volume déplacé, au moins 0).
## `stations` : parcours suivi par le train (sa ligne). `station_id` < 0 : aucune manutention.
func handle_stop(train: RefCounted, station_id: int, stations: Array[int]) -> int:
	if station_id < 0:
		return 0
	_book(train, stations, station_id, true)  # destinations, gare actuelle comprise
	var moved: int = _unload(train, station_id)
	moved += _load(train, station_id, stations)
	_book(train, stations, station_id, false)  # ce qui reste à bord part vers les autres gares
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
			var booked: int = train.bookings.get(station_id, {}).get(good, 0)
			var amount: int = mini(mini(industry.input_room(building, good), train.cargo.total(good)), booked)
			if amount <= 0:
				continue
			train.bookings[station_id][good] = booked - amount
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


func _load(train: RefCounted, station_id: int, stations: Array[int]) -> int:
	var moved: int = 0
	var stock: RefCounted = industry.warehouse(station_id)
	for good: String in content.good_ids():
		if train.cargo.capacity(good) <= 0:
			continue  # pas de wagon pour ce produit (non débloqué)
		var demand: int = 0
		for other: int in _distinct(stations, station_id):
			demand += _free_demand(other, good, train.id) - train.bookings.get(other, {}).get(good, 0)
		var amount: int = mini(mini(stock.total(good), train.cargo.free_room(good)), demand)
		if amount <= 0:
			continue
		for lot: Vector2i in stock.take(good, amount):
			moved += train.cargo.add(good, lot.x, lot.y)
	return moved



## Attribue toute la cargaison à bord à des gares du parcours, par priorité puis dans
## l'ordre du parcours, sans dépasser leur demande libre. Le reste n'a pas de destination
## pour l'instant : il reste à bord et sera réattribué au prochain arrêt.
func _book(train: RefCounted, stations: Array[int], here: int, include_here: bool) -> void:
	train.bookings = {}
	var destinations: Array[int] = _distinct(stations, -1 if include_here else here)
	for good: String in train.cargo.goods():
		var options: Array = []
		for order: int in destinations.size():
			var priority: int = _priority_at(destinations[order], good)
			if priority >= 0:
				options.append([priority, order, destinations[order]])
		options.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		var left: int = train.cargo.total(good)
		for option: Array in options:
			var take: int = mini(left, _free_demand(option[2], good, train.id))
			if take <= 0:
				continue
			if not train.bookings.has(option[2]):
				train.bookings[option[2]] = {}
			train.bookings[option[2]][good] = take
			left -= take


## Demande d'une gare pour un produit, moins ce que les autres trains lui ont réservé.
func _free_demand(station_id: int, good: String, train_id: int) -> int:
	var others: int = booked_elsewhere.call(station_id, good, train_id) if booked_elsewhere.is_valid() else 0
	return maxi(industry.demand_at(station_id, good) - others, 0)


## Meilleure priorité des consommateurs de la gare pour ce produit, -1 s'il n'y en a pas.
func _priority_at(station_id: int, good: String) -> int:
	var best: int = -1
	for building: RefCounted in industry.consumers_at(station_id, good):
		var priority: int = industry.priority(building)
		if best < 0 or priority < best:
			best = priority
	return best


## Gares distinctes du parcours, dans l'ordre, sans `excluded`.
func _distinct(stations: Array[int], excluded: int) -> Array[int]:
	var result: Array[int] = []
	for station_id: int in stations:
		if station_id != excluded and not (station_id in result):
			result.append(station_id)
	return result
