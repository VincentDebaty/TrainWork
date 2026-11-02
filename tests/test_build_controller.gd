extends "res://tests/test_case.gd"

const BuildController = preload("res://src/presentation/build_controller.gd")
const CameraRig = preload("res://src/presentation/camera_rig.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")
const WorldConfig = preload("res://src/data/world_config.gd")
const IsoProjection = preload("res://src/core/iso_projection.gd")
const WorldMap = preload("res://src/core/world_map.gd")

const Mode = BuildController.Mode


class Rig:
	var cam: CameraRig
	var build: BuildController
	var net: RailNetwork
	var proj: IsoProjection


func _rig() -> Rig:
	var cfg: WorldConfig = WorldConfig.new()
	var rig: Rig = Rig.new()
	rig.proj = IsoProjection.new(Vector2(cfg.tile_width, cfg.tile_height))
	rig.net = RailNetwork.new(WorldMap.new(16, 16, 1, 1))
	rig.cam = CameraRig.new()
	rig.build = BuildController.new()
	tree.root.add_child(rig.cam)
	tree.root.add_child(rig.build)
	rig.cam.configure(cfg, rig.proj.map_bounds(Vector2i(16, 16)))
	rig.cam.set_view(rig.proj.cell_center(Vector2i(8, 8)), 1.0)
	rig.build.setup(rig.net, rig.proj, rig.cam)
	return rig


func _free(rig: Rig) -> void:
	rig.cam.queue_free()
	rig.build.queue_free()


## Position écran du centre d'une case, avec la caméra courante.
func _screen_of(rig: Rig, cell: Vector2i) -> Vector2:
	var size: Vector2 = rig.cam.get_viewport_rect().size
	return (rig.proj.cell_center(cell) - rig.cam.position) * rig.cam.view_zoom() + size * 0.5


func _touch(cam: Camera2D, index: int, pressed: bool, pos: Vector2) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = pos
	cam._unhandled_input(event)


func _drag(cam: Camera2D, index: int, pos: Vector2, relative: Vector2 = Vector2.ZERO) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	cam._unhandled_input(event)


func _swipe(rig: Rig, cells: Array[Vector2i]) -> void:
	_touch(rig.cam, 0, true, _screen_of(rig, cells[0]))
	for i: int in range(1, cells.size()):
		var pos: Vector2 = _screen_of(rig, cells[i])
		_drag(rig.cam, 0, pos, pos - _screen_of(rig, cells[i - 1]))
	_touch(rig.cam, 0, false, _screen_of(rig, cells[cells.size() - 1]))


func test_navigate_mode_pans_and_does_not_build() -> void:
	var rig: Rig = _rig()
	var start: Vector2 = rig.cam.position
	_swipe(rig, [Vector2i(6, 6), Vector2i(7, 6), Vector2i(8, 6)] as Array[Vector2i])
	check(not rig.cam.position.is_equal_approx(start), "un doigt déplace la caméra")
	check_eq(rig.net.graph.edge_count(), 0, "aucun rail en mode navigation")
	_free(rig)


func test_swipe_in_rail_mode_lays_track_without_panning() -> void:
	var rig: Rig = _rig()
	rig.build.set_mode(Mode.RAIL)
	var start: Vector2 = rig.cam.position
	_swipe(rig, [Vector2i(5, 8), Vector2i(6, 8), Vector2i(7, 8), Vector2i(8, 8)] as Array[Vector2i])
	check_near_v(rig.cam.position, start, "la caméra ne bouge pas en mode rails")
	check_eq(rig.net.graph.edge_count(), 3, "3 segments posés")
	check(rig.net.graph.is_connected_cells(Vector2i(5, 8), Vector2i(8, 8)), "voie continue")
	_free(rig)


func test_preview_shows_refusals_and_commit_keeps_valid_part() -> void:
	var rig: Rig = _rig()
	rig.build.set_mode(Mode.RAIL)
	var messages: Array[String] = []
	rig.build.message.connect(func(text: String) -> void: messages.append(text))
	var cells: Array[Vector2i] = [Vector2i(5, 8), Vector2i(6, 8), Vector2i(6, 9)]  # coin à 90°
	_touch(rig.cam, 0, true, _screen_of(rig, cells[0]))
	_drag(rig.cam, 0, _screen_of(rig, cells[1]))
	_drag(rig.cam, 0, _screen_of(rig, cells[2]))
	check_eq(rig.build.preview_edges.size(), 2, "aperçu de 2 segments")
	check_eq(rig.build.preview_results[1], RailNetwork.Result.SHARP_TURN, "le virage serré est signalé")
	check_eq(rig.net.graph.edge_count(), 0, "l'aperçu ne pose rien")
	_touch(rig.cam, 0, false, _screen_of(rig, cells[2]))
	check_eq(rig.net.graph.edge_count(), 1, "seule la partie valide est posée")
	check(rig.build.preview_edges.is_empty(), "aperçu effacé")
	check(not messages.is_empty() and messages[0].contains("Virage trop serré"), "message de refus")
	_free(rig)


func test_second_finger_cancels_drawing() -> void:
	var rig: Rig = _rig()
	rig.build.set_mode(Mode.RAIL)
	_touch(rig.cam, 0, true, _screen_of(rig, Vector2i(5, 8)))
	_drag(rig.cam, 0, _screen_of(rig, Vector2i(6, 8)))
	_touch(rig.cam, 1, true, _screen_of(rig, Vector2i(9, 3)))
	check(rig.build.preview_edges.is_empty(), "le second doigt annule l'aperçu")
	_touch(rig.cam, 1, false, Vector2.ZERO)
	_touch(rig.cam, 0, false, _screen_of(rig, Vector2i(6, 8)))
	check_eq(rig.net.graph.edge_count(), 0, "rien posé")
	_free(rig)


func test_station_tool_and_orientation() -> void:
	var rig: Rig = _rig()
	rig.build.set_mode(Mode.STATION)
	rig.build.rotate_station_orientation()
	_touch(rig.cam, 0, true, _screen_of(rig, Vector2i(4, 4)))
	_touch(rig.cam, 0, false, _screen_of(rig, Vector2i(4, 4)))
	var station: RefCounted = rig.net.station_at(Vector2i(4, 4))
	check(station != null, "gare posée par un tap")
	if station != null:
		check_eq(station.orientation, 1, "orientation choisie appliquée")
	_free(rig)


func test_erase_tool_removes_segments_and_station() -> void:
	var rig: Rig = _rig()
	for x: int in range(2, 7):
		rig.net.place_edge(Vector2i(x, 5), Vector2i(x + 1, 5))
	rig.net.place_station(Vector2i(2, 5), 0)
	rig.build.set_mode(Mode.ERASE)
	_swipe(rig, [Vector2i(4, 5), Vector2i(5, 5), Vector2i(6, 5)] as Array[Vector2i])
	check_eq(rig.net.graph.edge_count(), 3, "2 segments effacés par glissement")
	_touch(rig.cam, 0, true, _screen_of(rig, Vector2i(2, 5)))
	_touch(rig.cam, 0, false, _screen_of(rig, Vector2i(2, 5)))
	check(rig.net.station_at(Vector2i(2, 5)) == null, "tap sur une gare : supprimée")
	_free(rig)


func test_touch_under_ui_is_ignored() -> void:
	var rig: Rig = _rig()
	rig.build.set_mode(Mode.RAIL)
	rig.cam.ui_blocker = func(pos: Vector2) -> bool: return pos.y > 600.0
	_touch(rig.cam, 0, true, Vector2(300, 650))
	_drag(rig.cam, 0, Vector2(400, 650))
	_touch(rig.cam, 0, false, Vector2(400, 650))
	check(rig.build.preview_edges.is_empty(), "aucun tracé sous la barre d'outils")
	check_eq(rig.net.graph.edge_count(), 0, "aucun rail")
	_free(rig)


func _tap(rig: Rig, cell: Vector2i) -> void:
	var pos: Vector2 = _screen_of(rig, cell)
	_touch(rig.cam, 0, true, pos)
	_touch(rig.cam, 0, false, pos)


func test_tap_to_place_rails_and_undo() -> void:
	var rig: Rig = _rig()
	rig.build.set_mode(Mode.RAIL)
	for x: int in range(3, 6):
		rig.net.place_edge(Vector2i(x, 8), Vector2i(x + 1, 8))
	_tap(rig, Vector2i(7, 8))
	check(rig.net.graph.has_edge(Vector2i(6, 8), Vector2i(7, 8)), "un toucher prolonge la voie")
	_tap(rig, Vector2i(8, 8))
	check(rig.net.graph.has_edge(Vector2i(7, 8), Vector2i(8, 8)), "et encore")
	check(rig.build.has_head and rig.build.head == Vector2i(8, 8), "la tête suit le dernier rail")
	rig.build.undo()
	check(not rig.net.graph.has_edge(Vector2i(7, 8), Vector2i(8, 8)), "annulation du dernier rail")
	check(rig.net.graph.has_edge(Vector2i(6, 8), Vector2i(7, 8)), "le précédent reste")
	_free(rig)


func test_tap_corner_is_rounded_and_undo_restores_it() -> void:
	var rig: Rig = _rig()
	rig.build.set_mode(Mode.RAIL)
	for x: int in range(3, 6):
		rig.net.place_edge(Vector2i(x, 8), Vector2i(x + 1, 8))
	_tap(rig, Vector2i(6, 9))
	check(rig.net.graph.has_edge(Vector2i(5, 8), Vector2i(6, 9)), "coin arrondi en diagonale")
	check(not rig.net.graph.has_edge(Vector2i(5, 8), Vector2i(6, 8)), "ancien segment remplacé")
	rig.build.undo()
	check(rig.net.graph.has_edge(Vector2i(5, 8), Vector2i(6, 8)), "l'annulation rétablit le segment d'origine")
	check(not rig.net.graph.has_edge(Vector2i(5, 8), Vector2i(6, 9)), "et retire la diagonale")
	_free(rig)


func test_undo_after_swipe_and_erase() -> void:
	var rig: Rig = _rig()
	rig.build.set_mode(Mode.RAIL)
	_swipe(rig, [Vector2i(3, 8), Vector2i(4, 8), Vector2i(5, 8), Vector2i(6, 8)] as Array[Vector2i])
	check_eq(rig.net.graph.edge_count(), 3, "tracé au doigt")
	rig.build.set_mode(Mode.ERASE)
	_tap(rig, Vector2i(5, 8))
	check_eq(rig.net.graph.edge_count(), 1, "gomme sur une case")
	rig.build.undo()
	check_eq(rig.net.graph.edge_count(), 3, "annuler la gomme")
	rig.build.undo()
	check_eq(rig.net.graph.edge_count(), 0, "annuler le tracé")
	rig.build.undo()
	check_eq(rig.net.graph.edge_count(), 0, "annuler à vide est sans effet")
	_free(rig)


func test_launching_the_same_line_twice_adds_a_second_train() -> void:
	var rig: Rig = _rig()
	var trains_sim: RefCounted = (load("res://src/sim/train_simulator.gd") as GDScript).new(rig.net, (load("res://src/sim/sim_params.gd") as GDScript).new(0.2, 2.0, 3.0, 1.0, 2))
	var content: RefCounted = (load("res://src/data/content.gd") as GDScript).new()
	content.load_from()
	content.logistics["max_trains"] = 2
	trains_sim.content = content  # 2 quais par gare, 2 trains maximum
	rig.build.setup(rig.net, rig.proj, rig.cam, trains_sim)
	rig.net.place_station(Vector2i(3, 8), 0)
	rig.net.place_station(Vector2i(9, 8), 0)
	for x: int in range(3, 9):
		rig.net.place_edge(Vector2i(x, 8), Vector2i(x + 1, 8))
	var a: int = rig.net.station_at(Vector2i(3, 8)).id
	var b: int = rig.net.station_at(Vector2i(9, 8)).id
	rig.build.pending_stations = [a, b] as Array[int]
	rig.build.launch_line()
	check_eq(trains_sim.lines.size(), 1, "une ligne")
	rig.build.pending_stations = [a, b] as Array[int]
	rig.build.launch_line()
	check_eq(trains_sim.lines.size(), 1, "la ligne identique est réutilisée")
	check_eq(trains_sim.trains.size(), 2, "deux trains sur la ligne")
	_free(rig)


func test_launch_modifies_the_only_line_when_trains_are_at_maximum() -> void:
	var rig: Rig = _rig()
	var trains_sim: RefCounted = (load("res://src/sim/train_simulator.gd") as GDScript).new(rig.net, (load("res://src/sim/sim_params.gd") as GDScript).new(0.2, 2.0, 3.0, 1.0, 1))
	rig.build.setup(rig.net, rig.proj, rig.cam, trains_sim)
	for x: int in [3, 9, 13]:
		rig.net.place_station(Vector2i(x, 8), 0)
	for x: int in range(3, 13):
		rig.net.place_edge(Vector2i(x, 8), Vector2i(x + 1, 8))
	var a: int = rig.net.station_at(Vector2i(3, 8)).id
	var b: int = rig.net.station_at(Vector2i(9, 8)).id
	var c: int = rig.net.station_at(Vector2i(13, 8)).id
	var messages: Array[String] = []
	rig.build.message.connect(func(text: String) -> void: messages.append(text))
	rig.build.pending_stations = [a, b] as Array[int]
	rig.build.launch_line()
	rig.build.pending_stations = [a, b, c] as Array[int]
	rig.build.launch_line()
	check_eq(trains_sim.lines.size(), 1, "toujours une seule ligne")
	check_eq(trains_sim.trains.size(), 1, "toujours un seul train")
	check_eq(trains_sim.lines.values()[0].station_ids, [a, b, c] as Array[int], "la ligne a été modifiée")
	check(messages.back().contains("Ligne modifiée"), "message explicite : %s" % messages.back())
	_free(rig)
