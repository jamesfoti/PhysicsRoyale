extends Node
class_name CameraOrbit

const CameraHints = preload("res://camera/camera_hints.gd")

# Godot-editor-style orbit camera for on-foot play.
# Middle mouse drag to orbit, scroll wheel to zoom.

@export var mouse_sensitivity := 0.25
@export var min_pitch := -80.0
@export var max_pitch := 80.0
@export var min_distance := 1.5
@export var max_distance := 24.0
@export var zoom_step := 0.75
@export var default_pitch := 18.0

var yaw := 0.0
var pitch := default_pitch
var _distance := 5.0
var _orbiting := false


func get_orbit_distance() -> float:
	return _distance


func set_orbit_distance(distance: float) -> void:
	_distance = clampf(distance, min_distance, max_distance)


func initialize_from_hints(hints: CameraHints) -> void:
	_distance = clampf(hints.distance_to_target, min_distance, max_distance)
	pitch = default_pitch


func align_yaw_to_forward(up: Vector3, forward: Vector3) -> void:
	var plane := Plane(up.normalized(), 0.0)
	var planar_forward := plane.project(forward)
	if planar_forward.length_squared() < 0.0001:
		return
	planar_forward = planar_forward.normalized()
	var frame := _build_orbit_frame(up)
	yaw = rad_to_deg(atan2(planar_forward.dot(frame.x), -planar_forward.dot(frame.z)))


func get_planar_look_direction(up: Vector3) -> Vector3:
	var frame := _build_orbit_frame(up)
	var yaw_rad := deg_to_rad(yaw)
	var look := frame.z * cos(yaw_rad) + frame.x * sin(yaw_rad)
	if look.length_squared() < 0.0001:
		return -frame.z
	return -look.normalized()


func compute_orbit_transform(
		anchor_transform: Transform3D,
		target_height: float,
		side_offset: float,
		distance: float) -> Transform3D:
	var up := anchor_transform.basis.y.normalized()
	var pivot := anchor_transform.origin + up * target_height + \
		anchor_transform.basis.x * side_offset
	var frame := _build_orbit_frame(up)

	var yaw_rad := deg_to_rad(yaw)
	var pitch_rad := deg_to_rad(pitch)
	var orbit_dir := Vector3(
		cos(pitch_rad) * sin(yaw_rad),
		sin(pitch_rad),
		cos(pitch_rad) * cos(yaw_rad)
	)
	var offset := frame.x * orbit_dir.x + frame.y * orbit_dir.y + frame.z * orbit_dir.z
	var camera_origin := pivot + offset * distance

	var camera_transform := Transform3D()
	camera_transform.origin = camera_origin
	camera_transform = camera_transform.looking_at(pivot, up)
	return camera_transform


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				_orbiting = event.pressed
				if _orbiting:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				else:
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					set_orbit_distance(_distance - zoom_step)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					set_orbit_distance(_distance + zoom_step)

	elif event is InputEventMouseMotion and _orbiting:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clampf(pitch, min_pitch, max_pitch)


static func _build_orbit_frame(up: Vector3) -> Basis:
	var up_vec := up.normalized()
	var tangent := up_vec.cross(Vector3.FORWARD)
	if tangent.length_squared() < 0.0001:
		tangent = up_vec.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(up_vec).normalized()
	return Basis(tangent, up_vec, bitangent)
