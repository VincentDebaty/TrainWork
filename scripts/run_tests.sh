#!/bin/sh
# Lance les tests headless. Code de sortie 0 si tout passe.
cd "$(dirname "$0")/.." || exit 1
exec godot --headless --path . --script res://tests/run_tests.gd
