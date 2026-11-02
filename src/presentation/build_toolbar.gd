extends HBoxContainer
## Barre d'outils placeholder, en bas de l'écran : modes de construction et actions
## propres au mode actif.

signal mode_selected(mode: int)
signal action_requested(action: String)

const BuildController = preload("res://src/presentation/build_controller.gd")

const MODE_LABELS: Dictionary = {
	BuildController.Mode.NAVIGATE: "Naviguer",
	BuildController.Mode.RAIL: "Rails",
	BuildController.Mode.STATION: "Gare",
	BuildController.Mode.LINE: "Ligne",
	BuildController.Mode.ERASE: "Gomme",
}
## Actions affichées selon le mode : [id, libellé, modes concernés].
const ACTIONS: Array = [
	["upgrade", "Améliorer", [BuildController.Mode.NAVIGATE]],
	["reset", "Recommencer", [BuildController.Mode.NAVIGATE]],
	["undo", "Annuler", [BuildController.Mode.RAIL, BuildController.Mode.ERASE]],
	["rotate", "Axe", [BuildController.Mode.STATION]],
	["launch", "Lancer", [BuildController.Mode.LINE]],
	["clear", "Vider", [BuildController.Mode.LINE]],
	["remove_lines", "Retirer", [BuildController.Mode.LINE]],
]

var _mode_buttons: Dictionary = {}
var _action_buttons: Dictionary = {}  # id -> {"button": Button, "modes": Array}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Les décalages sont ajustés par Main selon les zones sûres de l'écran.
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 6)
	var group: ButtonGroup = ButtonGroup.new()
	for mode: int in MODE_LABELS:
		var button: Button = _make_button(MODE_LABELS[mode])
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = (mode == BuildController.Mode.NAVIGATE)
		button.pressed.connect(func() -> void: mode_selected.emit(mode))
		_mode_buttons[mode] = button
		add_child(button)
	for entry: Array in ACTIONS:
		var action: String = entry[0]
		var button: Button = _make_button(entry[1])
		button.visible = false
		button.pressed.connect(func() -> void: action_requested.emit(action))
		_action_buttons[action] = {"button": button, "modes": entry[2]}
		add_child(button)


func show_mode(mode: int) -> void:
	_mode_buttons[mode].button_pressed = true
	for action: String in _action_buttons:
		_action_buttons[action]["button"].visible = mode in _action_buttons[action]["modes"]


func set_action_text(action: String, text: String) -> void:
	_action_buttons[action]["button"].text = text


func set_action_enabled(action: String, enabled: bool) -> void:
	_action_buttons[action]["button"].disabled = not enabled


func _make_button(text: String) -> Button:
	var button: Button = Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(124, 72)
	button.add_theme_font_size_override("font_size", 22)
	button.focus_mode = Control.FOCUS_NONE
	return button
