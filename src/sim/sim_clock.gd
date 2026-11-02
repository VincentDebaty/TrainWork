extends RefCounted
## Horloge à pas fixe. Convertit le temps réel écoulé (variable) en un nombre
## entier de pas de simulation. Accumulation en microsecondes entières pour éviter
## la dérive flottante.

var step_sec: float
var step_usec: int
var max_steps_per_advance: int
var _accum_usec: int = 0


func _init(p_step_sec: float, p_max_steps_per_advance: int) -> void:
	step_sec = p_step_sec
	step_usec = roundi(p_step_sec * 1000000.0)
	max_steps_per_advance = p_max_steps_per_advance


## Ajoute `delta_sec` de temps réel et renvoie le nombre de pas à exécuter.
## Garde-fou « spirale de la mort » : au-delà de `max_steps_per_advance`, le retard
## restant est abandonné. Le rattrapage hors ligne (M5) n'utilisera pas cette voie.
@warning_ignore("integer_division")
func consume(delta_sec: float) -> int:
	_accum_usec += roundi(maxf(delta_sec, 0.0) * 1000000.0)
	var steps: int = _accum_usec / step_usec
	if steps > max_steps_per_advance:
		steps = max_steps_per_advance
		_accum_usec = _accum_usec % step_usec
	else:
		_accum_usec -= steps * step_usec
	return steps


## Fraction (0..1) du pas en cours, pour interpoler l'affichage entre deux pas.
func alpha() -> float:
	return float(_accum_usec) / float(step_usec)


func accumulator_usec() -> int:
	return _accum_usec


func set_accumulator_usec(value: int) -> void:
	_accum_usec = value
