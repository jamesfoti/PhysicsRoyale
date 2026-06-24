extends RigidBody3D

# Planet walking based on Pigeonaut's RigidBody approach:
# https://www.youtube.com/watch?v=aL8TB_mB3j8

const Ship = preload("../ship/ship.gd")
const Util = preload("../util/util.gd")
const CollisionLayers = preload("../collision_layers.gd")
const StellarBody = preload("../solar_system/stellar_body.gd")
const SplitChunkRigidBodyComponent = preload("../solar_system/split_chunk_rigidbody_component.gd")
const CharacterAudio = preload("./character_audio.gd")
const Waypoint = preload("res://waypoints/waypoint.gd")
const TerrainEditCursor = preload("res://character/terrain_edit_cursor.gd")
const CameraOrbit = preload("res://character/camera_orbit.gd")

const WaypointScene = preload("../waypoints/waypoint.tscn")

@export var move_force := 30.0
@export var jump_impulse := 20.0
@export var max_gravity_force := 25.0
@export var floor_normal_dot := 0.45
@export var ground_height_offset := 0.15
@export var ground_snap_ray_length := 4.0
@export var undig_check_interval := 15
@export var up_align_speed := 12.0

const FLOOR_GRACE_FRAMES := 5
const JUMP_BUFFER_FRAMES := 10
const JUMP_AIR_FRAMES := 12

signal jumped

@onready var _head: Node3D = $Head
@onready var _visual_root: Node3D = $Visual
@onready var _visual_head: Node3D = $Visual/Head
@onready var _flashlight: SpotLight3D = $Visual/FlashLight
@onready var _audio: CharacterAudio = $Audio
@onready var _terrain_cursor: TerrainEditCursor = $TerrainEditCursor

var _motor := Vector3.ZERO
var _move_right := Vector3.RIGHT
var _move_forward := Vector3.FORWARD
var _planet_up := Vector3.UP
var _gravity_direction := Vector3.DOWN
var _landing_body: StellarBody = null
var _jump_buffer := 0
var _jump_air_frames := 0
var _floor_grace := 0
var _on_floor := false
var _spawn_settle_frames := 0
var _dig_cmd := false
var _interact_cmd := false
var _build_cmd := false
var _waypoint_cmd := false

var _planet_lock_local_transform := Transform3D.IDENTITY
var _planet_lock_body: StellarBody = null
var _was_idle_on_planet := false
var _last_planet_transform := Transform3D.IDENTITY

var _pending_spawn := false
var _pending_spawn_transform := Transform3D.IDENTITY
var _undig_check_counter := 0
var _terrain_hover_hit := {}


func configure_spawn(spawn_pos: Vector3, up: Vector3, forward: Vector3, planet: StellarBody = null) -> void:
	_planet_up = up.normalized()
	_landing_body = planet
	_pending_spawn_transform = Transform3D(_make_surface_basis(up, forward), spawn_pos)
	_pending_spawn = true
	var orbit := get_node_or_null("CameraOrbit") as CameraOrbit
	if orbit != null:
		orbit.align_yaw_to_forward(up, forward)


func is_spawn_settling() -> bool:
	return _spawn_settle_frames > 0


func is_on_floor() -> bool:
	return _on_floor


func is_landed() -> bool:
	return _on_floor


func set_gravity_planet(planet: StellarBody) -> void:
	_landing_body = planet


func clear_gravity_planet(planet: StellarBody) -> void:
	if _landing_body == planet:
		_landing_body = null


func _ready() -> void:
	can_sleep = false
	gravity_scale = 0.0
	if _pending_spawn:
		global_transform = _pending_spawn_transform
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		sleeping = false
		_spawn_settle_frames = 30
		_pending_spawn = false
	if _landing_body != null and _landing_body.node != null:
		_planet_lock_body = _landing_body
		_planet_lock_local_transform = \
			_landing_body.node.global_transform.affine_inverse() * global_transform


func _physics_process(_delta: float) -> void:
	if _spawn_settle_frames > 0:
		_spawn_settle_frames -= 1

	_read_motor_input()
	_update_landing_body()
	_process_action_commands()
	_process_undig()


func _process(_delta: float) -> void:
	_update_terrain_hover()
	_process_visuals(_delta)


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_update_gravity_direction(state)

	var planet_up := (-_gravity_direction).normalized()
	if planet_up.length_squared() < 0.0001:
		planet_up = _planet_up

	if _jump_air_frames > 0:
		_jump_air_frames -= 1

	var has_contact := _has_floor_contact(state, planet_up)
	if has_contact:
		_floor_grace = FLOOR_GRACE_FRAMES
	elif _floor_grace > 0:
		_floor_grace -= 1

	var near_ground := false
	if _jump_air_frames == 0:
		near_ground = _is_near_ground(state, planet_up)

	_on_floor = _jump_air_frames == 0 and (has_contact or _floor_grace > 0 or near_ground)
	var has_motor_input := _motor.length_squared() > 0.001

	if _landing_body != null and not has_contact:
		_align_to_planet_up(state, planet_up, state.step)

	var up := state.transform.basis.y.normalized()
	if up.length_squared() < 0.0001:
		up = planet_up

	if _jump_buffer > 0 and _on_floor:
		_clear_planet_lock()
		state.apply_central_impulse(up * jump_impulse)
		_jump_buffer = 0
		_jump_air_frames = JUMP_AIR_FRAMES
		_floor_grace = 0
		_on_floor = false
		jumped.emit()
	elif _jump_buffer > 0:
		_jump_buffer -= 1

	var is_idle := _on_floor and not has_motor_input

	if is_idle and _landing_body != null and _landing_body.node != null:
		if not _was_idle_on_planet or _planet_lock_body != _landing_body:
			_capture_planet_lock(state, _landing_body)
		_apply_planet_lock(state, _landing_body)
		_was_idle_on_planet = true
		return

	_was_idle_on_planet = false

	if _on_floor and _landing_body != null and _landing_body.node != null:
		if _last_planet_transform == Transform3D.IDENTITY:
			_last_planet_transform = _landing_body.node.global_transform
		_apply_planet_motion_delta(state, _landing_body)
		_flatten_velocity_to_ground(state, planet_up)
		_maintain_ground_height(state, planet_up)

	if has_motor_input:
		var move_dir := _get_planar_move_direction(state, planet_up)
		var force_dir := move_dir
		if force_dir.length_squared() < 0.001:
			force_dir = (
				state.transform.basis.x * _motor.x
				+ state.transform.basis.z * _motor.z
			)
		if force_dir.length_squared() > 0.001:
			state.apply_central_force(force_dir.normalized() * move_force)

	if not _on_floor and _landing_body != null:
		_apply_planet_gravity(state)

	if not _on_floor:
		_clear_planet_lock()


func _process_visuals(delta: float) -> void:
	var up := _planet_up
	if up.length_squared() < 0.0001:
		up = global_transform.basis.y
	_sync_head_to_camera(up)
	_visual_root.position = Vector3.ZERO

	# Yaw the visual mesh in local space only — the RigidBody basis already
	# handles planet alignment; a global look_at on the child was flipping the model.
	var head_forward := get_flat_forward_not_normalized(_head.global_transform.basis, up)
	if head_forward.length_squared() > 0.001:
		var local_forward := global_transform.basis.transposed() * head_forward.normalized()
		local_forward.y = 0.0
		if local_forward.length_squared() > 0.001:
			local_forward = local_forward.normalized()
			var target_yaw_basis := Basis.looking_at(local_forward, Vector3.UP)
			_visual_root.transform.basis = \
				_visual_root.transform.basis.slerp(target_yaw_basis, delta * 8.0)

	_visual_head.global_transform.basis = _head.global_transform.basis


func _read_motor_input() -> void:
	_motor = Vector3()
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z):
		_motor += Vector3(0, 0, 1)
	if Input.is_key_pressed(KEY_S):
		_motor += Vector3(0, 0, -1)
	if Input.is_key_pressed(KEY_A):
		_motor += Vector3(-1, 0, 0)
	if Input.is_key_pressed(KEY_D):
		_motor += Vector3(1, 0, 0)

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var move_plane := Plane(_planet_up, 0.0)
		_move_forward = move_plane.project(-camera.global_transform.basis.z).normalized()
		_move_right = move_plane.project(camera.global_transform.basis.x).normalized()


func _update_landing_body() -> void:
	if _landing_body != null and _landing_body.node != null:
		var to_core := _landing_body.node.global_transform.origin - global_position
		if to_core.length_squared() > 0.0001:
			_planet_up = -to_core.normalized()
		return

	if _gravity_direction.length_squared() > 0.0001:
		_planet_up = -_gravity_direction.normalized()
	else:
		_planet_up = Vector3.UP

func _get_planar_move_direction(state: PhysicsDirectBodyState3D, up: Vector3) -> Vector3:
	if _motor.length_squared() < 0.001:
		return Vector3.ZERO
	var plane := Plane(up.normalized(), 0.0)

	var forward := plane.project(_move_forward)
	if forward.length_squared() < 0.01:
		forward = plane.project(-_head.global_transform.basis.z)
	forward = forward.normalized()

	var right := plane.project(_move_right)
	if right.length_squared() < 0.01:
		right = plane.project(state.transform.basis.x)
	right = right.normalized()

	var move_dir := _motor.x * right + _motor.z * forward
	if move_dir.length_squared() < 0.001:
		move_dir = plane.project(state.transform.basis * Vector3(_motor.x, 0.0, -_motor.z))
	if move_dir.length_squared() < 0.001:
		return Vector3.ZERO
	return move_dir.normalized()


func _process_undig() -> void:
	if is_spawn_settling():
		return
	_undig_check_counter += 1
	if _undig_check_counter < undig_check_interval:
		return
	_undig_check_counter = 0
	var solar_system := _get_solar_system()
	if solar_system == null:
		return
	var landing_body := _get_landing_body()
	if landing_body == null or landing_body.volume == null:
		return
	var volume := landing_body.volume
	var vt: VoxelToolLodTerrain = volume.get_voxel_tool()
	var volume_to_local := volume.global_transform.affine_inverse()
	var local_pos := volume_to_local * global_transform.origin
	vt.channel = VoxelBuffer.CHANNEL_SDF
	var sdf := vt.get_voxel_f_interpolated(local_pos)
	if sdf < -0.001:
		print("Character is buried, teleporting back to air")
		var bury_up := local_pos.normalized()
		var offset_local_pos := local_pos
		for i in 10:
			print("Undig attempt ", i)
			offset_local_pos += 0.2 * bury_up
			sdf = vt.get_voxel_f_interpolated(offset_local_pos)
			if sdf > 0.0005:
				break
		var gtrans := global_transform
		gtrans.origin = volume.get_global_transform() * offset_local_pos
		global_transform = gtrans
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO


func _update_terrain_hover() -> void:
	_terrain_hover_hit = _raycast_terrain_from_mouse()


func _process_action_commands() -> void:
	if _interact_cmd:
		_interact_cmd = false
		_interact()

	var hit := _terrain_hover_hit
	var build_mode := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	if hit.is_empty() or not hit.collider is VoxelLodTerrain:
		_terrain_cursor.hide_cursor()
		return

	_terrain_cursor.show_at(hit.position, hit.normal, build_mode)

	var volume: VoxelLodTerrain = hit.collider
	var hit_position: Vector3 = hit.position

	if _dig_cmd:
		_dig_cmd = false
		var vt: VoxelToolLodTerrain = volume.get_voxel_tool()
		var pos := volume.get_global_transform().affine_inverse() * hit_position
		var sphere_size := 3.5
		vt.channel = VoxelBuffer.CHANNEL_SDF
		vt.mode = VoxelTool.MODE_REMOVE
		vt.do_sphere(pos, sphere_size)
		_audio.play_dig(pos)

		var camera := get_viewport().get_camera_3d()
		var splitter_aabb := AABB(pos, Vector3()).grow(16.0)
		var bodies := vt.separate_floating_chunks(splitter_aabb, camera.get_parent())
		print("Created ", len(bodies), " bodies")
		for body in bodies:
			var cmp := SplitChunkRigidBodyComponent.new()
			body.add_child(cmp)
		DDD.draw_box_aabb(splitter_aabb, Color(0, 1, 0), 60)

	if _build_cmd:
		_build_cmd = false
		var vt: VoxelTool = volume.get_voxel_tool()
		var pos := volume.get_global_transform().affine_inverse() * hit_position
		vt.channel = VoxelBuffer.CHANNEL_SDF
		vt.mode = VoxelTool.MODE_ADD
		vt.do_sphere(pos, 3.5)
		_audio.play_dig(pos)

	if _waypoint_cmd:
		_waypoint_cmd = false
		var planet := _get_landing_body()
		if planet == null:
			return
		var waypoint: Waypoint = WaypointScene.instantiate()
		waypoint.transform = Transform3D(global_transform.basis, hit_position)
		planet.node.add_child(waypoint)
		planet.waypoints.append(waypoint)
		_audio.play_waypoint()


func _raycast_terrain_from_mouse() -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return {}
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_direction := camera.project_ray_normal(mouse_pos)
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = ray_origin
	ray_query.to = ray_origin + ray_direction * 100.0
	ray_query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(ray_query)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			match event.keycode:
				KEY_SPACE:
					_jump_buffer = JUMP_BUFFER_FRAMES
				KEY_E:
					_interact_cmd = true
				KEY_F:
					_flashlight.visible = not _flashlight.visible
					if _flashlight.visible:
						_audio.play_light_on()
					else:
						_audio.play_light_off()
				KEY_T:
					_waypoint_cmd = true

	elif event is InputEventMouseButton:
		if event.pressed:
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_dig_cmd = true
				MOUSE_BUTTON_RIGHT:
					_build_cmd = true


func _interact() -> void:
	var space_state := get_world_3d().direct_space_state
	var camera := get_viewport().get_camera_3d()
	var front := -camera.global_transform.basis.z
	var pos := camera.global_transform.origin

	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = pos
	ray_query.to = pos + front * 10.0
	ray_query.collision_mask = CollisionLayers.DEFAULT
	ray_query.collide_with_bodies = false
	ray_query.collide_with_areas = true
	var hit := space_state.intersect_ray(ray_query)

	if not hit.is_empty():
		if hit.collider.name == "CommandPanel":
			var ship: Ship = Util.find_parent_by_type(hit.collider, Ship)
			if ship != null:
				_enter_ship(ship)


func _enter_ship(ship: Ship) -> void:
	var solar_system := _get_solar_system()
	if solar_system != null:
		solar_system.set_character_control_mode(false)
	var camera = get_viewport().get_camera_3d()
	camera.set_target(ship)
	ship.enable_controller()
	queue_free()


func _update_gravity_direction(state: PhysicsDirectBodyState3D) -> void:
	if _landing_body != null and _landing_body.node != null:
		_gravity_direction = (
			_landing_body.node.global_transform.origin - state.transform.origin
		).normalized()
	elif state.total_gravity.length_squared() > 0.0001:
		_gravity_direction = state.total_gravity.normalized()
	else:
		_gravity_direction = Vector3.DOWN


func _align_to_planet_up(
		state: PhysicsDirectBodyState3D, target_up: Vector3, step: float) -> void:
	target_up = target_up.normalized()
	var current_up := state.transform.basis.y.normalized()
	if current_up.dot(target_up) > 0.999:
		return
	var forward := -state.transform.basis.z
	forward = forward - target_up * forward.dot(target_up)
	if forward.length_squared() < 0.001:
		forward = state.transform.basis.x - target_up * state.transform.basis.x.dot(target_up)
	if forward.length_squared() < 0.001:
		forward = target_up.cross(Vector3.FORWARD)
		if forward.length_squared() < 0.001:
			forward = target_up.cross(Vector3.RIGHT)
	forward = forward.normalized()
	var right := forward.cross(target_up).normalized()
	forward = target_up.cross(right).normalized()
	var target_basis := Basis(right, target_up, -forward)
	var current_quat := state.transform.basis.get_rotation_quaternion()
	var target_quat := target_basis.get_rotation_quaternion()
	state.transform.basis = Basis(current_quat.slerp(target_quat, up_align_speed * step))


func _flatten_velocity_to_ground(state: PhysicsDirectBodyState3D, ground_up: Vector3) -> void:
	var n := ground_up.normalized()
	var velocity := state.linear_velocity
	state.linear_velocity = velocity - n * velocity.dot(n)


func _maintain_ground_height(state: PhysicsDirectBodyState3D, up_hint: Vector3) -> void:
	var hit := _raycast_to_ground(state.transform.origin, up_hint)
	if hit.is_empty():
		return
	var n: Vector3 = hit.normal.normalized()
	var height: float = (state.transform.origin - hit.position).dot(n)
	if height < ground_height_offset:
		state.transform.origin += n * (ground_height_offset - height)
		var into_ground := state.linear_velocity.dot(n)
		if into_ground < 0.0:
			state.linear_velocity -= n * into_ground


func _has_floor_contact(state: PhysicsDirectBodyState3D, up: Vector3) -> bool:
	for i in state.get_contact_count():
		var local_normal := state.get_contact_local_normal(i)
		var world_normal := (state.transform.basis * local_normal).normalized()
		if world_normal.dot(up) > floor_normal_dot:
			return true
	return false


func _is_near_ground(state: PhysicsDirectBodyState3D, up: Vector3) -> bool:
	var hit := _raycast_to_ground(state.transform.origin, up)
	if hit.is_empty():
		return false
	var surface_up: Vector3 = hit.normal.normalized()
	var height_above: float = (state.transform.origin - hit.position).dot(surface_up)
	return surface_up.dot(up) > floor_normal_dot and \
		height_above < ground_height_offset + 0.1


func _apply_planet_gravity(state: PhysicsDirectBodyState3D) -> void:
	var gravity_dir := _gravity_direction
	if gravity_dir.length_squared() < 0.0001:
		return
	state.apply_central_force(gravity_dir * _get_gravity_force_magnitude(state))


func _get_gravity_force_magnitude(state: PhysicsDirectBodyState3D) -> float:
	if _landing_body == null or _landing_body.node == null:
		return max_gravity_force
	var pull_center := _landing_body.node.global_transform.origin
	var pos := state.transform.origin
	var gd := absf(pull_center.distance_to(pos) - _landing_body.radius) + _landing_body.radius
	var stellar_mass := Util.get_sphere_volume(_landing_body.radius)
	var f := 0.005 * stellar_mass / (gd * gd)
	return minf(f, max_gravity_force)


func _raycast_to_ground(origin: Vector3, up: Vector3) -> Dictionary:
	var space_state := get_world_3d().direct_space_state
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = origin + up * 0.5
	ray_query.to = origin - up * ground_snap_ray_length
	ray_query.exclude = [get_rid()]
	return space_state.intersect_ray(ray_query)


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


func _sync_head_to_camera(up: Vector3) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var plane := Plane(up, 0.0)
	var look_dir := plane.project(-camera.global_transform.basis.z)
	if look_dir.length_squared() < 0.0001:
		return
	look_dir = look_dir.normalized()
	var head_pos := _head.global_position
	_head.global_transform = Transform3D(Basis.looking_at(look_dir, up), head_pos)


func _get_solar_system() -> SolarSystem:
	var node: Node = get_parent()
	while node != null:
		if node is SolarSystem:
			return node as SolarSystem
		node = node.get_parent()
	return null


func _get_landing_body() -> StellarBody:
	var solar_system := _get_solar_system()
	if solar_system == null:
		return null
	var ref_body := solar_system.get_reference_stellar_body()
	if ref_body.type == StellarBody.TYPE_ROCKY and ref_body.volume != null:
		return ref_body
	var closest: StellarBody = null
	var closest_d := INF
	for i in solar_system.get_stellar_body_count():
		var b: StellarBody = solar_system.get_stellar_body(i)
		if b.type != StellarBody.TYPE_ROCKY or b.volume == null:
			continue
		var d := b.node.global_transform.origin.distance_to(global_position)
		if d < b.radius * 4.0 and d < closest_d:
			closest = b
			closest_d = d
	return closest


static func get_flat_forward_not_normalized(head_basis: Basis, ground_up: Vector3) -> Vector3:
	var plane := Plane(ground_up, 0)
	var forward_projected := plane.project(-head_basis.z)
	if forward_projected.length_squared() < 0.01:
		if head_basis.z.dot(ground_up) > 0:
			forward_projected = plane.project(head_basis.y)
		else:
			forward_projected = plane.project(-head_basis.y)
	return forward_projected


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
