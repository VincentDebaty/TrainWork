extends RefCounted
## Types de terrain de la carte de test (données de simulation, sans rendu).

enum Type { PLAINS, FOREST, HILL, WATER, ROCK }

const NAMES: Dictionary = {
	Type.PLAINS: "Plaine",
	Type.FOREST: "Forêt",
	Type.HILL: "Colline",
	Type.WATER: "Rivière",
	Type.ROCK: "Roche",
}


## Constructible pour rails et gares. L'eau exige un pont (niveau 2, reporté).
static func is_buildable(terrain: int) -> bool:
	return terrain != Type.WATER


static func display_name(terrain: int) -> String:
	return NAMES.get(terrain, "?")
