extends RefCounted
## Répartiteur : garantit qu'une case n'est jamais tenue par plus de trains que sa
## capacité (1 sur voie ; nombre de quais dans une gare). Un train « tient » une case
## quand il l'a réservée ou l'occupe ; la réservation d'un trajet est atomique (tout ou
## rien) et inclut la gare de destination, donc son quai.
##
## L'interface (réserver / libérer / qui tient quoi) est volontairement générale : un
## cantonnement par blocs pourra la remplacer plus tard sans toucher aux trains.

## Appelable (case) -> int : capacité de la case. Défini par TrainSimulator.
var capacity_of: Callable = Callable()
var _holders: Dictionary = {}  # Vector2i -> Array[int] (ids de trains, uniques)


func capacity(cell: Vector2i) -> int:
	return capacity_of.call(cell) if capacity_of.is_valid() else 1


## Ids distincts des trains qui tiennent la case.
func holders(cell: Vector2i) -> Array[int]:
	var result: Array[int] = []
	for id: int in _holders.get(cell, []):
		result.append(id)
	return result


func holds(train_id: int, cell: Vector2i) -> bool:
	return train_id in _holders.get(cell, [])


## Réserve toutes les cases de `cells` pour le train, ou aucune. Renvoie
## {"ok": bool, "cell": première case refusée, "blockers": trains qui la tiennent}.
func try_reserve(train_id: int, cells: Array[Vector2i]) -> Dictionary:
	for cell: Vector2i in cells:
		var others: Array[int] = []
		for id: int in _holders.get(cell, []):
			if id != train_id:
				others.append(id)
		if others.size() >= capacity(cell):
			return {"ok": false, "cell": cell, "blockers": others}
	for cell: Vector2i in cells:
		if not holds(train_id, cell):
			if not _holders.has(cell):
				_holders[cell] = []
			_holders[cell].append(train_id)
	return {"ok": true, "cell": Vector2i(-1, -1), "blockers": [] as Array[int]}


func release(train_id: int, cell: Vector2i) -> void:
	if not _holders.has(cell):
		return
	_holders[cell].erase(train_id)
	if _holders[cell].is_empty():
		_holders.erase(cell)


func held_cells(train_id: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for cell: Vector2i in _holders:
		if train_id in _holders[cell]:
			result.append(cell)
	return result


## Libère toutes les cases du train sauf celles de `keep`.
func release_except(train_id: int, keep: Array[Vector2i]) -> void:
	for cell: Vector2i in held_cells(train_id):
		if not (cell in keep):
			release(train_id, cell)


func release_all(train_id: int) -> void:
	release_except(train_id, [] as Array[Vector2i])


func clear() -> void:
	_holders.clear()


func checksum() -> int:
	var h: int = 0
	for cell: Vector2i in _holders:
		for id: int in _holders[cell]:
			var entry: int = 1469598103934665603
			for v: int in [cell.x, cell.y, id]:
				entry = (entry ^ v) * 1099511628211
			h ^= entry  # indépendant de l'ordre d'insertion
	return h


func to_dict() -> Dictionary:
	var list: Array = []
	for cell: Vector2i in _holders:
		list.append([cell.x, cell.y, _holders[cell].duplicate()])
	return {"holders": list}


func load_dict(data: Dictionary) -> void:
	_holders.clear()
	for entry: Array in data["holders"]:
		var ids: Array[int] = []
		for id: int in entry[2]:
			ids.append(id)
		_holders[Vector2i(entry[0], entry[1])] = ids
