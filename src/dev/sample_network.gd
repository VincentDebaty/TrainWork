extends RefCounted
## Réseau d'exemple sur la carte 80x80 du scénario (développement et tests). Emplacements de
## gares et raccordements trouvés par recherche automatique ; chaque ligne ci-dessous est
## praticable dans les deux sens (virages de 45°, rebroussement en gare). Le jeu ne pose
## jamais ce réseau à la place du joueur : seuls la démo et les tests l'utilisent.

const RailPlanner = preload("res://src/rail/rail_planner.gd")
const Dir = preload("res://src/rail/direction.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")

## Gare -> [case, axe]. Bâtiments desservis en commentaire.
const STATIONS: Dictionary = {
	"mine": [Vector2i(26, 43), 0],  # mine de charbon (22,39), nord-ouest
	"depot": [Vector2i(40, 43), 0],  # dépôt (39,39), centre
	"city": [Vector2i(64, 43), 0],  # ville (66,39), sud-est
	"saw": [Vector2i(40, 54), 0],  # scierie (39,56), sud-ouest
	"quarry": [Vector2i(40, 14), 0],  # carrière (39,10), nord-est, de l'autre côté du pont (niveau 2)
	"steel": [Vector2i(62, 22), 0],  # aciérie (61,18), est (niveau 3)
	"iron": [Vector2i(63, 60), 0],  # mine de fer (62,62), sud (niveau 3)
}
## Raccordements des embranchements (aiguillages sur la voie principale y=43).
const JUNCTIONS: Dictionary = {
	"saw": Vector2i(44, 43),
	"quarry": Vector2i(39, 43),
	"iron": Vector2i(60, 43),
}


func cell_of(key: String) -> Vector2i:
	return STATIONS[key][0]


func id_of(world: RefCounted, key: String) -> int:
	var station: RefCounted = world.network.station_at(cell_of(key))
	return station.id if station != null else 0


## Pose la gare (payée). Renvoie son id, 0 si refusée.
func station(world: RefCounted, key: String) -> int:
	if world.sim.construction.place_station(STATIONS[key][0], STATIONS[key][1]) != RailNetwork.Result.OK:
		return 0
	return id_of(world, key)


## Tracé calculé de `a` à `b` (portée de toute la carte), payé. Renvoie le nombre de rails posés.
func link(world: RefCounted, a: Vector2i, b: Vector2i) -> int:
	var cells: Array[Vector2i] = RailPlanner.new().find_route(world.network, a, b, 64)
	var edges: Array[Vector4i] = []
	for i: int in range(1, cells.size()):
		edges.append(Dir.pair(cells[i - 1], cells[i]))
	if edges.is_empty():
		return 0
	return world.sim.construction.place_edges(edges)["placed"]


## Niveau 1 : voie principale mine -> dépôt -> ville, embranchement de la scierie.
func build_level1(world: RefCounted) -> bool:
	for key: String in ["mine", "depot", "city", "saw"]:
		if station(world, key) == 0:
			return false
	return link(world, cell_of("mine"), cell_of("depot")) > 0 and link(world, cell_of("depot"), cell_of("city")) > 0 \
			and link(world, cell_of("saw"), JUNCTIONS["saw"]) > 0


## Niveau 2 : la carrière, au-delà de la rivière (le pont doit être débloqué).
func build_quarry(world: RefCounted) -> bool:
	return station(world, "quarry") > 0 and link(world, cell_of("quarry"), JUNCTIONS["quarry"]) > 0


func build_steel(world: RefCounted) -> bool:
	return station(world, "steel") > 0 and link(world, cell_of("steel"), cell_of("city")) > 0


func build_iron(world: RefCounted) -> bool:
	return station(world, "iron") > 0 and link(world, cell_of("iron"), JUNCTIONS["iron"]) > 0


func line_of(world: RefCounted, keys: Array[String]) -> Array[int]:
	var ids: Array[int] = []
	for key: String in keys:
		ids.append(id_of(world, key))
	return ids


## Ligne du niveau 1 (un seul train) : la gare du dépôt est desservie deux fois.
func level1_line(world: RefCounted) -> Array[int]:
	return line_of(world, ["mine", "depot", "saw", "depot", "city"] as Array[String])


func level2_line(world: RefCounted) -> Array[int]:
	return line_of(world, ["mine", "depot", "saw", "depot", "city", "quarry"] as Array[String])


## Ligne qui dessert tout le réseau du niveau 3.
func full_line(world: RefCounted) -> Array[int]:
	return line_of(world, ["mine", "depot", "saw", "depot", "city", "steel", "city", "iron", "city", "depot", "quarry"] as Array[String])
