extends CharacterBody3D
class_name PlanetPlayer
## Walks on spherical terrain: mouse yaw, W/S move relative to camera view.

const PLUSH_SKIN := preload("res://character/godot_plush/godot_plush_skin.gd")
const _MIN_DIR_LEN_SQ: float = 0.0001
const _INPUT_DEADZONE: float = 0.01
const _SPAWN_ATTEMPTS: int = 12
const _SPAWN_RAY_MARGIN: float = 40.0
const _FALLBACK_PLANET_RADIUS: float = 18.0

class SpawnData:
	var position: Vector3 = Vector3.ZERO
	var up: Vector3 = Vector3.UP
	var forward: Vector3 = Vector3.FORWARD
	var from_hit: bool = false


@export var planet: Node3D
@export var speed: float = 5.0
@export var run_speed: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity_strength: float = 9.8
@export var surface_align_speed: float = 10.0
@export var mouse_sensitivity: float = 0.0025
@export var spawn_clearance: float = 1.2

@onready var _plush_skin: PLUSH_SKIN = $VisualRoot/GodotPlushSkin
@onready var _orbit_camera: OrbitCamera = $OrbitCamera
@onready var _camera: Camera3D = $OrbitCamera/Camera3D

var _gravity_direction: Vector3 = Vector3.DOWN
var _terrain: TerrainWorldV2
var _anim_state: String = ""
var _want_jump: bool = false
var _spawned: bool = false


func _ready() -> void:
	_cache_planet_refs()
	call_deferred("_spawn_on_planet")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("jump"):
		_want_jump = true
	if event.is_action_pressed("wave") and is_on_floor() and not _get_skin().is_waving():
		_get_skin().wave()


func _input(event: InputEvent) -> void:
	if not _spawned or Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	if _is_camera_orbiting():
		return
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		_apply_mouse_yaw(motion.relative.x)


func _physics_process(delta: float) -> void:
	if planet == null or not _spawned:
		return

	_update_gravity_direction()
	up_direction = _get_up()

	var move_dir: Vector3 = _get_movement_direction()
	_apply_movement(delta, move_dir)

	var facing: Vector3 = _get_facing_direction(move_dir)
	if move_dir.length_squared() > _MIN_DIR_LEN_SQ:
		var input_fb: float = Input.get_axis("move_backward", "move_forward")
		if input_fb > _INPUT_DEADZONE:
			_orbit_camera.recenter_yaw(delta)
	_align_up_to_planet(delta, facing)
	move_and_slide()
	_update_animation(move_dir)


func _apply_movement(delta: float, move_dir: Vector3) -> void:
	var move_speed: float = run_speed if Input.is_action_pressed("run") else speed
	var radial_speed: float = velocity.dot(_gravity_direction)

	if move_dir.length_squared() > _MIN_DIR_LEN_SQ:
		velocity = move_dir * move_speed + _gravity_direction * radial_speed
	elif is_on_floor():
		velocity = Vector3.ZERO

	if not is_on_floor():
		velocity += _gravity_direction * gravity_strength * delta

	if _want_jump and is_on_floor() and not _get_skin().is_waving():
		velocity += _get_up() * jump_velocity
	_want_jump = false


func _apply_mouse_yaw(mouse_dx: float) -> void:
	var up: Vector3 = _get_up()
	if up.length_squared() > _MIN_DIR_LEN_SQ:
		global_basis = Basis(up, -mouse_dx * mouse_sensitivity) * global_basis


func _is_camera_orbiting() -> bool:
	return _orbit_camera.is_orbiting()


func _update_gravity_direction() -> void:
	var to_center: Vector3 = _get_planet_center() - global_position
	if to_center.length_squared() > _MIN_DIR_LEN_SQ:
		_gravity_direction = to_center.normalized()


func _get_up() -> Vector3:
	return -_gravity_direction


func _get_planet_center() -> Vector3:
	if _terrain != null:
		return _terrain.global_position + _terrain.sphere_center
	if planet is TerrainWorldV2:
		var tw: TerrainWorldV2 = planet as TerrainWorldV2
		return tw.global_position + tw.sphere_center
	if planet != null:
		return planet.global_position
	return Vector3.ZERO


func _get_flat_forward() -> Vector3:
	var up: Vector3 = _get_up()
	var forward: Vector3 = (-global_transform.basis.z).slide(up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = global_transform.basis.x.slide(up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = up.cross(Vector3.RIGHT)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		forward = up.cross(Vector3.FORWARD)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return Vector3.ZERO
	return forward.normalized()


func _get_camera_flat_forward() -> Vector3:
	var up: Vector3 = _get_up()
	var forward: Vector3 = (-_camera.global_basis.z).slide(up)
	if forward.length_squared() < _MIN_DIR_LEN_SQ:
		return _get_flat_forward()
	return forward.normalized()


func _get_movement_direction() -> Vector3:
	var input_fb: float = Input.get_axis("move_backward", "move_forward")
	if absf(input_fb) < _INPUT_DEADZONE:
		return Vector3.ZERO
	var forward: Vector3 = _get_camera_flat_forward()
	if forward == Vector3.ZERO:
		return Vector3.ZERO
	return forward * input_fb


func _get_facing_direction(move_dir: Vector3) -> Vector3:
	if move_dir.length_squared() < _MIN_DIR_LEN_SQ:
		return _get_flat_forward()
	# Backpedal: keep facing camera forward so body rotation does not spin the camera.
	var input_fb: float = Input.get_axis("move_backward", "move_forward")
	if input_fb < -_INPUT_DEADZONE:
		var camera_forward: Vector3 = _get_camera_flat_forward()
		if camera_forward != Vector3.ZERO:
			return camera_forward
	return move_dir.normalized()


func _align_up_to_planet(delta: float, facing: Vector3) -> void:
	var up: Vector3 = _get_up()
	if facing.length_squared() < _MIN_DIR_LEN_SQ:
		return

	var target_basis: Basis = Basis.looking_at(facing.normalized(), up).orthonormalized()
	var blend: float = minf(1.0, surface_align_speed * delta)
	global_transform.basis = Basis(
		global_transform.basis.get_rotation_quaternion().slerp(
			target_basis.get_rotation_quaternion(),
			blend
		)
	)


func _cache_planet_refs() -> void:
	if planet == null:
		planet = get_tree().get_first_node_in_group("planet") as Node3D
	if planet is TerrainWorldV2:
		_terrain = planet as TerrainWorldV2


func respawn_random() -> void:
	_cache_planet_refs()
	_apply_spawn(_find_random_surface_spawn())


func _spawn_on_planet() -> void:
	_cache_planet_refs()
	if planet == null:
		push_warning("[PlanetPlayer] No planet assigned.")
		return

	var spawn: SpawnData = SpawnData.new()
	for _attempt: int in _SPAWN_ATTEMPTS:
		await get_tree().physics_frame
		spawn = _find_random_surface_spawn()
		if spawn.from_hit:
			break

	_apply_spawn(spawn)


func _apply_spawn(spawn: SpawnData) -> void:
	global_transform = Transform3D(Basis.looking_at(spawn.forward, spawn.up), spawn.position)
	velocity = Vector3.ZERO
	_want_jump = false
	_anim_state = ""
	_update_gravity_direction()
	_orbit_camera.rotation = Vector3(_orbit_camera.rotation.x, 0.0, _orbit_camera.rotation.z)
	_get_skin().set_state("idle")
	_spawned = true


func _find_random_surface_spawn() -> SpawnData:
	var spawn: SpawnData = SpawnData.new()
	var dir: Vector3 = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
	).normalized()
	var center: Vector3 = _get_planet_center()
	var radius: float = (
		_terrain.get_sphere_radius() if _terrain != null else _FALLBACK_PLANET_RADIUS
	)
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		center + dir * (radius + _SPAWN_RAY_MARGIN),
		center - dir * (radius + _SPAWN_RAY_MARGIN)
	)
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty() and not _is_planet_collider(hit.get("collider")):
		hit = {}
	if hit.is_empty():
		spawn.position = center + dir * (radius + spawn_clearance)
		spawn.up = dir
		spawn.forward = _tangent_forward_on_plane(dir)
		spawn.from_hit = false
		return spawn

	var surface_up: Vector3 = hit.normal
	spawn.position = hit.position + surface_up * spawn_clearance
	spawn.up = surface_up
	spawn.forward = _tangent_forward_on_plane(surface_up)
	spawn.from_hit = true
	return spawn


func _is_planet_collider(collider: Variant) -> bool:
	if planet == null or not (collider is Node):
		return false
	var node: Node = collider as Node
	return planet == node or planet.is_ancestor_of(node)


func _tangent_forward_on_plane(up: Vector3) -> Vector3:
	var forward: Vector3 = up.cross(Vector3.FORWARD)
	if forward.length_squared() < 0.01:
		forward = up.cross(Vector3.RIGHT)
	return forward.normalized()


func _get_skin() -> PLUSH_SKIN:
	return _plush_skin


func _set_anim_state(skin: PLUSH_SKIN, state_name: String) -> void:
	if _anim_state == state_name:
		return
	_anim_state = state_name
	skin.set_state(state_name)


func _update_animation(move_dir: Vector3) -> void:
	var skin: PLUSH_SKIN = _get_skin()
	if skin.is_waving():
		return

	var vertical_speed: float = velocity.dot(_get_up())
	if not is_on_floor():
		_set_anim_state(skin, "jump" if vertical_speed > 0.05 else "fall")
	elif move_dir.length_squared() > _MIN_DIR_LEN_SQ:
		_set_anim_state(skin, "run" if Input.is_action_pressed("run") else "walk")
	else:
		_set_anim_state(skin, "idle")
