extends RigidBody3D

# Planet walking based on GDQuest's "walk around planets" approach:
# https://www.youtube.com/watch?v=_QHvKMRtJD0
# RigidBody3D + _integrate_forces: gravity-aligned basis, contact floor checks.

const StellarBody = preload("res://solar_system/stellar_body.gd")
const Util = preload("res://util/util.gd")

const MOVE_SPEED := 10.0
const GROUND_ACCEL := 35.0
const AIR_MOVE_FORCE := 40.0
const GROUND_FRICTION := 14.0
const JUMP_IMPULSE := 7.0
const UP_ALIGN_SPEED := 10.0
const FLOOR_NORMAL_DOT := 0.45
const MAX_GRAVITY_FORCE := 25.0
const FOOT_SURFACE_CLEARANCE := 0.2
const GROUND_SNAP_RAY_LENGTH := 4.0

signal jumped

@onready var _head: Node3D = $Head

var _motor := Vector3.ZERO
var _planet_up := Vector3.UP
var _landing_body: StellarBody = null
var _jump_cmd := false
var _on_floor := false
var _spawn_settle_frames := 0
var _planet_lock_local_transform := Transform3D.IDENTITY
var _planet_lock_body: StellarBody = null
var _was_idle_on_planet := false
var _last_planet_transform := Transform3D.IDENTITY

var _pending_spawn_global_transform := Transform3D.IDENTITY
var _pending_spawn := false


func configure_spawn(spawn_pos: Vector3, up: Vector3, forward: Vector3, planet: StellarBody = null) -> void:
	_planet_up = up.normalized()
	_landing_body = planet
	_pending_spawn_global_transform = Transform3D(_make_surface_basis(up, forward), spawn_pos)
	_pending_spawn = true


func set_motor(motor: Vector3) -> void:
	_motor = motor


func set_planet_up(up: Vector3) -> void:
	if up.length_squared() > 0.0001:
		_planet_up = up.normalized()


func set_landing_body(body: StellarBody) -> void:
	_landing_body = body


func jump() -> void:
	_jump_cmd = true


func get_head() -> Node3D:
	return _head


func is_on_floor() -> bool:
	return _on_floor


func is_landed() -> bool:
	return _on_floor


func is_spawn_settling() -> bool:
	return _spawn_settle_frames > 0


func _ready() -> void:
	can_sleep = false
	if _pending_spawn:
		global_transform = _pending_spawn_global_transform
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = false
		_spawn_settle_frames = 30
		_pending_spawn = false
	if _landing_body != null and _landing_body.node != null:
		_planet_lock_body = _landing_body
		_planet_lock_local_transform = \
			_landing_body.node.global_transform.affine_inverse() * global_transform


@onready var _controller: Node = $Controller


func _physics_process(_delta: float) -> void:
	if _spawn_settle_frames > 0:
		_spawn_settle_frames -= 1


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _controller != null and _controller.has_method("_read_motor"):
		_motor = _controller.call("_read_motor")

	var gravity_dir := _get_gravity_direction(state)
	if gravity_dir.length_squared() < 0.0001:
		gravity_dir = -_planet_up.normalized()
	var up := -gravity_dir.normalized()
	var plane := Plane(up, 0.0)

	_on_floor = _check_floor(state, up)

	var move_dir := _get_planar_move_direction(state, up)
	var has_motor_input := _motor.length_squared() > 0.001
	var is_idle := _on_floor and not has_motor_input
	var gravity_strength := _get_gravity_force_magnitude(state)

	if _on_floor and _landing_body != null and _landing_body.node != null and is_idle:
		if not _was_idle_on_planet or _planet_lock_body != _landing_body:
			_capture_planet_lock(state, _landing_body)
		_apply_planet_lock(state, _landing_body)
		_was_idle_on_planet = true
		if _jump_cmd:
			_clear_planet_lock()
			state.apply_central_impulse(up * JUMP_IMPULSE)
			_on_floor = false
			emit_signal("jumped")
		_jump_cmd = false
		return

	_was_idle_on_planet = false

	if _on_floor and _landing_body != null and _landing_body.node != null:
		if _last_planet_transform == Transform3D.IDENTITY:
			_last_planet_transform = _landing_body.node.global_transform
		_apply_planet_motion_delta(state, _landing_body)
		_cancel_velocity_into_ground(state, up)

		if has_motor_input:
			var body_basis := state.transform.basis
			var desired_dir := move_dir
			if desired_dir.length_squared() < 0.001:
				desired_dir = plane.project(
					body_basis * Vector3(_motor.x, 0.0, -_motor.z)
				).normalized()
			if desired_dir.length_squared() > 0.001:
				var desired_vel := desired_dir * MOVE_SPEED
				var planar_vel := plane.project(state.linear_velocity)
				state.linear_velocity = state.linear_velocity - planar_vel + \
					planar_vel.lerp(desired_vel, minf(1.0, GROUND_ACCEL * state.step))
				_align_to_surface(state, up, desired_dir)

		state.apply_central_force(up * gravity_strength)
	else:
		if move_dir.length_squared() > 0.001:
			state.apply_central_force(move_dir * AIR_MOVE_FORCE)
		_apply_planet_gravity(state)

	if not _on_floor:
		_clear_planet_lock()

	if _jump_cmd and _on_floor:
		_clear_planet_lock()
		state.apply_central_impulse(up * JUMP_IMPULSE)
		_on_floor = false
		emit_signal("jumped")
	_jump_cmd = false


func _capture_planet_lock(state: PhysicsDirectBodyState3D, body: StellarBody) -> void:
	_planet_lock_body = body
	_planet_lock_local_transform = body.node.global_transform.affine_inverse() * state.transform


func _apply_planet_lock(state: PhysicsDirectBodyState3D, body: StellarBody) -> void:
	state.transform = body.node.global_transform * _planet_lock_local_transform
	state.linear_velocity = Vector3.ZERO
	state.angular_velocity = Vector3.ZERO
	_last_planet_transform = Transform3D.IDENTITY


func _apply_planet_motion_delta(state: PhysicsDirectBodyState3D, body: StellarBody) -> void:
	var planet_tf := body.node.global_transform
	if _last_planet_transform == Transform3D.IDENTITY:
		_last_planet_transform = planet_tf
		return
	var planet_delta := planet_tf * _last_planet_transform.affine_inverse()
	state.transform.origin = planet_delta * state.transform.origin
	state.linear_velocity = planet_delta.basis * state.linear_velocity
	_last_planet_transform = planet_tf


func _clear_planet_lock() -> void:
	_planet_lock_body = null
	_planet_lock_local_transform = Transform3D.IDENTITY
	_was_idle_on_planet = false
	_last_planet_transform = Transform3D.IDENTITY


func _get_planar_move_direction(state: PhysicsDirectBodyState3D, up: Vector3) -> Vector3:
	if _motor.length_squared() < 0.001:
		return Vector3.ZERO
	var plane := Plane(up.normalized(), 0.0)
	var head_trans := _head.global_transform
	var body_basis := state.transform.basis

	var forward := plane.project(-head_trans.basis.z)
	if forward.length_squared() < 0.01:
		forward = plane.project(-body_basis.z)
	forward = forward.normalized()

	var right := plane.project(head_trans.basis.x)
	if right.length_squared() < 0.01:
		right = plane.project(body_basis.x)
	right = right.normalized()

	var move_dir := _motor.x * right + _motor.z * forward
	if move_dir.length_squared() < 0.001:
		move_dir = plane.project(body_basis * Vector3(_motor.x, 0.0, -_motor.z))
	if move_dir.length_squared() < 0.001:
		return Vector3.ZERO
	return move_dir.normalized()


func _get_gravity_direction(state: PhysicsDirectBodyState3D) -> Vector3:
	if _landing_body != null and _landing_body.node != null:
		var pull_center := _landing_body.node.global_transform.origin
		return (pull_center - state.transform.origin).normalized()
	return -_planet_up.normalized()


func _get_gravity_force_magnitude(state: PhysicsDirectBodyState3D) -> float:
	if _landing_body == null or _landing_body.node == null:
		return MAX_GRAVITY_FORCE
	var pull_center := _landing_body.node.global_transform.origin
	var pos := state.transform.origin
	var gd := absf(pull_center.distance_to(pos) - _landing_body.radius) + _landing_body.radius
	var stellar_mass := Util.get_sphere_volume(_landing_body.radius)
	var f := 0.005 * stellar_mass / (gd * gd)
	return minf(f, MAX_GRAVITY_FORCE)


func _apply_planet_gravity(state: PhysicsDirectBodyState3D) -> void:
	var gravity_dir := _get_gravity_direction(state)
	state.apply_central_force(gravity_dir * _get_gravity_force_magnitude(state))


func _cancel_velocity_into_ground(state: PhysicsDirectBodyState3D, up: Vector3) -> void:
	var into_ground := state.linear_velocity.dot(-up)
	if into_ground > 0.0:
		state.linear_velocity += up * into_ground


func _snap_to_surface(state: PhysicsDirectBodyState3D, up: Vector3) -> void:
	var hit := _raycast_to_ground(state.transform.origin, up)
	if hit.is_empty():
		return
	var target_origin: Vector3 = hit.position + hit.normal * FOOT_SURFACE_CLEARANCE
	var correction: Vector3 = up * (target_origin - state.transform.origin).dot(up)
	if correction.dot(up) > -0.1:
		state.transform.origin += correction


func _raycast_to_ground(origin: Vector3, up: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = origin + up * 0.5
	ray_query.to = origin - up * GROUND_SNAP_RAY_LENGTH
	ray_query.exclude = [get_rid()]
	return space_state.intersect_ray(ray_query)


func _align_to_surface(state: PhysicsDirectBodyState3D, up: Vector3, move_dir: Vector3) -> void:
	if _spawn_settle_frames > 0:
		return
	var plane := Plane(up, 0.0)
	var forward := move_dir
	if forward.length_squared() < 0.001:
		forward = plane.project(-_head.global_transform.basis.z)
	if forward.length_squared() < 0.001:
		forward = plane.project(-state.transform.basis.z)
	var target_basis := _make_surface_basis(up, forward)
	var current_quat := state.transform.basis.get_rotation_quaternion()
	var target_quat := target_basis.get_rotation_quaternion()
	var new_quat := current_quat.slerp(target_quat, UP_ALIGN_SPEED * state.step)
	state.transform.basis = Basis(new_quat)


static func _make_surface_basis(surface_up: Vector3, forward_hint: Vector3) -> Basis:
	var up := surface_up.normalized()
	var forward := forward_hint - up * up.dot(forward_hint)
	if forward.length_squared() < 0.0001:
		forward = up.cross(Vector3.UP)
		if forward.length_squared() < 0.0001:
			forward = up.cross(Vector3.RIGHT)
	forward = forward.normalized()
	var right := forward.cross(up).normalized()
	forward = up.cross(right).normalized()
	return Basis(right, up, -forward)


func _check_floor(state: PhysicsDirectBodyState3D, up: Vector3) -> bool:
	for i in state.get_contact_count():
		var local_normal := state.get_contact_local_normal(i)
		var world_normal := (state.transform.basis * local_normal).normalized()
		if world_normal.dot(up) > FLOOR_NORMAL_DOT:
			return true
	var hit := _raycast_to_ground(state.transform.origin, up)
	if hit.is_empty():
		return false
	return hit.normal.dot(up) > FLOOR_NORMAL_DOT and \
		(hit.position - state.transform.origin).dot(up) < FOOT_SURFACE_CLEARANCE + 0.35
