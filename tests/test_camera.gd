extends "res://tests/test_case.gd"

const CameraMath = preload("res://src/core/camera_math.gd")
const CameraRig = preload("res://src/presentation/camera_rig.gd")
const WorldConfig = preload("res://src/data/world_config.gd")
const IsoProjection = preload("res://src/core/iso_projection.gd")
const MapGenerator = preload("res://src/core/map_generator.gd")
const GameSimulation = preload("res://src/sim/game_simulation.gd")
const SimParams = preload("res://src/sim/sim_params.gd")
const RailNetwork = preload("res://src/rail/rail_network.gd")

const VIEWPORT: Vector2 = Vector2(1280, 720)


func test_anchor_and_screen_to_world_are_inverse() -> void:
	var world: Vector2 = Vector2(1234, 567)
	for zoom: float in [0.5, 1.0, 2.5]:
		for screen: Vector2 in [Vector2(0, 0), Vector2(640, 360), Vector2(1000, 100)]:
			var pos: Vector2 = CameraMath.anchor_position(world, screen, zoom, VIEWPORT)
			check_near_v(CameraMath.screen_to_world(screen, pos, zoom, VIEWPORT), world, "ancrage z=%f" % zoom)


func test_zoom_keeps_focus_point_fixed() -> void:
	var pos: Vector2 = Vector2(100, 200)
	var focus: Vector2 = Vector2(900, 150)
	var before: Vector2 = CameraMath.screen_to_world(focus, pos, 1.0, VIEWPORT)
	var new_pos: Vector2 = CameraMath.anchor_position(before, focus, 2.0, VIEWPORT)
	check_near_v(CameraMath.screen_to_world(focus, new_pos, 2.0, VIEWPORT), before, "point sous le doigt inchangé")


func test_clamps() -> void:
	check_near(CameraMath.clamp_zoom(9.0, 0.5, 2.5), 2.5, "zoom max")
	check_near(CameraMath.clamp_zoom(0.1, 0.5, 2.5), 0.5, "zoom min")
	check_near_v(CameraMath.clamp_position(Vector2(-9999, 99999), Rect2(-100, 0, 200, 400)), Vector2(-100, 400), "position bornée")


func test_visible_rect() -> void:
	var rect: Rect2 = CameraMath.visible_world_rect(Vector2(0, 0), 2.0, VIEWPORT)
	check_near_v(rect.size, Vector2(640, 360), "taille visible à zoom 2")
	check_near_v(rect.get_center(), Vector2.ZERO, "centrée sur la caméra")


## Pan, pincement et clamp via de vrais événements d'entrée, sans effet sur carte ni simulation.
func test_gestures_do_not_touch_simulation_or_map() -> void:
	var cfg: WorldConfig = WorldConfig.new()
	var proj: IsoProjection = IsoProjection.new(Vector2(cfg.tile_width, cfg.tile_height))
	var map: RefCounted = MapGenerator.generate(cfg.map_width, cfg.map_height, cfg.map_seed, cfg.generator_version)
	var map_checksum: int = map.checksum()
	var sim_a: GameSimulation = GameSimulation.new(SimParams.new(cfg.sim_step_sec), cfg.sim_max_steps_per_frame, RailNetwork.new(map))
	var sim_b: GameSimulation = GameSimulation.new(SimParams.new(cfg.sim_step_sec), cfg.sim_max_steps_per_frame, RailNetwork.new(map))

	var cam: CameraRig = CameraRig.new()
	tree.root.add_child(cam)
	cam.configure(cfg, proj.map_bounds(map.size()))
	cam.set_view(proj.grid_to_world(Vector2(32, 32)), 1.0)
	var viewport_size: Vector2 = cam.get_viewport_rect().size

	# Pan à un doigt : le contenu suit le doigt.
	var start_pos: Vector2 = cam.position
	_touch(cam, 0, true, Vector2(500, 400))
	_drag(cam, 0, Vector2(400, 380), Vector2(-100, -20))
	_touch(cam, 0, false, Vector2(400, 380))
	check_near_v(cam.position, start_pos + Vector2(100, 20), "pan à zoom 1")

	# Pincement : le point monde sous le milieu des doigts reste sous le milieu.
	var mid_before: Vector2 = viewport_size * 0.5
	var anchor: Vector2 = cam.screen_to_world(mid_before)
	_touch(cam, 0, true, mid_before - Vector2(100, 0))
	_touch(cam, 1, true, mid_before + Vector2(100, 0))
	_drag(cam, 0, mid_before - Vector2(200, 0), Vector2(-100, 0))
	_drag(cam, 1, mid_before + Vector2(200, 0), Vector2(100, 0))
	check_near(cam.view_zoom(), 2.0, "pincement x2")
	check_near_v(cam.screen_to_world(mid_before), anchor, "point central stable")
	_touch(cam, 0, false, Vector2.ZERO)
	_touch(cam, 1, false, Vector2.ZERO)

	# Limites de zoom et de carte.
	cam.set_view(Vector2(1e7, -1e7), 100.0)
	check_near(cam.view_zoom(), cfg.zoom_max, "zoom plafonné")
	check(proj.map_bounds(map.size()).grow(0.01).has_point(cam.position), "caméra reste sur la carte")
	cam.set_view(Vector2.ZERO, 0.001)
	check_near(cam.view_zoom(), cfg.zoom_min, "zoom plancher")

	# La simulation avance de la même façon avec ou sans manipulation de caméra.
	for _i: int in 100:
		sim_a.advance(0.05)
		cam.set_view(cam.position + Vector2(13, 7), cam.view_zoom() * 1.01)
		sim_b.advance(0.05)
	check_eq(sim_a.state_checksum(), sim_b.state_checksum(), "simulation indépendante de la caméra")
	check_eq(map.checksum(), map_checksum, "carte inchangée")
	cam.queue_free()


func test_tap_vs_drag() -> void:
	var cfg: WorldConfig = WorldConfig.new()
	var proj: IsoProjection = IsoProjection.new(Vector2(cfg.tile_width, cfg.tile_height))
	var cam: CameraRig = CameraRig.new()
	tree.root.add_child(cam)
	cam.configure(cfg, proj.map_bounds(Vector2i(64, 64)))
	cam.set_view(Vector2(0, 2048), 1.0)
	var taps: Array[Vector2] = []
	cam.world_tapped.connect(func(p: Vector2) -> void: taps.append(p))

	_touch(cam, 0, true, Vector2(300, 300))
	_touch(cam, 0, false, Vector2(302, 301))
	check_eq(taps.size(), 1, "un tap court émet world_tapped")

	_touch(cam, 0, true, Vector2(300, 300))
	_drag(cam, 0, Vector2(360, 300), Vector2(60, 0))
	_touch(cam, 0, false, Vector2(360, 300))
	check_eq(taps.size(), 1, "un glissement n'est pas un tap")
	cam.queue_free()


func _touch(cam: Camera2D, index: int, pressed: bool, pos: Vector2) -> void:
	var event: InputEventScreenTouch = InputEventScreenTouch.new()
	event.index = index
	event.pressed = pressed
	event.position = pos
	cam._unhandled_input(event)


func _drag(cam: Camera2D, index: int, pos: Vector2, relative: Vector2) -> void:
	var event: InputEventScreenDrag = InputEventScreenDrag.new()
	event.index = index
	event.position = pos
	event.relative = relative
	cam._unhandled_input(event)
