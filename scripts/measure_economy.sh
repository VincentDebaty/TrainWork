#!/bin/sh
# Mesure de l'économie sur des scénarios automatiques fixes (voir src/dev/economy_report.gd).
cd "$(dirname "$0")/.." || exit 1
exec godot --headless --path . --script res://src/dev/economy_report.gd 2>&1 | grep -v -E "^Godot Engine|leaked|still in use|^   at: "
