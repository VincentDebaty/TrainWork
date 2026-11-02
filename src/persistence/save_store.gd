extends RefCounted
## Fichier de sauvegarde local. Écriture sûre en cas de fermeture brutale : on écrit un
## fichier temporaire complet, on le relit pour le vérifier, on garde l'ancienne
## sauvegarde en copie de secours, puis on renomme. Une copie corrompue ne remplace
## jamais une bonne sauvegarde ; au chargement, on retombe sur la copie de secours.

const SaveGame = preload("res://src/persistence/save_game.gd")

var path: String = "user://savegame.json"


func _init(p_path: String = "user://savegame.json") -> void:
	path = p_path


func exists() -> bool:
	return FileAccess.file_exists(path) or FileAccess.file_exists(_backup_path())


func save(data: Dictionary) -> bool:
	var temp: String = path + ".tmp"
	var file: FileAccess = FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return false
	var text: String = SaveGame.to_json(data)
	file.store_string(text)
	file.close()
	if FileAccess.get_file_as_string(temp) != text or SaveGame.from_json(FileAccess.get_file_as_string(temp)) == null:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(temp))
		return false
	if FileAccess.file_exists(path):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(_backup_path()))
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path)) == OK


## Dernière sauvegarde lisible (principale, sinon copie de secours), ou null.
func load_data() -> Variant:
	for candidate: String in [path, _backup_path()]:
		if FileAccess.file_exists(candidate):
			var data: Variant = SaveGame.from_json(FileAccess.get_file_as_string(candidate))
			if data != null:
				return data
	return null


func delete() -> void:
	for candidate: String in [path, _backup_path(), path + ".tmp"]:
		if FileAccess.file_exists(candidate):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(candidate))


func _backup_path() -> String:
	return path + ".bak"
