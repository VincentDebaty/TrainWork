extends RefCounted
## Sauvegarde et reprise de la partie : état logique complet, versionné, en JSON.
## La carte n'est pas sauvegardée (pas de duplication du décor procédural) : seulement sa
## graine et la version du générateur, comparées au chargement. Positions des trains,
## stocks, réservations, pièces, niveau et horloge sont restaurés à l'identique : après
## un chargement, la simulation continue exactement comme sans interruption.

const Content = preload("res://src/data/content.gd")

const SAVE_VERSION: int = 1


## État complet. `view` : cadrage de la caméra (position, zoom), conservé entre sessions.
func serialize(world: RefCounted, view: Dictionary = {}, saved_unix: int = -1) -> Dictionary:
	return {
		"save_version": SAVE_VERSION,
		"saved_unix": saved_unix if saved_unix >= 0 else int(Time.get_unix_time_from_system()),
		"map": {"seed": world.map.map_seed, "generator_version": world.map.generator_version,
				"width": world.map.width, "height": world.map.height},
		"network": world.network.to_dict(),
		"sim": world.sim.to_dict(),
		"view": view,
	}


## Chaîne vide si la sauvegarde est utilisable avec cette partie, sinon la raison du refus.
func check(world: RefCounted, data: Dictionary) -> String:
	if data.get("save_version", -1) != SAVE_VERSION:
		return "Version de sauvegarde incompatible (%s)" % str(data.get("save_version", "?"))
	var map: Dictionary = data.get("map", {})
	if map.get("seed", -1) != world.map.map_seed or map.get("generator_version", -1) != world.map.generator_version \
			or map.get("width", -1) != world.map.width or map.get("height", -1) != world.map.height:
		return "La carte de la sauvegarde ne correspond pas à la carte du jeu"
	for key: String in ["network", "sim"]:
		if not data.has(key):
			return "Sauvegarde incomplète (%s manquant)" % key
	return ""


## Restaure dans `world` (partie neuve, sans scénario). Renvoie "" ou la raison de l'échec.
func restore(world: RefCounted, data: Dictionary) -> String:
	var problem: String = check(world, data)
	if problem != "":
		return problem
	world.network.load_dict(data["network"])
	world.sim.load_dict(data["sim"])
	return ""


## Ordre des clés conservé (Godot trie par défaut) : l'ordre d'itération des dictionnaires
## restaurés est ainsi identique, donc la simulation aussi.
static func to_json(data: Dictionary) -> String:
	return JSON.stringify(data, "", false, true)


## Texte JSON -> dictionnaire (entiers rétablis), ou null si illisible.
static func from_json(text: String) -> Variant:
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not (json.data is Dictionary):
		return null
	return Content._intify(json.data)
