extends Node

const StellarBody = preload("../solar_system/stellar_body.gd")
var CharacterScene = load("res://character/character.tscn")
const SS_Camera = preload("res://camera/camera.gd")

const UPRIGHT_DOT_THRESHOLD := 0.75
const GROUND_RAY_LENGTH := 8.0
const SPAWN_FORWARD_OFFSET := 5.0
const SPAWN_LIFT := 2.0
const FOOT_CLEARANCE := 0.15

@onready var _ship : Ship = get_parent()
@onready var _character_spawn_position_node : Node3D = get_node("../CharacterSpawnPosition")
@onready var _ground_check_position_node : Node3D = get_node("../GroundCheckPosition")

@export var keyboard_turn_sensitivity := 0.1
@export var mouse_turn_sensitivity := 0.1

var _turn_cmd := Vector3()
var _exit_ship_cmd := false


func set_enabled(enabled: bool):
	set_process(enabled)
	set_process_input(enabled)
	set_physics_process(enabled)


func can_exit_ship() -> Dictionary:
	var result := {"can_exit": false}
	if not is_processing():
		return result
	if not _ship.is_ground_locked():
		return result
	var landing_body: StellarBody = _ship.get_ground_lock_body()
	if landing_body == null or landing_body.type != StellarBody.TYPE_ROCKY:
		return result

	var ship_trans := _ship.global_transform
	var planet_center := landing_body.node.global_transform.origin
	var down := (planet_center - ship_trans.origin).normalized()
	if down.dot(-ship_trans.basis.y) < UPRIGHT_DOT_THRESHOLD:
		return result

	var ground_check_pos := _ground_check_position_node.global_transform.origin
	var space_state := _ship.get_world_3d().direct_space_state
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = ground_check_pos
	ray_query.to = ground_check_pos + down * 2.0
	ray_query.exclude = [_ship.get_rid()]
	if space_state.intersect_ray(ray_query).is_empty():
		return result

	var spawn_data: Dictionary = _get_exit_spawn_position(landing_body, down, space_state)
	if spawn_data.is_empty():
		return result

	result.can_exit = true
	return result


func _process(_delta: float):
	if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
		return
	
	var motor := Vector3()
	
	if Input.is_key_pressed(KEY_S):
		motor.z -= 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z):
		motor.z += 1
	if Input.is_key_pressed(KEY_SPACE):
		motor.y += 1
	if Input.is_key_pressed(KEY_SHIFT):
		motor.y -= 1

	if Input.is_key_pressed(KEY_CTRL):
		motor = Vector3.ZERO;
		_turn_cmd = Vector3.ZERO;

	if Input.is_key_pressed(KEY_A):
		_turn_cmd.z -= keyboard_turn_sensitivity
	if Input.is_key_pressed(KEY_D):
		_turn_cmd.z += keyboard_turn_sensitivity
	
	_ship.set_superspeed_cmd(Input.is_key_pressed(KEY_SPACE) and not Input.is_key_pressed(KEY_CTRL))
	_ship.set_brake_cmd(Input.is_key_pressed(KEY_CTRL))
	
	_turn_cmd.x = clampf(_turn_cmd.x, -1.0, 1.0)
	_turn_cmd.y = clampf(_turn_cmd.y, -1.0, 1.0)
	_turn_cmd.z = clampf(_turn_cmd.z, -1.0, 1.0)
	motor.x = clampf(motor.x, -1.0, 1.0)
	motor.y = clampf(motor.y, -1.0, 1.0)
	motor.z = clampf(motor.z, -1.0, 1.0)
	
	_ship.set_move_cmd(motor)
	_ship.set_turn_cmd(_turn_cmd)
	_turn_cmd = Vector3()


func _physics_process(_delta: float):
	if _exit_ship_cmd:
		_exit_ship_cmd = false
		_try_exit_ship()
	
	if is_processing():
		_process_dig_actions()
		

func _get_exit_spawn_position(
		_landing_body: StellarBody,
		down: Vector3,
		space_state: PhysicsDirectSpaceState3D) -> Dictionary:
	var ship_trans := _ship.global_transform
	var surface_up := -down.normalized()
	var forward := -ship_trans.basis.z
	forward = (forward - surface_up * forward.dot(surface_up)).normalized()
	if forward.length_squared() < 0.001:
		forward = ship_trans.basis.x

	# Place the exit point on the ground ahead of the ship nose, not under the hull.
	var hatch_pos := _character_spawn_position_node.global_transform.origin
	var ray_origin := hatch_pos + forward * SPAWN_FORWARD_OFFSET + surface_up * SPAWN_LIFT
	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = ray_origin
	ray_query.to = ray_origin + down * (GROUND_RAY_LENGTH + SPAWN_LIFT)
	ray_query.exclude = [_ship.get_rid()]
	var hit := space_state.intersect_ray(ray_query)
	if hit.is_empty():
		return {}
	return {
		"position": hit.position + hit.normal * FOOT_CLEARANCE,
		"normal": hit.normal,
	}


func _try_exit_ship():
	var status := can_exit_ship()
	if not status.get("can_exit", false):
		return

	var landing_body: StellarBody = _ship.get_ground_lock_body()
	var ship_trans := _ship.global_transform
	var planet_center := landing_body.node.global_transform.origin
	var surface_up := (ship_trans.origin - planet_center).normalized()
	var down := -surface_up
	var space_state := _ship.get_world_3d().direct_space_state
	var spawn_data: Dictionary = _get_exit_spawn_position(landing_body, down, space_state)
	if spawn_data.is_empty():
		return

	var up: Vector3 = spawn_data["normal"]
	var spawn_pos: Vector3 = spawn_data["position"]

	var forward := -ship_trans.basis.z
	forward = (forward - up * forward.dot(up)).normalized()
	if forward.length_squared() < 0.001:
		forward = ship_trans.basis.x

	var character : Node3D = CharacterScene.instantiate()
	character.configure_spawn(spawn_pos, up, forward, landing_body)
	_ship.get_solar_system().add_child(character)

	var camera : SS_Camera = get_viewport().get_camera_3d()
	camera.set_target(character)
	_ship.disable_controller()
	var solar_system := _ship.get_solar_system()
	if solar_system != null:
		solar_system.set_character_control_mode(true)


# TODO I could not use `_unhandled_input`
# because otherwise control is stuck for the duration of the pause menu animations
# See https://github.com/godotengine/godot/issues/20234
func _input(event: InputEvent):
	if not Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		return
	
	if event is InputEventMouseMotion:
		# Get mouse delta
		var motion : Vector2 = -event.relative
		var cmd := mouse_turn_sensitivity * motion
		_turn_cmd.x += cmd.x
		_turn_cmd.y += cmd.y
	
	elif event is InputEventKey:
		if event.pressed:
			match event.keycode:
				KEY_E:
					_exit_ship_cmd = true


# TODO Temporary, need to replace this with a rocket launcher
func _process_dig_actions():
	var camera := get_viewport().get_camera_3d()
	var front := -camera.global_transform.basis.z
	var cam_pos := camera.global_transform.origin
	var space_state := camera.get_world_3d().direct_space_state

	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = cam_pos
	ray_query.to = cam_pos + front * 50.0
	ray_query.exclude = [_ship.get_rid()]
	var hit = space_state.intersect_ray(ray_query)
	
	var dig_cmd = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	
	if not hit.is_empty():
		if hit.collider is VoxelLodTerrain:
			var volume : VoxelLodTerrain = hit.collider
			if dig_cmd:
				var vt : VoxelTool = volume.get_voxel_tool()
				var hit_pos : Vector3 = hit.position
				var pos := volume.get_global_transform().affine_inverse() * hit_pos
				var sphere_size := 15.0
				pos -= front * (sphere_size * 0.7)
				vt.channel = VoxelBuffer.CHANNEL_SDF
				vt.mode = VoxelTool.MODE_REMOVE
				vt.do_sphere(pos, sphere_size)
