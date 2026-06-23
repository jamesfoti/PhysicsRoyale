extends RigidBody3D
class_name Ship

const StellarBody = preload("../solar_system/stellar_body.gd")
const Util = preload("../util/util.gd")
const SolarSystemSetup = preload("../solar_system/solar_system_setup.gd")
const Settings = preload("res://settings.gd")
const ShipController = preload("./ship_controller.gd")
const ShipAudio = preload("./ship_audio.gd")
const JetVFX = preload("./jet_vfx.gd")
const ReferenceChangeInfo = preload("res://solar_system/reference_change_info.gd")

const STATE_LANDED = 0
const STATE_FLYING = 1
const BRAKE_GROUND_LOCK_CLEARANCE := 4.0

@export var linear_acceleration := 10.0
@export var angular_acceleration := 1000.0
@export var speed_cap_on_planet := 40.0
@export var speed_cap_in_space := 400.0
@export var brake_landing_trigger_distance := 300.0
@export_range(0.05, 0.95, 0.01) var brake_landing_smoothness := 0.2
@export_range(1.0, 50.0, 0.5) var brake_ground_lock_snap_distance := 12.0

@onready var _visual_root : Node3D = $Visual/VisualRoot
@onready var _controller : ShipController = $Controller
# Nodes that should be enabled only when landed
@onready var _landed_nodes : Array[Node] = [
	# TODO Godot4 now imports some nodes with unpredictable names if they collide instead of
	# incrementing.
	# The model has Interior and Interior-colonly but then the second was supposed to be named
	# Interior2, now instead it is some random name with an @ which means it may not be relied on...
	#$Visual/VisualRoot/ship/Interior2,
	$Visual/VisualRoot/ship/HatchDown/KinematicBody,
	$CommandPanel
]
var _landed_node_parents : Array[Node] = []
@onready var _flight_collision_shapes : Array[CollisionShape3D] = [
	$FlightCollisionShape,
	#$FlightCollisionShape2,
	#$FlightCollisionShape3
]
@onready var _animation_player : AnimationPlayer = $AnimationPlayer
@onready var _main_jets : Array[JetVFX] = [
	$Visual/VisualRoot/JetVFXMainLeft,
	$Visual/VisualRoot/JetVFXMainRight,
]
@onready var _left_roll_jets : Array[JetVFX] = [
	$Visual/VisualRoot/JetVFXLeftWing1,
	$Visual/VisualRoot/JetVFXLeftWing2
]
@onready var _right_roll_jets : Array[JetVFX] = [
	$Visual/VisualRoot/JetVFXRightWing1,
	$Visual/VisualRoot/JetVFXRightWing2
]
@onready var _audio : ShipAudio = $ShipAudio

var _move_cmd := Vector3()
var _turn_cmd := Vector3()
var _superspeed_cmd := false
var _brake_cmd := false
var _exit_ship_cmd := false
var _state := STATE_FLYING
var _planet_damping_amount := 0.0 # TODO Doesnt need to be a member var
var _ref_change_info : ReferenceChangeInfo
var _was_superspeed := false
var _last_contacts_count := 0
var _ground_lock_active := false
var _ground_lock_body : StellarBody = null
var _ground_lock_local_transform := Transform3D.IDENTITY

var _speed_cap_in_space_superspeed_multiplier := 10.0
var _linear_acceleration_superspeed_multiplier := 15.0


func _ready():
	# Workaround because these node names can easily be unreliable due to import issues
	var visual_model_root := _visual_root.get_node("ship")
	for i in visual_model_root.get_child_count():
		var node := visual_model_root.get_child(i)
		if node is StaticBody3D:
			_landed_nodes.append(node)

	for n in _landed_nodes:
		_landed_node_parents.append(n.get_parent())
	
	_visual_root.global_transform = global_transform
	enable_controller()
	
	get_solar_system().reference_body_changed.connect(_on_solar_system_reference_body_changed)


func apply_game_settings(s: Settings):
	if s.world_scale_x10:
		speed_cap_in_space *= SolarSystemSetup.LARGE_SCALE
		speed_cap_on_planet *= 0.25 * SolarSystemSetup.LARGE_SCALE
		_speed_cap_in_space_superspeed_multiplier *= SolarSystemSetup.LARGE_SCALE
		_linear_acceleration_superspeed_multiplier *= SolarSystemSetup.LARGE_SCALE


func enable_controller():
	_ground_lock_active = false
	_ground_lock_body = null
	_controller.set_enabled(true)
	for n in _landed_nodes:
		n.get_parent().remove_child(n)
	for cs in _flight_collision_shapes:
		cs.disabled = false
	freeze = false
	_close_hatch()
	_state = STATE_FLYING
	_audio.play_enabled()


func disable_controller():
	_preserve_parked_ground_lock()
	_controller.set_enabled(false)
	for i in len(_landed_nodes):
		_landed_node_parents[i].add_child(_landed_nodes[i])
	for cs in _flight_collision_shapes:
		cs.disabled = true
	freeze = true
	_open_hatch()
	_state = STATE_LANDED
	_audio.play_disabled()


func _notification(what: int):
	if what == NOTIFICATION_PREDELETE:
		if _state != STATE_LANDED:
			for n in _landed_nodes:
				n.free()


func _open_hatch():
	_animation_player.play("hatch_open")


func _close_hatch():
	_animation_player.play_backwards("hatch_open")


func _on_solar_system_reference_body_changed(info: ReferenceChangeInfo):
	# We'll do that in `_integrate_forces`,
	# because Godot can't be bothered to do such override for us.
	# The camera following the ship will also needs to account for that delay...
	_ref_change_info = info
	#transform = info.inverse_transform * transform
	#_linear_velocity = info.inverse_transform.basis * _linear_velocity


func get_solar_system() -> SolarSystem:
	return get_parent()


func set_move_cmd(vec: Vector3):
	_move_cmd = vec


func set_turn_cmd(vec: Vector3):
	_turn_cmd = vec


func set_superspeed_cmd(cmd: bool):
	_superspeed_cmd = cmd


func set_brake_cmd(cmd: bool):
	_brake_cmd = cmd


func is_ground_locked() -> bool:
	return _ground_lock_active and _ground_lock_body != null


func get_ground_lock_body() -> StellarBody:
	return _ground_lock_body


func _physics_process(_delta: float) -> void:
	_apply_parked_ground_lock()


func _preserve_parked_ground_lock() -> void:
	if _ground_lock_active and _ground_lock_body != null:
		_ground_lock_local_transform = \
			_ground_lock_body.node.global_transform.affine_inverse() * global_transform
		return
	var body := _find_nearest_rocky_body(global_transform.origin)
	if body == null:
		return
	_ground_lock_body = body
	_ground_lock_local_transform = body.node.global_transform.affine_inverse() * global_transform
	_ground_lock_active = true


func _apply_parked_ground_lock() -> void:
	if _state != STATE_LANDED or not _ground_lock_active or _ground_lock_body == null:
		return
	if _ground_lock_body.node == null:
		return
	var locked_transform := _ground_lock_body.node.global_transform * _ground_lock_local_transform
	global_transform = locked_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	_visual_root.global_transform = locked_transform


func _integrate_forces(state: PhysicsDirectBodyState3D):
	if _ref_change_info != null:
		# Teleport
		state.transform = _ref_change_info.inverse_transform * state.transform
		state.linear_velocity = _ref_change_info.inverse_transform.basis * state.linear_velocity
		_ref_change_info = null
	
	var gtrans := state.transform
	var forward := -gtrans.basis.z
	var right := gtrans.basis.x
	var up := gtrans.basis.y

	if not _brake_cmd and _state != STATE_LANDED:
		_ground_lock_active = false
		_ground_lock_body = null

	if _state == STATE_LANDED and _ground_lock_active and _ground_lock_body != null:
		state.transform = _ground_lock_body.node.global_transform * _ground_lock_local_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_visual_root.global_transform = state.transform
		return

	var stellar_body : StellarBody = get_solar_system().get_reference_stellar_body()
	var linear_acceleration_mod := linear_acceleration
	var speed_cap_in_space_mod := speed_cap_in_space
	
	var superspeed := false
	if _superspeed_cmd and stellar_body.type == StellarBody.TYPE_SUN:
		speed_cap_in_space_mod *= _speed_cap_in_space_superspeed_multiplier
		linear_acceleration_mod *= _linear_acceleration_superspeed_multiplier
		superspeed = true
	
	if superspeed != _was_superspeed:
		if superspeed:
			_audio.play_start_superspeed()
		else:
			_audio.play_stop_superspeed()
		_was_superspeed = superspeed

	var speed_cap := speed_cap_in_space_mod
	
	var motor := _move_cmd.z * forward * linear_acceleration_mod
	state.apply_central_force(motor)

	_turn_cmd.x = clampf(_turn_cmd.x, -1.0, 1.0)
	_turn_cmd.y = clampf(_turn_cmd.y, -1.0, 1.0)
	_turn_cmd.z = clampf(_turn_cmd.z, -1.0, 1.0)
	
	state.apply_torque_impulse(up * _turn_cmd.x * angular_acceleration)
	state.apply_torque_impulse(right * _turn_cmd.y * angular_acceleration)
	state.apply_torque_impulse(forward * _turn_cmd.z * angular_acceleration)

	# Angular damping?
	#state.apply_torque_impulse(-state.angular_velocity * 0.01)

	# Planet influence
	if stellar_body.type != StellarBody.TYPE_SUN:
		var pull_center := stellar_body.node.global_transform.origin
		var distance_to_core := pull_center.distance_to(gtrans.origin)

		# Gravity
		# TODO Need a No-Man-Sky-esque mechanic to land without gravity
		# In case you dive into a stellar body, gravity actually reduces as you get closer to
		# the core, because some mass is now behind you
		# TODO Explicit typing should not be needed, there is a bug in GDScript2
		var gd : float = absf(distance_to_core - stellar_body.radius) + stellar_body.radius
		var gravity_dir := (pull_center - gtrans.origin).normalized()
		var stellar_mass := Util.get_sphere_volume(stellar_body.radius)
		var f := 0.005 * stellar_mass / (gd * gd)
		f = minf(f, 25.0)
		state.apply_central_force(gravity_dir * f)
		
		# Near-planet damping
		var distance_to_surface := distance_to_core - stellar_body.radius
		_planet_damping_amount = \
			1.0 - clampf((distance_to_surface - 50.0) / stellar_body.radius, 0.0, 1.0)
		DDD.set_text("Atmosphere damping amount", _planet_damping_amount)
		speed_cap = lerpf(speed_cap_in_space_mod, speed_cap_on_planet, _planet_damping_amount)
	
	var speed := state.linear_velocity.length()
	if speed > speed_cap:
		state.linear_velocity = state.linear_velocity.normalized() * speed_cap

	if _brake_cmd:
		if not _try_apply_brake_ground_lock(state):
			state.linear_velocity = state.linear_velocity.lerp(Vector3.ZERO, 0.35)
			state.angular_velocity = state.angular_velocity.lerp(Vector3.ZERO, 0.5)
		_move_cmd = Vector3.ZERO
		_turn_cmd = Vector3.ZERO
	
	# Jets
	var main_jet_power := _move_cmd.z
	for jet in _main_jets:
		jet.set_power(main_jet_power)
	var left_roll_jet_power := maxf(_turn_cmd.z, 0.0)
	var right_roll_jet_power := maxf(-_turn_cmd.z, 0.0)
	for jet in _left_roll_jets:
		jet.set_power(left_roll_jet_power)
	for jet in _right_roll_jets:
		jet.set_power(right_roll_jet_power)
	_audio.set_main_jet_power(absf(_move_cmd.z))
	_audio.set_secondary_jet_power(clampf(left_roll_jet_power + right_roll_jet_power, 0.0, 1.0))

	DDD.set_text("Speed", state.linear_velocity.length())
	DDD.set_text("X", gtrans.origin.x)
	DDD.set_text("Y", gtrans.origin.y)
	DDD.set_text("Z", gtrans.origin.z)
	
	_visual_root.global_transform = gtrans
	
	_last_contacts_count = state.get_contact_count()


func get_last_contacts_count() -> int:
	return _last_contacts_count


func _try_apply_brake_ground_lock(state: PhysicsDirectBodyState3D) -> bool:
	var body := _find_nearest_rocky_body(state.transform.origin)
	if body == null:
		_ground_lock_active = false
		_ground_lock_body = null
		return false

	var center := body.node.global_transform.origin
	var up := (state.transform.origin - center).normalized()
	var distance_to_surface := state.transform.origin.distance_to(center) - body.radius
	if distance_to_surface > brake_landing_trigger_distance:
		_ground_lock_active = false
		_ground_lock_body = null
		return false

	if _ground_lock_active and _ground_lock_body == body:
		state.transform = body.node.global_transform * _ground_lock_local_transform
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		return true

	# Deterministic landing target direction: nearest point on planet sphere from ship position.
	var target_normal: Vector3 = up
	var target_pos: Vector3 = center + target_normal * (body.radius + BRAKE_GROUND_LOCK_CLEARANCE)
	var surface_sampling_margin := maxf(brake_landing_trigger_distance, 150.0)
	var surface_raycast_length := maxf(brake_landing_trigger_distance * 2.5, 220.0)
	var space_state := state.get_space_state()
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = center + target_normal * (body.radius + surface_sampling_margin)
	ray_query.to = center + target_normal * maxf(body.radius - surface_raycast_length, 1.0)
	ray_query.exclude = [get_rid()]
	var hit := space_state.intersect_ray(ray_query)
	if not hit.is_empty():
		var hit_normal: Vector3 = hit.normal.normalized()
		target_normal = hit_normal
		target_pos = hit.position + hit_normal * BRAKE_GROUND_LOCK_CLEARANCE
	var target_basis: Basis = _align_basis_to_up(state.transform.basis, target_normal)

	var current_transform := state.transform
	var pos_lerp_factor := brake_landing_smoothness
	if distance_to_surface < 15.0:
		pos_lerp_factor = minf(0.7, pos_lerp_factor + 0.15)
	var smoothed_pos := current_transform.origin.lerp(target_pos, pos_lerp_factor)

	var q_current := current_transform.basis.orthonormalized().get_rotation_quaternion()
	var q_target := target_basis.orthonormalized().get_rotation_quaternion()
	var rot_lerp_factor := clampf(brake_landing_smoothness * 0.9, 0.05, 0.9)
	var q_smoothed := q_current.slerp(q_target, rot_lerp_factor).normalized()
	var smoothed_basis := Basis(q_smoothed).orthonormalized()

	state.transform = Transform3D(smoothed_basis, smoothed_pos)

	var lock_distance := smoothed_pos.distance_to(target_pos)
	var near_surface := distance_to_surface < maxf(BRAKE_GROUND_LOCK_CLEARANCE * 2.5, 10.0)
	var should_lock := lock_distance < brake_ground_lock_snap_distance or near_surface
	if should_lock:
		state.transform = Transform3D(target_basis, target_pos)
		state.linear_velocity = Vector3.ZERO
		state.angular_velocity = Vector3.ZERO
		_ground_lock_active = true
		_ground_lock_body = body
		_ground_lock_local_transform = body.node.global_transform.affine_inverse() * state.transform
	else:
		state.linear_velocity = state.linear_velocity.lerp(Vector3.ZERO, 0.25)
		state.angular_velocity = state.angular_velocity.lerp(Vector3.ZERO, 0.3)
		_ground_lock_active = false
		_ground_lock_body = null
	return true


func _find_nearest_rocky_body(pos: Vector3) -> StellarBody:
	var solar_system := get_solar_system()
	if solar_system == null:
		return null
	var nearest: StellarBody = null
	var nearest_surface_distance := INF
	for i in solar_system.get_stellar_body_count():
		var body: StellarBody = solar_system.get_stellar_body(i)
		if body.type != StellarBody.TYPE_ROCKY:
			continue
		var center := body.node.global_transform.origin
		var surface_distance := absf(pos.distance_to(center) - body.radius)
		if surface_distance < nearest_surface_distance:
			nearest_surface_distance = surface_distance
			nearest = body
	return nearest


static func _align_basis_to_up(current_basis: Basis, target_up: Vector3) -> Basis:
	var forward := -current_basis.z
	var projected_forward := (forward - target_up * forward.dot(target_up)).normalized()
	if projected_forward.length_squared() < 0.001:
		projected_forward = (current_basis.x - target_up * current_basis.x.dot(target_up)).normalized()
	if projected_forward.length_squared() < 0.001:
		projected_forward = Vector3.FORWARD
	return Basis.looking_at(projected_forward, target_up)

