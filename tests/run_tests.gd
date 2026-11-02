extends SceneTree
## Lanceur de tests headless :
##   godot --headless --path . --script res://tests/run_tests.gd
## Code de sortie 0 si tout passe, 1 sinon.

const TEST_FILES: Array[String] = [
	"res://tests/test_iso_projection.gd",
	"res://tests/test_world_map.gd",
	"res://tests/test_sim_clock.gd",
	"res://tests/test_camera.gd",
	"res://tests/test_rail_graph.gd",
	"res://tests/test_rail_network.gd",
	"res://tests/test_rail_drag_path.gd",
	"res://tests/test_rail_planner.gd",
	"res://tests/test_build_controller.gd",
	"res://tests/test_trains.gd",
	"res://tests/test_industry.gd",
	"res://tests/test_dispatcher.gd",
	"res://tests/test_progression.gd",
	"res://tests/test_map_layout.gd",
	"res://tests/test_save_game.gd",
	"res://tests/test_config.gd",
]


var _done: bool = false


## Les tests de nœuds exigent un arbre prêt : on attend la première frame.
func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	_run_all()
	return true


func _run_all() -> void:
	var total: int = 0
	var failed: Array[String] = []
	for path: String in TEST_FILES:
		var script: GDScript = load(path)
		var suite: RefCounted = script.new()
		suite.tree = self
		for method: Dictionary in suite.get_method_list():
			var method_name: String = method["name"]
			if not method_name.begins_with("test_"):
				continue
			total += 1
			suite.begin("%s::%s" % [path.get_file(), method_name])
			suite.call(method_name)
		failed.append_array(suite.failures)
	for message: String in failed:
		printerr("ECHEC  ", message)
	print("%d tests exécutés, %d échec(s)." % [total, failed.size()])
	# Laisse les nœuds libérés par les tests disparaître avant de quitter.
	await process_frame
	await process_frame
	quit(1 if not failed.is_empty() else 0)
