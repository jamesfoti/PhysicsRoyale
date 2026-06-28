extends SpringArm3D
class_name OrbitCamera
## Camera pitch while playing; hold middle mouse to orbit around the player.


@export_range(-90.0, 90.0, 0.1, "radians") var min_limit_x: float = -1.4
@export_range(-90.0, 90.0, 0.1, "radians") var max_limit_x: float = 0.2
@export var mouse_sensitivity: float = 0.0025
@export var recenter_speed: float = 10.0

var _orbiting: bool = false


func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if _is_terrain_focus_active():
		return
	if event.is_action_pressed("ui_cancel"):
		if _is_terrain_edit_active():
			return
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed:
		if get_viewport().gui_get_hovered_control() != null:
			return
		if _is_terrain_edit_active():
			return
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _input(event: InputEvent) -> void:
	if _is_terrain_focus_active():
		return
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_MIDDLE:
			_orbiting = button.pressed

	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		if _orbiting:
			rotation.y -= motion.relative.x * mouse_sensitivity
		rotation.x = clampf(
			rotation.x - motion.relative.y * mouse_sensitivity,
			min_limit_x,
			max_limit_x
		)


func is_orbiting() -> bool:
	return _orbiting


func recenter_yaw(delta: float) -> void:
	rotation.y = lerpf(rotation.y, 0.0, minf(1.0, recenter_speed * delta))


func _is_terrain_edit_active() -> bool:
	var brush: TerrainBrush = get_tree().get_first_node_in_group("terrain_brush") as TerrainBrush
	return brush != null and brush.get_edit_mode() != TerrainBrush.EditMode.OFF


func _is_terrain_focus_active() -> bool:
	var player: PlanetPlayer = get_parent() as PlanetPlayer
	return player != null and player.is_terrain_focus_active()
