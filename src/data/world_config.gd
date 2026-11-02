extends Resource
## Constantes d'essai du prototype. Valeurs PROVISOIRES, non validées :
## à éditer dans data/world_config.tres, jamais en dur dans le code.

@export_group("Carte")
@export var map_width: int = 80
@export var map_height: int = 80
@export var map_seed: int = 1865
@export var generator_version: int = 2

@export_group("Projection")
## Taille du losange d'une case à l'écran (ratio 2:1), en pixels à zoom 1.
@export var tile_width: float = 128.0
@export var tile_height: float = 64.0

@export_group("Simulation")
@export var sim_step_sec: float = 0.2
@export var sim_max_steps_per_frame: int = 25

@export_group("Trains")
## Valeurs d'essai, non validées.
@export var train_speed_cells_per_sec: float = 2.0
@export var station_dwell_sec: float = 3.0
@export var no_route_retry_sec: float = 1.0
## Repli si `content.json` ne définit pas `max_trains` (qui l'emporte).
@export var max_trains: int = 1

@export_group("Caméra")
@export var zoom_default: float = 1.0
@export var zoom_min: float = 0.5
@export var zoom_max: float = 2.5
@export var wheel_zoom_step: float = 1.1
## Vitesse du défilement au pavé tactile (Mac) : pixels écran par unité de geste.
@export var pan_gesture_speed: float = 10.0
@export var tap_max_move_px: float = 12.0
@export var tap_max_duration_ms: int = 350

@export_group("Debug")
@export var debug_draw_grid: bool = false
@export var show_debug_hud: bool = true
