extends RefCounted
## Les 8 directions de la grille logique (pas de 45° en espace grille).
## Indices 0..7 ; d+1 tourne de 45°, d+4 est la direction opposée.
## Indices impairs = diagonales.

const VECTORS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]
## Noms écran (orientation de la vue isométrique) des 4 axes de gare.
const AXIS_NAMES: Array[String] = ["SE-NO", "S-N", "SO-NE", "O-E"]


static func opposite(d: int) -> int:
	return (d + 4) & 7


## Direction d'un déplacement d'une case, ou -1 si les cases ne sont pas voisines.
static func from_delta(delta: Vector2i) -> int:
	return VECTORS.find(delta)


static func is_diagonal(d: int) -> bool:
	return (d & 1) == 1


## Vrai si la direction `d` est sur l'axe de gare `axis` (0..3).
static func on_axis(d: int, axis: int) -> bool:
	return (d & 3) == axis


## Un train qui roule dans la direction `d_in` peut enchaîner `d_out` si le virage
## ne dépasse pas 45°.
static func turn_ok(d_in: int, d_out: int) -> bool:
	var turn: int = (d_out - d_in) & 7
	return turn == 0 or turn == 1 or turn == 7


## Deux voies partant d'une même case (directions sortantes) forment-elles un passage
## praticable (angle ouvert d'au moins 135°) ?
static func edges_compatible(d1: int, d2: int) -> bool:
	var diff: int = (d2 - d1) & 7
	return diff == 3 or diff == 4 or diff == 5


## Chemin case par case de `a` à `b` (inclus) : diagonales d'abord, puis ligne droite.
static func step_path(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [a]
	var cur: Vector2i = a
	while cur != b:
		cur += Vector2i(signi(b.x - cur.x), signi(b.y - cur.y))
		path.append(cur)
	return path


## Longueur logique d'un segment en milli-cases (diagonale = 1414). Valeurs d'essai.
static func segment_length_milli(d: int) -> int:
	return 1414 if is_diagonal(d) else 1000


static func pair(a: Vector2i, b: Vector2i) -> Vector4i:
	return Vector4i(a.x, a.y, b.x, b.y)
