extends RefCounted
## Contenu de jeu éditable (produits, bâtiments, wagons, constantes de logistique),
## chargé depuis data/content.json. Les nombres JSON sont convertis en entiers.

const DEFAULT_PATH: String = "res://data/content.json"

var goods: Dictionary = {}
var buildings: Dictionary = {}
var wagons: Dictionary = {}
var logistics: Dictionary = {}
var construction: Dictionary = {}
var operations: Dictionary = {}
var levels: Dictionary = {}
var progression: Dictionary = {}
var max_level: int = 1
var error: String = ""


func load_from(path: String = DEFAULT_PATH) -> bool:
	var parsed: Variant = parse_file(path)
	if not (parsed is Dictionary):
		error = "Fichier illisible : %s" % path
		return false
	goods = parsed.get("goods", {})
	buildings = parsed.get("buildings", {})
	wagons = parsed.get("wagons", {})
	logistics = parsed.get("logistics", {})
	construction = parsed.get("construction", {})
	operations = parsed.get("operations", {})
	levels = parsed.get("levels", {})
	progression = parsed.get("progression", {})
	max_level = parsed.get("max_level", 1)
	return _validate()


## Lit un fichier JSON et convertit les flottants entiers en int.
static func parse_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var json: JSON = JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		return null
	return _intify(json.data)


func good_ids() -> Array[String]:
	var ids: Array[String] = []
	for id: String in goods:
		ids.append(id)
	return ids


func good_name(good: String) -> String:
	return goods.get(good, {}).get("name", good)


func building_size(type_id: String) -> Vector2i:
	var size: Array = buildings[type_id]["size"]
	return Vector2i(size[0], size[1])


func logistic(key: String, default_value: int = 0) -> int:
	return logistics.get(key, default_value)


func operating_cost(key: String) -> int:
	return operations.get(key, 0)


func build_cost(key: String, default_value: int = 0) -> int:
	return construction.get(key, default_value)


## Produits disponibles au niveau `level`, dans l'ordre du fichier.
func unlocked_goods(level: int) -> Array[String]:
	var result: Array[String] = []
	for id: String in goods:
		if goods[id].get("unlock_level", 1) <= level:
			result.append(id)
	return result


func is_good_unlocked(good: String, level: int) -> bool:
	return goods.has(good) and goods[good].get("unlock_level", 1) <= level


func building_unlock_level(type_id: String) -> int:
	return buildings[type_id].get("unlock_level", 1)


func building_role(type_id: String) -> String:
	return buildings[type_id].get("role", "industry")


## Wagon transportant ce produit, ou "" s'il n'y en a pas.
func wagon_for(good: String) -> String:
	for id: String in wagons:
		if wagons[id]["good"] == good:
			return id
	return ""


func max_trains_for_level(level: int, fallback: int) -> int:
	return levels.get(str(level), {}).get("max_trains", fallback)


## Conditions pour passer du niveau `level` au suivant ({} au niveau maximal).
func progression_for(level: int) -> Dictionary:
	return progression.get(str(level), {})


func _validate() -> bool:
	for type_id: String in buildings:
		var b: Dictionary = buildings[type_id]
		for key: String in ["size", "inputs", "outputs", "cycle_ticks", "input_cap", "output_cap"]:
			if not b.has(key):
				error = "Bâtiment %s : clé « %s » manquante" % [type_id, key]
				return false
		for good: String in b["inputs"].keys() + b["outputs"].keys():
			if not goods.has(good):
				error = "Bâtiment %s : produit inconnu « %s »" % [type_id, good]
				return false
	for wagon_id: String in wagons:
		if not goods.has(wagons[wagon_id].get("good", "")):
			error = "Wagon %s : produit inconnu" % wagon_id
			return false
	for level_key: String in progression:
		for good: String in progression[level_key].get("materials", {}):
			if not goods.has(good):
				error = "Progression niveau %s : produit inconnu « %s »" % [level_key, good]
				return false
	return true


static func _intify(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: Variant in value:
			result[key] = _intify(value[key])
		return result
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_intify(item))
		return items
	if value is float and value == floorf(value):
		return int(value)
	return value
