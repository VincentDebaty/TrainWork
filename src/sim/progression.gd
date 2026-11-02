extends RefCounted
## Niveau du dépôt et conditions de passage au niveau suivant (D-017). Pour monter, il
## faut RÉUNIR : des pièces disponibles, les matériaux présents dans le stock du dépôt
## (consommés à l'amélioration) et tous les objectifs permanents du niveau. Les
## livraisons à la ville sont cumulées depuis le début du niveau.

signal level_changed(new_level: int)

enum Result { OK, MAX_LEVEL, NO_DEPOT, NOT_READY }

const RESULT_TEXTS: Dictionary = {
	Result.OK: "Dépôt amélioré",
	Result.MAX_LEVEL: "Niveau maximal du prototype atteint",
	Result.NO_DEPOT: "Aucun dépôt actif",
	Result.NOT_READY: "Conditions non réunies",
}

var content: RefCounted
var industry: RefCounted
var economy: RefCounted
var trains: RefCounted = null
var level: int = 1
var city_delivered: Dictionary = {}  # produit -> unités livrées à la ville depuis le début du niveau
var trips_completed: int = 0  # trajets terminés par des trains (ligne opérationnelle)


func _init(p_content: RefCounted, p_industry: RefCounted, p_economy: RefCounted) -> void:
	content = p_content
	industry = p_industry
	economy = p_economy


func is_max_level() -> bool:
	return level >= content.max_level


func record_city_delivery(good: String, quantity: int) -> void:
	city_delivered[good] = city_delivered.get(good, 0) + quantity


func record_trip() -> void:
	trips_completed += 1


func depot() -> RefCounted:
	for id: int in industry.buildings:
		var building: RefCounted = industry.buildings[id]
		if content.building_role(building.type_id) == "depot" and industry.is_active(building):
			return building
	return null


## Lignes d'état pour l'interface : [{"label", "have", "need", "ok"}].
func status() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var rule: Dictionary = content.progression_for(level)
	if rule.is_empty():
		return rows
	rows.append(_row("Pièces", int(economy.wallet_milli / 1000.0), rule["coins_milli"] / 1000, economy.wallet_milli >= rule["coins_milli"]))
	var stock: RefCounted = depot()
	for good: String in rule.get("materials", {}):
		var have: int = stock.inputs.get(good, 0) if stock != null else 0
		rows.append(_row("%s au dépôt" % content.good_name(good), have, rule["materials"][good], have >= rule["materials"][good]))
	for objective: Dictionary in rule.get("objectives", []):
		rows.append(_objective_row(objective))
	return rows


func can_upgrade() -> bool:
	if is_max_level() or depot() == null:
		return false
	for row: Dictionary in status():
		if not row["ok"]:
			return false
	return true


func upgrade() -> int:
	if is_max_level():
		return Result.MAX_LEVEL
	var stock: RefCounted = depot()
	if stock == null:
		return Result.NO_DEPOT
	if not can_upgrade():
		return Result.NOT_READY
	var rule: Dictionary = content.progression_for(level)
	if not economy.spend(rule["coins_milli"]):
		return Result.NOT_READY
	for good: String in rule.get("materials", {}):
		stock.inputs[good] -= rule["materials"][good]
		industry.consumed[good] = industry.consumed.get(good, 0) + rule["materials"][good]  # sort du système
	set_level(level + 1)
	return Result.OK


## Fixe le niveau (montée, restauration d'une sauvegarde, outils de développement).
func set_level(new_level: int) -> void:
	level = clampi(new_level, 1, content.max_level)
	city_delivered = {}
	industry.refresh_associations()
	if trains != null:
		trains.apply_level()
	level_changed.emit(level)


func checksum() -> int:
	var h: int = level * 7919 + trips_completed
	for good: String in city_delivered:
		h = (h ^ good.hash() ^ city_delivered[good]) * 1099511628211
	return h


static func result_text(result: int) -> String:
	return RESULT_TEXTS.get(result, "?")


func _row(label: String, have: int, need: int, ok: bool) -> Dictionary:
	return {"label": label, "have": have, "need": need, "ok": ok}


func _objective_row(objective: Dictionary) -> Dictionary:
	match objective["kind"]:
		"city_delivered_total":
			var total: int = 0
			var each_ok: bool = true
			var each_min: int = objective.get("each_min", 0)
			for good: String in objective["goods"]:
				total += city_delivered.get(good, 0)
				each_ok = each_ok and city_delivered.get(good, 0) >= each_min
			var label: String = "Livrer %d unités à la ville" % objective["total"]
			if each_min > 0:
				label += " (dont %d de chaque produit)" % each_min
			return _row(label, total, objective["total"], total >= objective["total"] and each_ok)
		"city_delivered_good":
			var have: int = city_delivered.get(objective["good"], 0)
			return _row("Livrer %d %s à la ville" % [objective["total"], content.good_name(objective["good"]).to_lower()], have, objective["total"], have >= objective["total"])
		"operational_line":
			var running: bool = trains != null and trains.trains.size() > 0 and trips_completed > 0
			return _row("Une ligne opérationnelle", 1 if running else 0, 1, running)
	return _row("?", 0, 1, false)


func to_dict() -> Dictionary:
	return {"level": level, "city_delivered": city_delivered.duplicate(), "trips": trips_completed}


func load_dict(data: Dictionary) -> void:
	level = clampi(data["level"], 1, content.max_level)
	city_delivered = data["city_delivered"].duplicate()
	trips_completed = data["trips"]
