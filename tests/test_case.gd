extends RefCounted
## Base minimale des tests : les méthodes `test_*` des classes filles sont
## découvertes et exécutées par tests/run_tests.gd.

var failures: Array[String] = []
var tree: SceneTree
var _current: String = ""


func begin(test_name: String) -> void:
	_current = test_name


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append("%s : %s" % [_current, message])


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s : %s (obtenu %s, attendu %s)" % [_current, message, str(actual), str(expected)])


func check_near(actual: float, expected: float, message: String, epsilon: float = 0.001) -> void:
	if absf(actual - expected) > epsilon:
		failures.append("%s : %s (obtenu %f, attendu %f)" % [_current, message, actual, expected])


func check_near_v(actual: Vector2, expected: Vector2, message: String, epsilon: float = 0.01) -> void:
	if actual.distance_to(expected) > epsilon:
		failures.append("%s : %s (obtenu %s, attendu %s)" % [_current, message, str(actual), str(expected)])
