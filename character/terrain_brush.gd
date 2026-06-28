extends Node
class_name TerrainBrush
## Raycasts terrain from screen center and applies edits while left mouse is held.


enum EditMode {
	OFF,
	DESTROY,
	ADD,
}

@export var edit_distance: float = 20.0
@export var brush_radius: float = 1.5
## Seconds between brush stamps while holding LMB.
@export var stroke_interval: float = 0.05

@onready var _cursor: TerrainEditCursor = $TerrainEditCursor

var _terrain: TerrainWorldV2
var _mode: EditMode = EditMode.OFF
var _hover_hit: Dictionary = {}
var _is_painting: bool = false
var _stroke_cooldown: float = 0.0


func _ready() -> void:
	add_to_group("terrain_brush")
	_cursor.edit_radius = brush_radius
	call_deferred("_cache_terrain")


func set_edit_mode(mode: EditMode) -> void:
	if mode == EditMode.OFF and _is_painting and _terrain != null:
		_is_painting = false
		_terrain.end_continuous_edit()
	_mode = mode
	if _mode == EditMode.OFF:
		_cursor.hide_cursor()


func get_edit_mode() -> EditMode:
	return _mode


func _process(delta: float) -> void:
	if get_tree().paused or _mode == EditMode.OFF:
		_cursor.hide_cursor()
		_hover_hit = {}
		_stroke_cooldown = 0.0
		return

	var player: Node = get_parent()
	if player == null:
		return
	if _is_terrain_focus_active(player):
		_hover_hit = _raycast_terrain_from_view(player)
		if _hover_hit.is_empty():
			_cursor.hide_cursor()
			if _is_painting and _terrain != null:
				_is_painting = false
				_terrain.end_continuous_edit()
			return
		_cursor.show_at(
			_hover_hit.position,
			_hover_hit.normal,
			_mode == EditMode.ADD
		)
		_process_paint_input(delta)
		return
	if _is_camera_orbiting(player):
		if _is_painting and _terrain != null:
			_is_painting = false
			_terrain.end_continuous_edit()
		_cursor.hide_cursor()
		_hover_hit = {}
		return

	_hover_hit = _raycast_terrain_from_view(player)
	if _hover_hit.is_empty():
		_cursor.hide_cursor()
		return

	_cursor.show_at(
		_hover_hit.position,
		_hover_hit.normal,
		_mode == EditMode.ADD
	)

	_process_paint_input(delta)


func _process_paint_input(delta: float) -> void:
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _is_painting:
			_is_painting = false
			_stroke_cooldown = 0.0
			if _terrain != null:
				_terrain.end_continuous_edit()
		return

	var wants_paint: bool = _can_apply_edit()
	if wants_paint and not _is_painting:
		_is_painting = true
		_stroke_cooldown = 0.0
		if _terrain != null:
			_terrain.begin_continuous_edit()
		_apply_brush()
		_stroke_cooldown = stroke_interval
		return
	elif not wants_paint:
		if _is_painting:
			_is_painting = false
			_stroke_cooldown = 0.0
			if _terrain != null:
				_terrain.end_continuous_edit()
		return

	_stroke_cooldown -= delta
	if _stroke_cooldown > 0.0:
		return
	_apply_brush()
	_stroke_cooldown = stroke_interval


func _can_apply_edit() -> bool:
	if get_viewport().gui_get_hovered_control() != null:
		return false
	if _hover_hit.is_empty():
		return false
	return _terrain != null


func _apply_brush() -> void:
	var hit_position: Vector3 = _hover_hit.position
	_terrain.apply_brush(hit_position, brush_radius, _mode == EditMode.ADD)


func _cache_terrain() -> void:
	var parent: Node = get_parent()
	if parent is PlanetPlayer:
		var planet: Node3D = (parent as PlanetPlayer).planet
		if planet is TerrainWorldV2:
			_terrain = planet as TerrainWorldV2
			return
	_terrain = get_tree().get_first_node_in_group("planet") as TerrainWorldV2


func _raycast_terrain_from_view(player: Node) -> Dictionary:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return {}

	var screen_pos: Vector2 = get_viewport().get_visible_rect().size * 0.5
	if _is_terrain_focus_active(player):
		screen_pos = get_viewport().get_mouse_position()
	var ray_origin: Vector3 = camera.project_ray_origin(screen_pos)
	var ray_direction: Vector3 = camera.project_ray_normal(screen_pos)
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = ray_origin
	ray_query.to = ray_origin + ray_direction * maxf(edit_distance * 2.0, 50.0)
	if player is CollisionObject3D:
		ray_query.exclude = [(player as CollisionObject3D).get_rid()]

	var space: PhysicsDirectSpaceState3D = (get_parent() as Node3D).get_world_3d().direct_space_state
	var hit: Dictionary = space.intersect_ray(ray_query)
	if hit.is_empty():
		return {}
	if player is Node3D and (player as Node3D).global_position.distance_to(hit.position) > edit_distance:
		return {}
	return hit


func _is_camera_orbiting(player: Node) -> bool:
	var orbit_camera: OrbitCamera = player.get_node_or_null("OrbitCamera") as OrbitCamera
	if orbit_camera != null:
		return orbit_camera.is_orbiting()
	return false


func _is_terrain_focus_active(player: Node) -> bool:
	if player is PlanetPlayer:
		return (player as PlanetPlayer).is_terrain_focus_active()
	return false
