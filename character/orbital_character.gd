extends CharacterBody3D

# Orbital / faux-gravity movement inspired by ForlornU's Unity tutorial:
# https://www.youtube.com/watch?v=gpjqd0OPrJc
# Gravity toward the planet, rotate to the surface, idle gravity while grounded, raycast ground data.

const StellarBody = preload("res://solar_system/stellar_body.gd")

@export var move_acceleration := 75.0
@export var move_damp_factor := 0.2
@export var move_speed_cap := 12.0
@export var gravity_strength := 25.0
@export var idle_gravity := 8.0
@export_range(0.0, 1.0, 0.01) var surface_rotation_blend := 0.6
@export var align_speed := 10.0
@export var ground_check_distance := 1.5
@export var jump_speed := 10.0
@export var jump_cooldown_time := 0.3

signal jumped

@onready var _head: Node3D = $Head

var _velocity := Vector3.ZERO
var _motor := Vector3.ZERO
var _move_right := Vector3.RIGHT
var _move_back := Vector3.BACK
var _planet_up := Vector3.UP
var _landing_body: StellarBody = null
var _jump_cooldown := 0.0
var _jump_cmd := 0
var _spawn_settle_frames := 0

var _pending_spawn := false
var _pending_spawn_transform := Transform3D.IDENTITY


func configure_spawn(spawn_pos: Vector3, up: Vector3, forward: Vector3, planet: StellarBody = null) -> void:
	_planet_up = up.normalized()
	_landing_body = planet
	_pending_spawn_transform = Transform3D(_basis_from_up_forward(up, forward), spawn_pos)
	_pending_spawn = true


func set_motor(motor: Vector3) -> void:
	_motor = motor


func set_move_basis(right: Vector3, back: Vector3) -> void:
	if right.length_squared() > 0.0001:
		_move_right = right.normalized()
	if back.length_squared() > 0.0001:
		_move_back = back.normalized()


func set_planet_up(up: Vector3) -> void:
	if up.length_squared() > 0.0001:
		_planet_up = up.normalized()


func set_landing_body(body: StellarBody) -> void:
	_landing_body = body


func jump() -> void:
	_jump_cmd = 5


func get_head() -> Node3D:
	return _head


func is_spawn_settling() -> bool:
	return _spawn_settle_frames > 0


func _ready() -> void:
	if _pending_spawn:
		global_transform = _pending_spawn_transform
		_velocity = Vector3.ZERO
		_spawn_settle_frames = 30
		_pending_spawn = false


func _physics_process(delta: float) -> void:
	if _spawn_settle_frames > 0:
		_spawn_settle_frames -= 1

	_update_planet_up()
	var gravity_up := _planet_up.normalized()
	var ground := _query_ground(gravity_up)
	var up := gravity_up
	if ground.grounded:
		up = gravity_up.lerp(ground.normal, surface_rotation_blend).normalized()
	if up.length_squared() < 0.0001:
		up = gravity_up

	_align_body_to_up(up, delta)

	var plane := Plane(up, 0.0)
	var motor := _motor.z * _move_back + _motor.x * _move_right
	_motor = Vector3.ZERO

	_velocity += motor * move_acceleration * delta
	_velocity = _clamp_planar_speed(_velocity, plane, move_speed_cap)
	var planar_velocity := plane.project(_velocity)
	_velocity -= planar_velocity * move_damp_factor

	var grounded: bool = ground.grounded or is_on_floor()

	if grounded:
		if idle_gravity > 0.0:
			_velocity -= up * idle_gravity * delta
		if _velocity.length_squared() < 0.001:
			_velocity = Vector3.ZERO
		elif is_on_floor() and not ground.grounded:
			_velocity -= up * 0.01
	else:
		_velocity -= up * gravity_strength * delta

	if _velocity != Vector3.ZERO:
		up_direction = up
		velocity = _velocity
		move_and_slide()
		_velocity = velocity

	if _jump_cooldown > 0.0:
		_jump_cooldown -= delta
	elif _jump_cmd > 0:
		if is_on_floor():
			_velocity += up * jump_speed
			_jump_cooldown = jump_cooldown_time
			_jump_cmd = 0
			jumped.emit()
	_jump_cmd = maxi(_jump_cmd - 1, 0)


func _update_planet_up() -> void:
	if _landing_body != null and _landing_body.node != null:
		var to_core := _landing_body.node.global_transform.origin - global_position
		if to_core.length_squared() > 0.0001:
			_planet_up = -to_core.normalized()


func _query_ground(up: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = global_position + up * 0.2
	ray_query.to = global_position - up * ground_check_distance
	ray_query.exclude = [get_rid()]
	var hit := space_state.intersect_ray(ray_query)
	if hit.is_empty():
		return {"grounded": false, "normal": up, "hit": {}}
	return {"grounded": true, "normal": hit.normal, "hit": hit}


func _align_body_to_up(up: Vector3, delta: float) -> void:
	var gtrans := global_transform
	var current_up := gtrans.basis.y
	if current_up.dot(up) < 0.999:
		var correction_axis := up.cross(current_up).normalized()
		if correction_axis.length_squared() > 0.0001:
			var correction_rot := Basis(
				correction_axis, -current_up.angle_to(up) * align_speed * delta)
			gtrans.basis = correction_rot * gtrans.basis
			gtrans.origin += up * 0.01
			global_transform = gtrans


func _clamp_planar_speed(vel: Vector3, plane: Plane, cap: float) -> Vector3:
	var planar := plane.project(vel)
	if planar.length() > cap:
		return vel - planar + planar.normalized() * cap
	return vel


static func _basis_from_up_forward(up: Vector3, forward_hint: Vector3) -> Basis:
	var up_vec := up.normalized()
	var forward := forward_hint - up_vec * up_vec.dot(forward_hint)
	if forward.length_squared() < 0.0001:
		forward = up_vec.cross(Vector3.UP)
		if forward.length_squared() < 0.0001:
			forward = up_vec.cross(Vector3.RIGHT)
	forward = forward.normalized()
	var right := forward.cross(up_vec).normalized()
	forward = up_vec.cross(right).normalized()
	return Basis(right, up_vec, -forward)
