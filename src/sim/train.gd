extends RefCounted
## État d'un train (données de simulation). Positions de voie en entiers
## (milli-cases) pour un résultat reproductible ; `pos` / `prev_pos` sont des
## coordonnées de grille flottantes réservées à l'affichage.

enum State { DWELLING, RUNNING, WAITING_ROUTE, WAITING_CLEARANCE }

const STATE_NAMES: Dictionary = {
	State.DWELLING: "à l'arrêt en gare",
	State.RUNNING: "en marche",
	State.WAITING_ROUTE: "attend une voie",
	State.WAITING_CLEARANCE: "attend que la voie soit libre",
}

var id: int
var line_id: int
var state: int = State.DWELLING
## Index (dans la ligne) de la dernière gare atteinte, puis de la gare visée.
var stop_index: int = 0
var target_index: int = 0
var direction: int = 1  # +1 : vers la fin de la ligne, -1 : vers le début
## Liste de gares suivie (copie de la ligne, mise à jour au prochain arrêt après un changement).
var route: Array[int] = []
## Le parcours a changé et ne contient plus la gare où se trouve le train : il rejoint la première.
var relocate: bool = false
var dwell_left: int = 0
var retry_left: int = 0
var at_station: bool = true

## Dernière case franchie ; origine du prochain trajet.
var cell: Vector2i = Vector2i.ZERO
## Direction de roulement (0..7), pour interdire le demi-tour hors gare.
var heading: int = 0
var path: Array[Vector2i] = []
var seg: int = 0
var progress_milli: int = 0
## Distance (milli-cases) de chaque case du trajet depuis son début, et index de la
## prochaine case à libérer derrière le train.
var cell_dist: Array[int] = []
var release_index: int = 0
## En attente d'autorisation : case refusée et trains qui la tiennent.
var wait_cell: Vector2i = Vector2i(-1, -1)
var blockers: Array[int] = []

## Cargaison transportée (lots avec gare d'origine) ; capacités fixées par les wagons.
var cargo: RefCounted = null
## Destination précise de la cargaison : id de gare -> {produit -> quantité réservée}.
var bookings: Dictionary = {}

var pos: Vector2 = Vector2.ZERO
var prev_pos: Vector2 = Vector2.ZERO


func _init(p_id: int, p_line_id: int, p_cell: Vector2i) -> void:
	id = p_id
	line_id = p_line_id
	cell = p_cell
	pos = Vector2(p_cell) + Vector2(0.5, 0.5)
	prev_pos = pos


func to_dict() -> Dictionary:
	var path_list: Array = []
	for c: Vector2i in path:
		path_list.append([c.x, c.y])
	return {"id": id, "line_id": line_id, "state": state, "stop_index": stop_index, "target_index": target_index,
			"direction": direction, "dwell_left": dwell_left, "retry_left": retry_left, "at_station": at_station,
			"cell": [cell.x, cell.y], "heading": heading, "path": path_list, "seg": seg, "progress": progress_milli,
			"cell_dist": cell_dist.duplicate(), "release_index": release_index,
			"wait_cell": [wait_cell.x, wait_cell.y], "blockers": blockers.duplicate(), "cargo": cargo.to_dict(),
			"route": route.duplicate(), "relocate": relocate, "bookings": bookings_list()}


## Réservations sous forme de liste (les clés entières ne survivent pas au JSON).
func bookings_list() -> Array:
	var list: Array = []
	for station_id: int in bookings:
		for good: String in bookings[station_id]:
			list.append([station_id, good, bookings[station_id][good]])
	return list
