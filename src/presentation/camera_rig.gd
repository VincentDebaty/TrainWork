extends Camera2D
## Caméra tactile : un doigt = panoramique, deux doigts = pincement (zoom + pan),
## taper = `world_tapped`. Au bureau : la souris est émulée en toucher
## (glisser = pan), molette = zoom, pavé tactile = pan / pincement.
## Cette caméra ne touche jamais à la simulation.
##
## Mode pointeur : si `single_finger_pan` est faux (outils de construction), un doigt
## n'est plus un pan mais émet `pointer_*` ; un second doigt annule le geste en cours
## (`pointer_cancelled`) et le pincement reste disponible.

const CameraMath = preload("res://src/core/camera_math.gd")

signal view_changed
signal world_tapped(world_pos: Vector2)
signal pointer_pressed(world_pos: Vector2)
signal pointer_dragged(world_pos: Vector2)
signal pointer_released(world_pos: Vector2)
signal pointer_cancelled

var single_finger_pan: bool = true
## Appelable (position écran) -> bool : vrai si l'interface couvre ce point.
## Un toucher qui démarre sous l'interface est ignoré par la caméra.
var ui_blocker: Callable = Callable()

var _bounds: Rect2 = Rect2()
var _zoom_min: float = 0.5
var _zoom_max: float = 2.5
var _wheel_step: float = 1.1
var _pan_gesture_speed: float = 10.0
var _tap_max_move_px: float = 12.0
var _tap_max_duration_ms: int = 350

var _touches: Dictionary = {}  # index du doigt -> position écran courante
var _ignored: Dictionary = {}  # doigts démarrés sous l'interface
var _tap_index: int = -1
var _tap_start_pos: Vector2 = Vector2.ZERO
var _tap_start_ms: int = 0
var _pointer_index: int = -1
var _pinch_prev_dist: float = 0.0
var _pinch_prev_mid: Vector2 = Vector2.ZERO


func _ready() -> void:
	get_viewport().size_changed.connect(_on_viewport_resized)


func configure(config: Resource, world_bounds: Rect2) -> void:
	_bounds = world_bounds
	_zoom_min = config.zoom_min
	_zoom_max = config.zoom_max
	_wheel_step = config.wheel_zoom_step
	_pan_gesture_speed = config.pan_gesture_speed
	_tap_max_move_px = config.tap_max_move_px
	_tap_max_duration_ms = config.tap_max_duration_ms


func view_zoom() -> float:
	return zoom.x


## Fixe le cadrage en le contraignant aux limites de zoom et de carte.
func set_view(pos: Vector2, new_zoom: float) -> void:
	var z: float = CameraMath.clamp_zoom(new_zoom, _zoom_min, _zoom_max)
	var p: Vector2 = CameraMath.clamp_position(pos, _bounds)
	if p.is_equal_approx(position) and is_equal_approx(z, zoom.x):
		return
	position = p
	zoom = Vector2(z, z)
	view_changed.emit()


func screen_to_world(screen: Vector2) -> Vector2:
	return CameraMath.screen_to_world(screen, position, zoom.x, get_viewport_rect().size)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_on_touch(event as InputEventScreenTouch)
	elif event is InputEventScreenDrag:
		_on_drag(event as InputEventScreenDrag)
	elif event is InputEventMouseButton:
		_on_mouse_button(event as InputEventMouseButton)
	elif event is InputEventMagnifyGesture:
		var magnify: InputEventMagnifyGesture = event as InputEventMagnifyGesture
		_zoom_at(magnify.position, magnify.factor)
	elif event is InputEventPanGesture:
		var pan: InputEventPanGesture = event as InputEventPanGesture
		set_view(position + pan.delta * _pan_gesture_speed / zoom.x, zoom.x)


func _on_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		if ui_blocker.is_valid() and ui_blocker.call(event.position):
			_ignored[event.index] = true
			return
		_touches[event.index] = event.position
		if _touches.size() == 1:
			_tap_index = event.index
			_tap_start_pos = event.position
			_tap_start_ms = Time.get_ticks_msec()
			if not single_finger_pan:
				_pointer_index = event.index
				pointer_pressed.emit(screen_to_world(event.position))
		else:
			_tap_index = -1
			_cancel_pointer()
		_reset_pinch_reference()
		return
	if _ignored.erase(event.index) or not _touches.has(event.index):
		return
	if event.index == _tap_index and _touches.size() == 1:
		var duration_ms: int = Time.get_ticks_msec() - _tap_start_ms
		if duration_ms <= _tap_max_duration_ms and event.position.distance_to(_tap_start_pos) <= _tap_max_move_px:
			world_tapped.emit(screen_to_world(event.position))
	if event.index == _pointer_index:
		_pointer_index = -1
		pointer_released.emit(screen_to_world(event.position))
	_touches.erase(event.index)
	_tap_index = -1
	_reset_pinch_reference()


func _on_drag(event: InputEventScreenDrag) -> void:
	if not _touches.has(event.index):
		return
	_touches[event.index] = event.position
	if _touches.size() == 1:
		if event.index == _tap_index and event.position.distance_to(_tap_start_pos) > _tap_max_move_px:
			_tap_index = -1
		if event.index == _pointer_index:
			pointer_dragged.emit(screen_to_world(event.position))
		elif single_finger_pan:
			set_view(position - event.relative / zoom.x, zoom.x)
		return
	var fingers: Array[Vector2] = _first_two_fingers()
	var dist: float = fingers[0].distance_to(fingers[1])
	var mid: Vector2 = (fingers[0] + fingers[1]) * 0.5
	if _pinch_prev_dist > 0.0 and dist > 0.0:
		# Le point monde sous le milieu des doigts reste sous le milieu des doigts.
		var new_zoom: float = CameraMath.clamp_zoom(zoom.x * dist / _pinch_prev_dist, _zoom_min, _zoom_max)
		var anchor_world: Vector2 = screen_to_world(_pinch_prev_mid)
		set_view(CameraMath.anchor_position(anchor_world, mid, new_zoom, get_viewport_rect().size), new_zoom)
	_pinch_prev_dist = dist
	_pinch_prev_mid = mid


func _on_mouse_button(event: InputEventMouseButton) -> void:
	if not event.pressed:
		return
	if event.button_index == MOUSE_BUTTON_WHEEL_UP:
		_zoom_at(event.position, _wheel_step)
	elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_zoom_at(event.position, 1.0 / _wheel_step)


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var new_zoom: float = CameraMath.clamp_zoom(zoom.x * factor, _zoom_min, _zoom_max)
	var anchor_world: Vector2 = screen_to_world(screen_point)
	set_view(CameraMath.anchor_position(anchor_world, screen_point, new_zoom, get_viewport_rect().size), new_zoom)


func _cancel_pointer() -> void:
	if _pointer_index != -1:
		_pointer_index = -1
		pointer_cancelled.emit()


func _first_two_fingers() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for finger: int in _touches:
		result.append(_touches[finger])
		if result.size() == 2:
			break
	return result


func _reset_pinch_reference() -> void:
	if _touches.size() >= 2:
		var fingers: Array[Vector2] = _first_two_fingers()
		_pinch_prev_dist = fingers[0].distance_to(fingers[1])
		_pinch_prev_mid = (fingers[0] + fingers[1]) * 0.5
	else:
		_pinch_prev_dist = 0.0


func _on_viewport_resized() -> void:
	set_view(position, zoom.x)
