extends RefCounted
## Ligne : liste ordonnée de gares, parcourue en aller-retour (A-B-C-B-A).

var id: int
var station_ids: Array[int] = []


func _init(p_id: int, p_station_ids: Array[int]) -> void:
	id = p_id
	station_ids = p_station_ids.duplicate()


func to_dict() -> Dictionary:
	return {"id": id, "stations": station_ids.duplicate()}
