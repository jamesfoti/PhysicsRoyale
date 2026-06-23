extends Node3D

const StellarBody = preload("res://solar_system/stellar_body.gd")
const Util = preload("res://util/util.gd")
const ReferenceChangeInfo = preload("res://solar_system/reference_change_info.gd")

const JUMP_STRENGTH := 70.0
const SPEED := 50.0
const DAMPING := 0.9

signal jumped

@export var angular_spring_stiffness: float = 4000.0
@export var angular_spring_damping: float = 80.0
@export var max_angular_force: float = 9999.0
@export var ragdoll_mode := false

@onready var _head: Node3D = $Head
@onready var _ragdoll: Node3D = $Ragdoll
@onready var _on_floor_left: ShapeCast3D = $"Ragdoll/Physical/Armature/Skeleton3D/Physical Bone LLeg2/OnFloorLeft"
@onready var _on_floor_right: ShapeCast3D = $"Ragdoll/Physical/Armature/Skeleton3D/Physical Bone RLeg2/OnFloorRight"
@onready var _jump_timer: Timer = $Ragdoll/Physical/JumpTimer
@onready var _physical_skel: Skeleton3D = $Ragdoll/Physical/Armature/Skeleton3D
@onready var _animated_skel: Skeleton3D = $Ragdoll/Animated/Armature/Skeleton3D
@onready var _animation_tree: AnimationTree = $Ragdoll/Animated/AnimationTree
@onready var _physical_bone_body: PhysicalBone3D = $"Ragdoll/Physical/Armature/Skeleton3D/Physical Bone Body"
@onready var _grab_joint_right: PinJoint3D = $Ragdoll/Physical/GrabJointRight
@onready var _grab_joint_left: PinJoint3D = $Ragdoll/Physical/GrabJointLeft
@onready var _physical_bone_l_arm_2: PhysicalBone3D = $"Ragdoll/Physical/Armature/Skeleton3D/Physical Bone LArm2"
@onready var _physical_bone_r_arm_2: PhysicalBone3D = $"Ragdoll/Physical/Armature/Skeleton3D/Physical Bone RArm2"
@onready var _l_grab_area: Area3D = $"Ragdoll/Physical/Armature/Skeleton3D/Physical Bone LArm2/LGrabArea"
@onready var _r_grab_area: Area3D = $"Ragdoll/Physical/Armature/Skeleton3D/Physical Bone RArm2/RGrabArea"

var _physics_bones: Array[PhysicalBone3D] = []
var _can_jump := true
var _is_on_floor := false
var _walking := false
var _current_delta := 0.0
var _active_arm_left := false
var _active_arm_right := false
var _grabbing_arm_left := false
var _grabbing_arm_right := false
var _planet_up := Vector3.UP
var _ref_change_info: ReferenceChangeInfo = null
var _pending_spawn_pos: Vector3 = Vector3.INF
var _pending_spawn_basis: Basis = Basis.IDENTITY
var _pending_spawn_planet : StellarBody = null
var _pending_spawn_local_transform := Transform3D.IDENTITY
var _planet_attach_body : StellarBody = null
var _planet_lock_local_transform := Transform3D.IDENTITY
var _was_on_floor := false
var _was_walking := false
var _spawn_settle_frames := 0
var _simulation_running := false


func configure_spawn(spawn_pos: Vector3, up: Vector3, forward: Vector3, planet: StellarBody = null) -> void:
	_pending_spawn_basis = Basis.looking_at(forward, up)
	_pending_spawn_pos = spawn_pos
	_pending_spawn_planet = planet
	if planet != null and planet.node != null:
		_pending_spawn_local_transform = \
			planet.node.global_transform.affine_inverse() * Transform3D(_pending_spawn_basis, spawn_pos)
	else:
		_pending_spawn_local_transform = Transform3D.IDENTITY


func setup_spawn(spawn_pos: Vector3, up: Vector3, forward: Vector3) -> void:
	configure_spawn(spawn_pos, up, forward)
	_apply_spawn_transform()


func _ready():
	_physics_bones.assign(
		_physical_skel.get_children().filter(func(x): return x is PhysicalBone3D))
	_physical_skel.skeleton_updated.connect(_on_skeleton_updated)
	_l_grab_area.body_entered.connect(_on_l_grab_area_body_entered)
	_r_grab_area.body_entered.connect(_on_r_grab_area_body_entered)
	_jump_timer.timeout.connect(_on_jump_timer_timeout)
	var ragdoll_cam := _ragdoll.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if ragdoll_cam != null:
		ragdoll_cam.current = false

	var solar_system := _get_solar_system()
	if solar_system != null and solar_system.has_signal("reference_body_changed"):
		solar_system.reference_body_changed.connect(_on_reference_body_changed)

	if _pending_spawn_pos == Vector3.INF:
		_pending_spawn_pos = global_position
		_pending_spawn_basis = global_transform.basis
	elif _pending_spawn_planet != null and get_parent() == _pending_spawn_planet.node:
		transform = _pending_spawn_local_transform
		_planet_attach_body = _pending_spawn_planet
		_was_on_floor = true

	call_deferred("_begin_spawn_settle")


func _start_simulation() -> void:
	if _simulation_running:
		return
	var simulator := _physical_skel.get_parent().get_node_or_null("PhysicalBoneSimulator3D")
	if simulator != null:
		simulator.physical_bones_start_simulation()
	else:
		_physical_skel.physical_bones_start_simulation()
	_simulation_running = true


func stop_simulation() -> void:
	if not _simulation_running:
		return
	var simulator := _physical_skel.get_parent().get_node_or_null("PhysicalBoneSimulator3D")
	if simulator != null:
		simulator.physical_bones_stop_simulation()
	else:
		_physical_skel.physical_bones_stop_simulation()
	_simulation_running = false


func _begin_spawn_settle() -> void:
	stop_simulation()
	_apply_spawn_transform()
	_pin_body_to_character_root()
	_zero_all_bone_velocities()
	_spawn_settle_frames = 30
	if _pending_spawn_planet != null:
		_planet_attach_body = _pending_spawn_planet
		_was_on_floor = true


func _apply_spawn_transform() -> void:
	if _pending_spawn_planet != null and _pending_spawn_planet.node != null:
		var spawn_global := _pending_spawn_planet.node.global_transform * _pending_spawn_local_transform
		if get_parent() == _pending_spawn_planet.node:
			transform = _pending_spawn_local_transform
		else:
			global_transform = spawn_global
	else:
		global_transform = Transform3D(_pending_spawn_basis, _pending_spawn_pos)
	_ragdoll.transform = Transform3D.IDENTITY
	_animation_tree.set("parameters/walking/blend_amount", 0.0)
	_animation_tree.set("parameters/grab_dir/blend_position", 0.0)
	_animated_skel.rotation.y = _head.rotation.y


func _pin_body_to_character_root() -> void:
	_physical_bone_body.global_transform = global_transform
	_zero_all_bone_velocities()


func _sync_spawn_physical_bones() -> void:
	_pin_body_to_character_root()


func _zero_all_bone_velocities() -> void:
	for b: PhysicalBone3D in _physics_bones:
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO


func _get_move_direction() -> Vector3:
	var dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		dir += _head.global_transform.basis.z
	if Input.is_action_pressed("move_left"):
		dir += _head.global_transform.basis.x
	if Input.is_action_pressed("move_right"):
		dir -= _head.global_transform.basis.x
	if Input.is_action_pressed("move_backward"):
		dir -= _head.global_transform.basis.z
	var plane := Plane(_planet_up, 0.0)
	return plane.project(dir).normalized()


func is_on_floor() -> bool:
	return _is_on_floor


func get_body_transform() -> Transform3D:
	return _physical_bone_body.global_transform


func get_body_rid() -> RID:
	return _physical_bone_body.get_rid()


func _input(_event: InputEvent) -> void:
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return

	if Input.is_action_just_pressed("ragdoll_toggle"):
		ragdoll_mode = not ragdoll_mode

	_active_arm_left = Input.is_action_pressed("grab_left")
	_active_arm_right = Input.is_action_pressed("grab_right")

	if (not _active_arm_left and _grabbing_arm_left) or ragdoll_mode:
		_grabbing_arm_left = false
		_grab_joint_left.node_a = NodePath()
		_grab_joint_left.node_b = NodePath()

	if (not _active_arm_right and _grabbing_arm_right) or ragdoll_mode:
		_grabbing_arm_right = false
		_grab_joint_right.node_a = NodePath()
		_grab_joint_right.node_b = NodePath()


func _process(_delta: float) -> void:
	var head_pitch: float = _head.rotation.x
	var r: float = clamp((head_pitch * 2.0) / PI * 2.1, -1.0, 1.0)
	if _active_arm_left or _active_arm_right:
		_animation_tree.set("parameters/grab_dir/blend_position", r)
	else:
		_animation_tree.set("parameters/grab_dir/blend_position", 0.0)


func _physics_process(delta: float) -> void:
	_current_delta = delta
	_update_planet_up()

	if _spawn_settle_frames > 0:
		_spawn_settle_frames -= 1
		stop_simulation()
		_apply_spawn_transform()
		_pin_body_to_character_root()
		_zero_all_bone_velocities()
		return

	_walking = _read_walking_input()
	var wants_jump := Input.is_action_pressed("jump")
	var landing_body := get_landing_body()
	var on_planet_surface := _is_on_planet_surface(landing_body)

	if ragdoll_mode:
		if _planet_attach_body != null:
			_detach_from_planet()
		_start_simulation()
		_apply_airborne_physics(delta, _get_move_direction())
		_is_on_floor = _check_on_floor()
		_was_on_floor = _is_on_floor
		_was_walking = _walking
		_finalize_visual_and_animation()
		return

	if on_planet_surface and not wants_jump:
		_attach_idle_to_planet(landing_body)
		stop_simulation()
		if _walking:
			global_position += _get_move_direction() * SPEED * delta
		_pin_body_to_character_root()
		_is_on_floor = true
		_was_on_floor = true
		_was_walking = _walking
		_finalize_visual_and_animation()
		return

	if wants_jump and on_planet_surface and _can_jump:
		_detach_from_planet()
		_start_simulation()
		_pin_body_to_character_root()
		_physical_bone_body.linear_velocity = _planet_up * JUMP_STRENGTH
		_jump_timer.start()
		_can_jump = false
		jumped.emit()
		_is_on_floor = false
		_was_on_floor = false
		_was_walking = _walking
		_finalize_visual_and_animation()
		return

	if _planet_attach_body != null:
		_detach_from_planet()
	_start_simulation()

	if on_planet_surface and landing_body != null:
		_apply_planet_carry(landing_body)

	if _ref_change_info != null:
		global_transform = _ref_change_info.inverse_transform * global_transform
		_physical_bone_body.linear_velocity = \
			_ref_change_info.inverse_transform.basis * _physical_bone_body.linear_velocity
		_ref_change_info = null

	_apply_airborne_physics(delta, _get_move_direction())

	_is_on_floor = _check_on_floor()

	if _is_on_floor and landing_body != null:
		_planet_lock_local_transform = \
			landing_body.node.global_transform.affine_inverse() * global_transform
	elif not _is_on_floor:
		_planet_lock_local_transform = Transform3D.IDENTITY

	_was_on_floor = _is_on_floor
	_was_walking = _walking
	_finalize_visual_and_animation()


func _apply_airborne_physics(delta: float, dir: Vector3) -> void:
	_apply_planet_gravity(delta)
	_physical_bone_body.linear_velocity += dir * SPEED * delta
	var damped := _physical_bone_body.linear_velocity
	var plane := Plane(_planet_up, 0.0)
	var planar := plane.project(damped)
	damped -= planar * (1.0 - DAMPING)
	damped -= _planet_up * damped.dot(_planet_up) * (1.0 - DAMPING)
	_physical_bone_body.linear_velocity = damped


func _read_walking_input() -> bool:
	return Input.is_action_pressed("move_forward") \
		or Input.is_action_pressed("move_backward") \
		or Input.is_action_pressed("move_left") \
		or Input.is_action_pressed("move_right")


func _is_grounded(body: StellarBody) -> bool:
	if _check_on_floor():
		return true
	var pos := global_transform.origin
	var center := body.node.global_transform.origin
	return absf(pos.distance_to(center) - body.radius) < 40.0


func _is_on_planet_surface(body: StellarBody) -> bool:
	if body == null:
		return false
	if _planet_attach_body == body and get_parent() == body.node:
		return true
	return _is_grounded(body)


func _attach_idle_to_planet(body: StellarBody) -> void:
	if body == null or body.node == null:
		return
	var solar_system := _get_solar_system()
	if solar_system == null:
		return
	if _planet_attach_body == body and get_parent() == body.node:
		_pin_body_to_character_root()
		return
	var gtrans := global_transform
	if get_parent() != body.node:
		if get_parent() != null:
			get_parent().remove_child(self)
		body.node.add_child(self)
		global_transform = gtrans
	_planet_attach_body = body


func _detach_from_planet() -> void:
	if _planet_attach_body == null:
		return
	var solar_system := _get_solar_system()
	if solar_system == null:
		_planet_attach_body = null
		return
	if _planet_attach_body.node != null:
		_planet_lock_local_transform = \
			_planet_attach_body.node.global_transform.affine_inverse() * global_transform
	var gtrans := global_transform
	if get_parent() != solar_system:
		if get_parent() != null:
			get_parent().remove_child(self)
		solar_system.add_child(self)
		global_transform = gtrans
	_planet_attach_body = null


func _finalize_visual_and_animation() -> void:
	if _walking:
		_animation_tree.set("parameters/walking/blend_amount", 1.0)
	else:
		_animation_tree.set("parameters/walking/blend_amount", 0.0)
	_sync_visual_from_body()


func _sync_visual_from_body() -> void:
	_animated_skel.rotation.y = _head.rotation.y
	if not _simulation_running:
		return
	var head_bone: PhysicalBone3D = $"Ragdoll/Physical/Armature/Skeleton3D/Physical Bone Head"
	_head.global_position = head_bone.global_position
	$Visual.global_position = head_bone.global_position
	if _planet_attach_body == null:
		global_position = _physical_bone_body.global_position


func _update_planet_up() -> void:
	var body := get_landing_body()
	if body != null:
		var pos := global_transform.origin
		if _simulation_running:
			pos = _physical_bone_body.global_position
		var to_core := body.node.global_transform.origin - pos
		if to_core.length_squared() > 0.001:
			_planet_up = to_core.normalized()
	else:
		_planet_up = Vector3.UP


func get_landing_body() -> StellarBody:
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
		var d := b.node.global_transform.origin.distance_to(global_transform.origin)
		if d < b.radius * 4.0 and d < closest_d:
			closest = b
			closest_d = d
	return closest


func _apply_planet_carry(body: StellarBody) -> void:
	var carried_origin := (body.node.global_transform * _planet_lock_local_transform).origin
	var carry_delta := carried_origin - global_transform.origin
	if carry_delta.length_squared() < 0.000001:
		return
	global_position += carry_delta
	if _simulation_running:
		_physical_bone_body.global_position += carry_delta
		var carry_velocity := carry_delta / maxf(_current_delta, 0.0001)
		var plane := Plane(_planet_up, 0.0)
		var vel := _physical_bone_body.linear_velocity
		vel += plane.project(carry_velocity)
		_physical_bone_body.linear_velocity = vel


func _apply_planet_gravity(delta: float) -> void:
	var body := get_landing_body()
	if body == null:
		return
	var pull_center := body.node.global_transform.origin
	var pos := _physical_bone_body.global_position
	var gd := absf(pull_center.distance_to(pos) - body.radius) + body.radius
	var gravity_dir := (pull_center - pos).normalized()
	var stellar_mass := Util.get_sphere_volume(body.radius)
	var f := 0.005 * stellar_mass / (gd * gd)
	f = minf(f, 25.0)
	_physical_bone_body.linear_velocity -= gravity_dir * f * delta


func _check_on_floor() -> bool:
	for cast in [_on_floor_left, _on_floor_right]:
		if not cast.is_colliding():
			continue
		for i in cast.get_collision_count():
			if cast.get_collision_normal(i).dot(_planet_up) > 0.5:
				return true
	return false


func _on_skeleton_updated() -> void:
	if ragdoll_mode or _spawn_settle_frames > 0:
		return
	if not _simulation_running:
		return
	for b: PhysicalBone3D in _physics_bones:
		if not _active_arm_left and b.name.contains("LArm"):
			continue
		if not _active_arm_right and b.name.contains("RArm"):
			continue
		var target_transform: Transform3D = \
			_animated_skel.global_transform * _animated_skel.get_bone_global_pose(b.get_bone_id())
		var current_transform: Transform3D = \
			_physical_skel.global_transform * _physical_skel.get_bone_global_pose(b.get_bone_id())
		var rotation_difference: Basis = target_transform.basis * current_transform.basis.inverse()
		var torque := _hookes_law(
			rotation_difference.get_euler(), b.angular_velocity,
			angular_spring_stiffness, angular_spring_damping)
		torque = torque.limit_length(max_angular_force)
		b.angular_velocity += torque * _current_delta


static func _hookes_law(
	displacement: Vector3, current_velocity: Vector3,
	stiffness: float, damping: float) -> Vector3:
	return (stiffness * displacement) - (damping * current_velocity)


func _on_r_grab_area_body_entered(body: Node3D) -> void:
	if body is PhysicsBody3D and body.get_parent() != _physical_skel:
		if _active_arm_right and not _grabbing_arm_right:
			_grabbing_arm_right = true
			_grab_joint_right.global_position = _r_grab_area.global_position
			_grab_joint_right.node_a = _physical_bone_r_arm_2.get_path()
			_grab_joint_right.node_b = body.get_path()


func _on_l_grab_area_body_entered(body: Node3D) -> void:
	if body is PhysicsBody3D and body.get_parent() != _physical_skel:
		if _active_arm_left and not _grabbing_arm_left:
			_grabbing_arm_left = true
			_grab_joint_left.global_position = _l_grab_area.global_position
			_grab_joint_left.node_a = _physical_bone_l_arm_2.get_path()
			_grab_joint_left.node_b = body.get_path()


func _on_jump_timer_timeout() -> void:
	_can_jump = true


func _on_reference_body_changed(info: ReferenceChangeInfo) -> void:
	_ref_change_info = info


func _get_solar_system() -> SolarSystem:
	var node := get_parent()
	while node != null:
		if node is SolarSystem:
			return node
		node = node.get_parent()
	return null
