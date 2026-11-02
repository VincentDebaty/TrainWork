extends Node
## Point d'entrée : assemble données, simulation, caméra et rendu.
## Seul endroit qui connaît à la fois la simulation et les nœuds visuels.

const WorldConfig = preload("res://src/data/world_config.gd")
const IsoProjection = preload("res://src/core/iso_projection.gd")
const Terrain = preload("res://src/core/terrain.gd")
const GameSimulation = preload("res://src/sim/game_simulation.gd")
const Content = preload("res://src/data/content.gd")
const Train = preload("res://src/sim/train.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const BuildController = preload("res://src/presentation/build_controller.gd")
const GameWorld = preload("res://src/sim/game_world.gd")
const SaveGame = preload("res://src/persistence/save_game.gd")
const SaveStore = preload("res://src/persistence/save_store.gd")
const OfflineCatchup = preload("res://src/sim/offline_catchup.gd")
const Progression = preload("res://src/sim/progression.gd")

const SCENARIO_PATH: String = "res://data/scenario_level1.json"
const MESSAGE_DURATION_SEC: float = 3.0
const SAFE_MARGIN: float = 8.0
const RESET_CONFIRM_SEC: float = 4.0

@export var config: Resource
## Sauvegarde locale (désactivée par les tests et la scène de démonstration).
@export var save_enabled: bool = true
@export var save_path: String = "user://savegame.json"

var _cfg: WorldConfig
var _world: GameWorld
var _store: SaveStore
var _autosave_left: float = 0.0
var _paused_unix: int = -1
var _reset_armed_left: float = 0.0
var _projection: IsoProjection
var _map: RefCounted
var _network: RailNetwork
var _simulation: GameSimulation
var _selected_cell: Vector2i = Vector2i(-1, -1)
var _message_ttl: float = 0.0
var _last_touch: Vector2 = Vector2(-1, -1)

@onready var _view: Node2D = $WorldView
@onready var _industry_view: Node2D = $IndustryView
@onready var _rail_view: Node2D = $RailView
@onready var _train_view: Node2D = $TrainView
@onready var _camera: Camera2D = $Camera
@onready var _build: BuildController = $BuildController
@onready var _hud_label: Label = $Hud/Info
@onready var _message_label: Label = $Hud/Message
@onready var _toolbar: HBoxContainer = $Hud/BuildToolbar


func _ready() -> void:
	_cfg = (config as WorldConfig) if config != null else WorldConfig.new()
	_projection = IsoProjection.new(Vector2(_cfg.tile_width, _cfg.tile_height))
	var content: Content = Content.new()
	if not content.load_from():
		push_error("Contenu de jeu invalide : %s" % content.error)
	var scenario: Variant = Content.parse_file(SCENARIO_PATH)
	if not (scenario is Dictionary):
		push_error("Scénario illisible : %s" % SCENARIO_PATH)
		scenario = {}
	_world = GameWorld.new()
	_world.build(_cfg, content, scenario)
	_map = _world.map
	_network = _world.network
	_simulation = _world.sim
	var view: Dictionary = _load_or_start(scenario)

	_camera.configure(_cfg, _projection.map_bounds(_map.size()))
	_camera.set_view(_start_position(), _cfg.zoom_default)
	if view.has("x") and view.has("y") and view.has("zoom"):
		_camera.set_view(Vector2(view["x"], view["y"]), view["zoom"])  # dernier cadrage conservé
	_camera.world_tapped.connect(_on_world_tapped)
	_camera.ui_blocker = func(pos: Vector2) -> bool: return _toolbar.get_global_rect().has_point(pos)
	_view.setup(_map, _projection, _camera, _cfg.debug_draw_grid)

	_build.setup(_network, _projection, _camera, _simulation.trains, _simulation.construction)
	_train_view.setup(_simulation, _projection)
	_industry_view.setup(_simulation, _network, _projection, _build)
	_rail_view.setup(_network, _projection, _camera, _build)
	_build.message.connect(_show_message)
	_simulation.trains.deadlock_changed.connect(func(_ids: Array, text: String) -> void:
		if text != "":
			_show_message(text))
	_simulation.progression.level_changed.connect(_on_level_changed)
	_build.mode_changed.connect(_toolbar.show_mode)
	_toolbar.mode_selected.connect(_build.set_mode)
	_toolbar.action_requested.connect(_on_toolbar_action)
	_toolbar.set_action_text("rotate", "Axe : %s" % _build.orientation_name())
	_toolbar.show_mode(_build.mode)
	_autosave_left = float(_simulation.content.logistic("autosave_interval_sec", 30))

	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()

	_hud_label.visible = _cfg.show_debug_hud
	for label: Label in [_hud_label, _message_label]:
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_outline_color", Color.BLACK)
		label.add_theme_constant_override("outline_size", 6)


func _input(event: InputEvent) -> void:
	# Diagnostic : dernière position de toucher reçue, en coordonnées du viewport.
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		_last_touch = event.position


## Reprend la sauvegarde si elle existe et convient, sinon commence une partie neuve.
## Renvoie le cadrage sauvegardé (vide pour une partie neuve).
## Partie neuve : la caméra s'ouvre sur le dépôt (le territoire se découvre en se déplaçant).
func _start_position() -> Vector2:
	var depot: RefCounted = _simulation.progression.depot()
	if depot != null:
		return _projection.grid_to_world(depot.center_grid())
	return _projection.grid_to_world(Vector2(_map.width, _map.height) * 0.5)


func _load_or_start(scenario: Dictionary) -> Dictionary:
	if save_enabled:
		_store = SaveStore.new(save_path)
		var data: Variant = _store.load_data()
		if data is Dictionary:
			var problem: String = SaveGame.new().restore(_world, data)
			if problem == "":
				var away: float = Time.get_unix_time_from_system() - float(data.get("saved_unix", 0))
				_report_catch_up(OfflineCatchup.new().catch_up(_simulation, away), "Partie reprise")
				return data.get("view", {})
			push_warning("Sauvegarde ignorée : %s" % problem)
			_show_message("Sauvegarde ignorée : %s. Nouvelle partie." % problem)
	_world.new_game(scenario)
	return {}


func save_now() -> bool:
	if not save_enabled or _store == null:
		return false
	var view: Dictionary = {"x": _camera.position.x, "y": _camera.position.y, "zoom": _camera.view_zoom()}
	return _store.save(SaveGame.new().serialize(_world, view))


func _report_catch_up(report: Dictionary, prefix: String) -> void:
	if report["ticks"] <= 0:
		_show_message(prefix + ".")
		return
	var text: String = "%s : %d min %02d s de jeu rattrapées" % [prefix, int(report["simulated_sec"]) / 60, int(report["simulated_sec"]) % 60]
	if report["capped"]:
		text += " (absence plus longue : rattrapage plafonné)"
	_show_message(text + ".")


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_CLOSE_REQUEST, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if _world != null:
				save_now()
			if what == NOTIFICATION_APPLICATION_PAUSED:
				_paused_unix = int(Time.get_unix_time_from_system())
		NOTIFICATION_APPLICATION_RESUMED:
			if _paused_unix > 0 and _world != null:
				var away: float = Time.get_unix_time_from_system() - _paused_unix
				_paused_unix = -1
				_report_catch_up(OfflineCatchup.new().catch_up(_simulation, away), "Retour")


func _on_level_changed(level: int) -> void:
	var names: PackedStringArray = []
	for type_id: String in _simulation.content.buildings:
		if _simulation.content.building_unlock_level(type_id) == level:
			names.append(_simulation.content.buildings[type_id]["name"])
	for good: String in _simulation.content.unlocked_goods(level):
		if _simulation.content.goods[good].get("unlock_level", 1) == level:
			names.append("wagon " + _simulation.content.good_name(good).to_lower())
	_show_message("Niveau %d ! Nouveau : %s." % [level, ", ".join(names)])
	save_now()


func _process(delta: float) -> void:
	_simulation.advance(delta)
	_autosave_left -= delta
	if _autosave_left <= 0.0:
		_autosave_left = float(_simulation.content.logistic("autosave_interval_sec", 30))
		save_now()
	if _reset_armed_left > 0.0:
		_reset_armed_left -= delta
	var prog: Progression = _simulation.progression
	_toolbar.set_action_enabled("upgrade", prog.can_upgrade())
	_toolbar.set_action_text("upgrade", "Niveau max" if prog.is_max_level() else "Améliorer → N%d" % (prog.level + 1))
	if _cfg.show_debug_hud:
		_hud_label.text = _hud_text()
		# Le message temporaire s'affiche sous le HUD, quelle que soit sa hauteur.
		_message_label.offset_top = _hud_label.offset_top + _hud_label.get_minimum_size().y + 8.0
	if _message_ttl > 0.0:
		_message_ttl -= delta
		if _message_ttl <= 0.0:
			_message_label.text = ""


## Décale l'interface hors des zones non sûres (îlot dynamique, coins arrondis,
## indicateur d'accueil). La zone sûre est donnée en coordonnées d'écran : on mesure
## donc les marges par rapport à la fenêtre. Sur ordinateur, la fenêtre est entièrement
## dans la zone sûre : aucun décalage.
func _apply_safe_area() -> void:
	var window: Rect2 = Rect2(Vector2(DisplayServer.window_get_position()), Vector2(DisplayServer.window_get_size()))
	var safe: Rect2 = Rect2(DisplayServer.get_display_safe_area())
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	if window.size.x <= 0.0 or window.size.y <= 0.0 or safe.size.x <= 0.0 or safe.size.y <= 0.0:
		return
	var scale: Vector2 = view_size / window.size
	var left: float = maxf(safe.position.x - window.position.x, 0.0) * scale.x
	var top: float = maxf(safe.position.y - window.position.y, 0.0) * scale.y
	var right: float = maxf(window.end.x - safe.end.x, 0.0) * scale.x
	var bottom: float = maxf(window.end.y - safe.end.y, 0.0) * scale.y
	_toolbar.offset_left = SAFE_MARGIN + left
	_toolbar.offset_right = -SAFE_MARGIN - right
	_toolbar.offset_top = -80.0 - SAFE_MARGIN - bottom
	_toolbar.offset_bottom = -SAFE_MARGIN - bottom
	_hud_label.offset_left = 16.0 + left
	_hud_label.offset_top = 12.0 + top
	_message_label.offset_left = 16.0 + left
	_message_label.offset_top = 124.0 + top


func _on_world_tapped(world_pos: Vector2) -> void:
	if _build.mode != BuildController.Mode.NAVIGATE:
		return
	var cell: Vector2i = _projection.world_to_cell(world_pos)
	_selected_cell = cell if _map.in_bounds(cell) else Vector2i(-1, -1)
	_view.select_cell(_selected_cell)


func _on_toolbar_action(action: String) -> void:
	match action:
		"undo":
			_build.undo()
		"rotate":
			_build.rotate_station_orientation()
			_toolbar.set_action_text("rotate", "Axe : %s" % _build.orientation_name())
		"launch":
			_build.launch_line()
		"clear":
			_build.clear_pending()
		"remove_lines":
			_build.remove_all_lines()
		"upgrade":
			var result: int = _simulation.progression.upgrade()
			if result != Progression.Result.OK:
				_show_message(Progression.result_text(result))
		"reset":
			if _reset_armed_left <= 0.0:
				_reset_armed_left = RESET_CONFIRM_SEC
				_show_message("Touchez encore « Recommencer » pour effacer la partie.")
			else:
				if _store != null:
					_store.delete()
				save_enabled = false  # ne pas réécrire l'ancienne partie en quittant la scène
				get_tree().reload_current_scene()


func _show_message(text: String) -> void:
	_message_label.text = text
	_message_ttl = MESSAGE_DURATION_SEC


func _hud_text() -> String:
	var graph: RefCounted = _network.graph
	var text: String = "Pas sim. %d (%.1f s)  |  zoom x%.2f  |  %d FPS\nPièces : %.1f   |   Rails : %d segments, %d aiguillage(s), %d gare(s)" % [
		_simulation.tick, _simulation.sim_time_sec(), _camera.view_zoom(), Engine.get_frames_per_second(),
		_simulation.economy.coins(), graph.edge_count(), graph.switch_count(), _network.station_count()]
	for id: int in _simulation.trains.trains:
		var train: Train = _simulation.trains.trains[id]
		var station: RefCounted = _network.station_by_id(train.route[train.stop_index])
		var target: RefCounted = _network.station_by_id(train.route[train.target_index])
		text += "\nTrain %d : %s" % [train.id, Train.STATE_NAMES[train.state]]
		if station != null and train.state == Train.State.DWELLING:
			text += " (%s)" % station.station_name
		elif target != null:
			text += " vers %s" % target.station_name
		text += " | " + _cargo_text(train.cargo)
		if train.state == Train.State.WAITING_CLEARANCE:
			text += "\n    " + _simulation.trains.wait_text(train.id)
	for id: int in _simulation.trains.lines:
		var names: PackedStringArray = []
		for station_id: int in _simulation.trains.lines[id].station_ids:
			var station: RefCounted = _network.station_by_id(station_id)
			names.append(station.station_name if station != null else "?")
		text += "\nLigne %d : %s" % [id, " > ".join(names)]
	text += "\n" + _progress_text()
	if _build.preview_cost_milli > 0:
		text += "\nCoût du tracé : %.0f pièce(s)" % (_build.preview_cost_milli / 1000.0)
	elif _build.mode == BuildController.Mode.STATION:
		text += "\nGare : %.0f pièces" % (_simulation.construction.station_cost() / 1000.0)
	if _simulation.trains.deadlock_text != "":
		text += "\n!! " + _simulation.trains.deadlock_text
	if _build.mode == BuildController.Mode.LINE:
		text += "\nLigne en préparation : %d gare(s)" % _build.pending_stations.size()
	text += "\nMode %d | dernier toucher (%d, %d) | viewport %dx%d" % [
		_build.mode, _last_touch.x, _last_touch.y, get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y]
	if _map.in_bounds(_selected_cell):
		text += "\n" + _cell_info(_selected_cell)
	return text


## Niveau et conditions du prochain niveau, une ligne par condition.
func _progress_text() -> String:
	var prog: Progression = _simulation.progression
	if prog.is_max_level():
		return "Niveau %d (maximum du prototype)" % prog.level
	var text: String = "Niveau %d -> %d :" % [prog.level, prog.level + 1]
	var rows: Array[Dictionary] = prog.status()
	for i: int in rows.size():
		var row: Dictionary = rows[i]
		# Pièces et matériaux sur la première ligne, un objectif par ligne ensuite.
		var separator: String = "  " if i <= _materials_count() else "\n    "
		text += "%s[%s] %s %d/%d" % [separator, "ok" if row["ok"] else "..", row["label"], mini(row["have"], row["need"]), row["need"]]
	return text


func _materials_count() -> int:
	return _simulation.content.progression_for(_simulation.progression.level).get("materials", {}).size()


func _cargo_text(cargo: RefCounted) -> String:
	var parts: PackedStringArray = []
	for good: String in _simulation.content.good_ids():
		if cargo.capacity(good) > 0:
			parts.append("%s %d/%d" % [_simulation.content.good_name(good), cargo.total(good), cargo.capacity(good)])
	return "cargaison : " + (", ".join(parts) if not parts.is_empty() else "aucun wagon")


## Fiche d'information d'une case : bâtiment, gare (entrepôt) ou terrain.
func _cell_info(cell: Vector2i) -> String:
	var content: RefCounted = _simulation.content
	var building: RefCounted = _simulation.industry.building_at(cell)
	if building != null and not _simulation.industry.is_active(building):
		return "Case (%d, %d) : %s — site réservé pour une extension future" % [cell.x, cell.y, Terrain.display_name(_map.get_terrain(cell))]
	if building != null:
		var type: Dictionary = content.buildings[building.type_id]
		var text: String = "%s (%s)" % [type["name"], building.STATE_NAMES[building.state]]
		var station: RefCounted = _network.station_by_id(building.station_id)
		text += " | gare : %s" % (station.station_name if station != null else "aucune à portée")
		for good: String in building.outputs:
			text += "\n  sortie %s : %d/%d" % [content.good_name(good), building.outputs[good], type["output_cap"]]
		if not _simulation.industry.is_active(building):
			text += "\n  débloqué au niveau %d" % content.building_unlock_level(building.type_id)
		for good: String in _simulation.industry.active_inputs(building):
			text += "\n  entrée %s : %d/%d" % [content.good_name(good), building.inputs.get(good, 0), _simulation.industry.input_cap(building, good)]
		return text
	var gare: RefCounted = _network.station_at(cell)
	if gare != null:
		var stock: RefCounted = _simulation.industry.warehouse(gare.id)
		var text: String = "%s : entrepôt" % gare.station_name
		for good: String in content.good_ids():
			text += " | %s %d/%d" % [content.good_name(good), stock.total(good), stock.capacity(good)]
		var served: PackedStringArray = []
		for id: int in _simulation.industry.buildings:
			if _simulation.industry.buildings[id].station_id == gare.id:
				served.append(content.buildings[_simulation.industry.buildings[id].type_id]["name"])
		text += "\n  dessert : " + (", ".join(served) if not served.is_empty() else "aucun bâtiment")
		return text
	return "Case (%d, %d) : %s" % [cell.x, cell.y, Terrain.display_name(_map.get_terrain(cell))]
