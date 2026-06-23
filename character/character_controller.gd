extends Node

const StellarBody = preload("../solar_system/stellar_body.gd")
const Ship = preload("../ship/ship.gd")
const Util = preload("../util/util.gd")
const CollisionLayers = preload("../collision_layers.gd")
# TODO This is very close to Godot's CharacterBody3D. Introduce prefixes?
# It could be confusing to not realize this is actually from the project and not Godot
const OrbitalCharacter = preload("res://character/orbital_character.gd")
const SplitChunkRigidBodyComponent = preload("../solar_system/split_chunk_rigidbody_component.gd")
const CharacterAudio = preload("./character_audio.gd")
const Waypoint = preload("res://waypoints/waypoint.gd")

const WaypointScene = preload("../waypoints/waypoint.tscn")

const VERTICAL_CORRECTION_SPEED = PI
const MOVE_ACCELERATION = 40.0
const MOVE_DAMP_FACTOR = 0.1
const JUMP_COOLDOWN_TIME = 0.3
const JUMP_SPEED = 8.0

const TerrainEditCursor = preload("res://character/terrain_edit_cursor.gd")

@onready var _head : Node3D = get_node("../Head")
@onready var _visual_root : Node3D = get_node("../Visual")
@onready var _visual_head : Node3D = get_node("../Visual/Head")
@onready var _flashlight : SpotLight3D = get_node("../Visual/FlashLight")
@onready var _audio : CharacterAudio = get_node("../Audio")
@onready var _terrain_cursor : TerrainEditCursor = $TerrainEditCursor

var _velocity := Vector3()
var _dig_cmd := false
var _interact_cmd := false
var _build_cmd := false
var _waypoint_cmd := false
var _last_motor := Vector3()


func _physics_process(delta):
	var character_body := _get_body()
	var motor := Vector3()

	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_Z):
		motor += Vector3(0, 0, -1)
	if Input.is_key_pressed(KEY_S):
		motor += Vector3(0, 0, 1)
	if Input.is_key_pressed(KEY_A):
		motor += Vector3(-1, 0, 0)
	if Input.is_key_pressed(KEY_D):
		motor += Vector3(1, 0, 0)

	character_body.set_motor(motor)

	var landing_body := _get_landing_body()
	var planet_up: Vector3
	if landing_body != null:
		var planet_center := landing_body.node.global_transform.origin
		planet_up = (character_body.global_position - planet_center).normalized()
		character_body.set_landing_body(landing_body)
	else:
		planet_up = character_body.global_position.normalized()
		if planet_up.length_squared() < 0.001:
			planet_up = Vector3.UP
		character_body.set_landing_body(null)
	character_body.set_planet_up(planet_up)

	var camera := get_viewport().get_camera_3d()
	if camera != null:
		var move_plane := Plane(planet_up, 0.0)
		var move_back := move_plane.project(camera.global_transform.basis.z).normalized()
		var move_right := move_plane.project(camera.global_transform.basis.x).normalized()
		character_body.set_move_basis(move_right, move_back)
	
	_process_actions()
	_process_undig()
	
	_last_motor = motor


func _process_undig():
	var character_body := _get_body()
	if character_body.is_spawn_settling():
		return
	var solar_system := _get_solar_system()
	if solar_system == null:
		# In testing scene?
		return
	var landing_body := _get_landing_body()
	if landing_body == null or landing_body.volume == null:
		return
	var volume := landing_body.volume
	var vt : VoxelToolLodTerrain = volume.get_voxel_tool()
	var to_local := volume.global_transform.affine_inverse()
	var local_pos := to_local * character_body.global_transform.origin
	vt.channel = VoxelBuffer.CHANNEL_SDF
	var sdf := vt.get_voxel_f_interpolated(local_pos)
	DDD.set_text("SDF at feet", sdf)
	if sdf < -0.001:
		# We got buried, teleport at nearest safe location
		print("Character is buried, teleporting back to air")
		var up := local_pos.normalized()
		var offset_local_pos := local_pos
		for i in 10:
			print("Undig attempt ", i)
			offset_local_pos += 0.2 * up
			sdf = vt.get_voxel_f_interpolated(offset_local_pos)
			if sdf > 0.0005:
				break
		var gtrans := character_body.global_transform
		gtrans.origin = volume.get_global_transform() * offset_local_pos
		character_body.global_transform = gtrans
		character_body.velocity = Vector3.ZERO


func _process_actions():
	if _interact_cmd:
		_interact_cmd = false
		_interact()

	var character_body := _get_body()
	var hit := _raycast_terrain_from_mouse()
	var build_mode := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	if hit.is_empty() or not hit.collider is VoxelLodTerrain:
		_terrain_cursor.hide_cursor()
		return

	_terrain_cursor.show_at(hit.position, hit.normal, build_mode)

	var volume : VoxelLodTerrain = hit.collider
	var hit_position : Vector3 = hit.position

	if _dig_cmd:
		_dig_cmd = false
		var vt : VoxelToolLodTerrain = volume.get_voxel_tool()
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
		DDD.draw_box_aabb(splitter_aabb, Color(0,1,0), 60)

	if _build_cmd:
		_build_cmd = false
		var vt : VoxelTool = volume.get_voxel_tool()
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
		var waypoint : Waypoint = WaypointScene.instantiate()
		waypoint.transform = Transform3D(character_body.transform.basis, hit_position)
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
	ray_query.exclude = [_get_body().get_rid()]
	return _get_body().get_world_3d().direct_space_state.intersect_ray(ray_query)


func _unhandled_input(event: InputEvent):
	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			match event.keycode:
				KEY_SPACE:
					var body := _get_body()
					body.jump()
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


func _interact():
	var character_body := _get_body()
	var space_state := character_body.get_world_3d().direct_space_state
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
			var ship : Ship = Util.find_parent_by_type(hit.collider, Ship)
			if ship != null:
				_enter_ship(ship)


func _enter_ship(ship: Ship):
	var solar_system := _get_solar_system()
	if solar_system != null:
		solar_system.set_character_control_mode(false)
	var camera = get_viewport().get_camera_3d()
	camera.set_target(ship)
	ship.enable_controller()
	_get_body().queue_free()


func _process(delta: float):
	var character_body := _get_body()
	var gtrans := character_body.global_transform
	var up := gtrans.basis.y

	_sync_head_to_camera(up)

	# We want to rotate only along local Y
	var head_basis := _head.global_transform.basis
	var forward_projected := get_flat_forward_not_normalized(head_basis, up)
	
	# Visual can be offset.
	# We need global transfotm tho cuz look_at wants a global position
	gtrans.origin = _visual_root.global_transform.origin
	
	var old_root_basis := _visual_root.transform.basis.orthonormalized()
	_visual_root.transform.basis = old_root_basis
	_visual_root.look_at(gtrans.origin + forward_projected, up)
	_visual_root.transform.basis = old_root_basis.slerp(_visual_root.transform.basis, delta * 8.0)
	
	# TODO Temporarily removed Mannequinny, it did not port well to Godot4
	#_process_visual_animated(forward, character_body)
	
	_visual_head.global_transform.basis = head_basis


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
	var character_body := _get_body()
	var ref_body := solar_system.get_reference_stellar_body()
	if ref_body.type == StellarBody.TYPE_ROCKY and ref_body.volume != null:
		return ref_body
	var closest: StellarBody = null
	var closest_d := INF
	for i in solar_system.get_stellar_body_count():
		var b: StellarBody = solar_system.get_stellar_body(i)
		if b.type != StellarBody.TYPE_ROCKY or b.volume == null:
			continue
		var d := b.node.global_transform.origin.distance_to(character_body.global_position)
		if d < b.radius * 4.0 and d < closest_d:
			closest = b
			closest_d = d
	return closest


func _get_body() -> OrbitalCharacter:
	return get_parent() as OrbitalCharacter


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


# Gets a vector pointing forwards from the specified basis, projected along the ground plane with specified normal.
# That vector's direction is unaffected by the vertical angle of the basis relative to the ground plane,
# so it may be used to orient a character's body based on its head rotation.
static func get_flat_forward_not_normalized(basis: Basis, ground_up: Vector3) -> Vector3:
	var plane := Plane(ground_up, 0)
	var forward_projected := plane.project(-basis.z)
	# Godot math functions are very sensitive so we have to handle fallbacks otherwise we get lots of warnings
	if forward_projected.length_squared() < 0.01:
		if basis.z.dot(ground_up) > 0:
			# Looking down (z points back)
			forward_projected = plane.project(basis.y)
		else:
			# Looking up
			forward_projected = plane.project(-basis.y)
	# Output is not normalized because it is not always necessary depending on usage
	return forward_projected
