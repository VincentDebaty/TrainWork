extends RefCounted
## Stock de marchandises à capacités par produit, en lots (produit, gare d'origine,
## quantité). L'origine sert au calcul de la distance payée à la livraison et
## distingue, pour les futures correspondances, marchandises sortantes et en transit.
## Jamais négatif, jamais au-delà de la capacité.

var default_capacity: int = 0
var _lots: Dictionary = {}  # produit -> {origine (int) -> quantité (int)}
var _capacities: Dictionary = {}  # produit -> capacité


func _init(p_default_capacity: int = 0) -> void:
	default_capacity = p_default_capacity


func set_capacity(good: String, capacity: int) -> void:
	_capacities[good] = capacity


func capacity(good: String) -> int:
	return _capacities.get(good, default_capacity)


func total(good: String) -> int:
	var sum: int = 0
	for origin: int in _lots.get(good, {}):
		sum += _lots[good][origin]
	return sum


func free_room(good: String) -> int:
	return maxi(capacity(good) - total(good), 0)


## Ajoute jusqu'à `quantity` unités ; renvoie la quantité acceptée.
func add(good: String, origin: int, quantity: int) -> int:
	var accepted: int = clampi(quantity, 0, free_room(good))
	if accepted > 0:
		if not _lots.has(good):
			_lots[good] = {}
		_lots[good][origin] = _lots[good].get(origin, 0) + accepted
	return accepted


## Retire jusqu'à `quantity` unités, les plus anciennes d'abord. Renvoie des lots
## Vector2i(origine, quantité).
func take(good: String, quantity: int) -> Array[Vector2i]:
	var taken: Array[Vector2i] = []
	var remaining: int = quantity
	var by_origin: Dictionary = _lots.get(good, {})
	for origin: int in by_origin.keys():
		if remaining <= 0:
			break
		var amount: int = mini(by_origin[origin], remaining)
		by_origin[origin] -= amount
		remaining -= amount
		taken.append(Vector2i(origin, amount))
		if by_origin[origin] == 0:
			by_origin.erase(origin)
	return taken


func goods() -> Array[String]:
	var result: Array[String] = []
	for good: String in _lots:
		if total(good) > 0:
			result.append(good)
	return result


func checksum() -> int:
	var h: int = 1469598103934665603
	for good: String in _lots:
		for origin: int in _lots[good]:
			for v: int in [good.hash(), origin, _lots[good][origin]]:
				h = (h ^ v) * 1099511628211
	return h  # l'ordre des lots compte (FIFO) : il est conservé par la sauvegarde


# --- Sauvegarde ---------------------------------------------------------------

func to_dict() -> Dictionary:
	var lots: Array = []
	for good: String in _lots:
		var by_origin: Array = []
		for origin: int in _lots[good]:
			by_origin.append([origin, _lots[good][origin]])
		lots.append([good, by_origin])
	return {"default": default_capacity, "caps": _capacities.duplicate(), "lots": lots}


func load_dict(data: Dictionary) -> void:
	default_capacity = data["default"]
	_capacities = data["caps"].duplicate()
	_lots.clear()
	for entry: Array in data["lots"]:
		_lots[entry[0]] = {}
		for lot: Array in entry[1]:
			_lots[entry[0]][lot[0]] = lot[1]
