extends RefCounted
## Paramètres de simulation dérivés de la configuration (valeurs d'essai).
## Toutes les durées sont converties en nombre de pas pour rester en entiers.

var step_sec: float
var speed_milli_per_tick: int
var dwell_ticks: int
var retry_ticks: int
var max_trains: int


func _init(p_step_sec: float = 0.2, speed_cells_per_sec: float = 2.0, dwell_sec: float = 3.0,
		retry_sec: float = 1.0, p_max_trains: int = 1) -> void:
	step_sec = p_step_sec
	speed_milli_per_tick = roundi(speed_cells_per_sec * 1000.0 * p_step_sec)
	dwell_ticks = maxi(1, roundi(dwell_sec / p_step_sec))
	retry_ticks = maxi(1, roundi(retry_sec / p_step_sec))
	max_trains = p_max_trains
