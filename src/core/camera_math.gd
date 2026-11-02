extends RefCounted
## Mathématiques pures de la caméra (testables sans scène).
## Modèle : Camera2D ancrée au centre ; la position est le point monde affiché
## au centre du viewport, `zoom` est le facteur monde -> écran.


static func clamp_zoom(zoom: float, zoom_min: float, zoom_max: float) -> float:
	return clampf(zoom, zoom_min, zoom_max)


static func clamp_position(position: Vector2, bounds: Rect2) -> Vector2:
	return position.clamp(bounds.position, bounds.end)


static func screen_to_world(screen: Vector2, cam_pos: Vector2, zoom: float, viewport_size: Vector2) -> Vector2:
	return cam_pos + (screen - viewport_size * 0.5) / zoom


## Position de caméra pour que `world_point` s'affiche en `screen_point` au zoom donné.
## Sert au zoom centré sur les doigts et au panoramique (même formule).
static func anchor_position(world_point: Vector2, screen_point: Vector2, zoom: float, viewport_size: Vector2) -> Vector2:
	return world_point - (screen_point - viewport_size * 0.5) / zoom


## Rectangle monde visible (pour ne dessiner que les cases à l'écran).
static func visible_world_rect(cam_pos: Vector2, zoom: float, viewport_size: Vector2) -> Rect2:
	var half: Vector2 = viewport_size / (2.0 * zoom)
	return Rect2(cam_pos - half, half * 2.0)
