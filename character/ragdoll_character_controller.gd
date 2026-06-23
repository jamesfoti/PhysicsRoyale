extends Node

const StellarBody = preload("../solar_system/stellar_body.gd")
const Ship = preload("../ship/ship.gd")
const Util = preload("../util/util.gd")
const CollisionLayers = preload("../collision_layers.gd")
const CharacterAudio = preload("./character_audio.gd")
const Waypoint = preload("res://waypoints/waypoint.gd")
const SplitChunkRigidBodyComponent = preload("../solar_system/split_chunk_rigidbody_component.gd")

const WaypointScene = preload("../waypoints/waypoint.tscn")

@onready var _flashlight: SpotLight3D = get_node("../Visual/FlashLight")
@onready var _audio: CharacterAudio = get_node("../Audio")
@onready var _ragdoll: Node3D = get_node("..")

var _dig_cmd := false
var _interact_cmd := false
var _build_cmd := false
var _waypoint_cmd := false


func _physics_process(_delta: float) -> void:
	_process_actions()
	_process_undig()


func _process_undig() -> void:
	var solar_system := _get_solar_system()
	if solar_system == null:
		return
	var landing_body: StellarBody = _ragdoll.get_landing_body()
	if landing_body == null or landing_body.volume == null:
		return
	var volume := landing_body.volume
	var vt: VoxelToolLodTerrain = volume.get_voxel_tool()
	var to_local := volume.global_transform.affine_inverse()
	var gtrans: Transform3D = _ragdoll.get_body_transform()
	var local_pos: Vector3 = to_local * gtrans.origin
	vt.channel = VoxelBuffer.CHANNEL_SDF
	var sdf := vt.get_voxel_f_interpolated(local_pos)
	DDD.set_text("SDF at feet", sdf)
	if sdf < -0.001:
		print("Character is buried, teleporting back to air")
		var up: Vector3 = local_pos.normalized()
		var offset_local_pos := local_pos
		for i in 10:
			offset_local_pos += 0.2 * up
			sdf = vt.get_voxel_f_interpolated(offset_local_pos)
			if sdf > 0.0005:
				break
		gtrans.origin = volume.get_global_transform() * offset_local_pos
		_ragdoll.global_transform = gtrans


func _process_actions() -> void:
	if _interact_cmd:
		_interact_cmd = false
		_interact()

	var camera := get_viewport().get_camera_3d()
	var front := -camera.global_transform.basis.z
	var cam_pos := camera.global_transform.origin
	var space_state := _ragdoll.get_world_3d().direct_space_state

	var ray_query := PhysicsRayQueryParameters3D.new()
	ray_query.from = cam_pos
	ray_query.to = cam_pos + front * 50.0
	ray_query.exclude = [_ragdoll.get_body_rid()]
	var hit = space_state.intersect_ray(ray_query)

	if not hit.is_empty():
		if hit.collider is VoxelLodTerrain:
			DDD.draw_box(hit.position, Vector3(0.5, 0.5, 0.5), Color(1, 1, 0))
			DDD.draw_ray_3d(hit.position, hit.normal, 1.0, Color(1, 1, 0))

	if not hit.is_empty() and hit.collider is VoxelLodTerrain:
		var volume: VoxelLodTerrain = hit.collider
		var hit_position: Vector3 = hit.position

		if _dig_cmd:
			_dig_cmd = false
			var vt: VoxelToolLodTerrain = volume.get_voxel_tool()
			var pos := volume.get_global_transform().affine_inverse() * hit_position
			vt.channel = VoxelBuffer.CHANNEL_SDF
			vt.mode = VoxelTool.MODE_REMOVE
			vt.do_sphere(pos, 3.5)
			_audio.play_dig(pos)

			var splitter_aabb := AABB(pos, Vector3()).grow(16.0)
			var bodies := vt.separate_floating_chunks(splitter_aabb, camera.get_parent())
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
			var planet: StellarBody = _ragdoll.get_landing_body()
			if planet == null:
				return
			var waypoint: Waypoint = WaypointScene.instantiate()
			var body_basis: Basis = _ragdoll.get_body_transform().basis
			waypoint.transform = Transform3D(body_basis, hit_position)
			planet.node.add_child(waypoint)
			planet.waypoints.append(waypoint)
			_audio.play_waypoint()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			match event.keycode:
				KEY_SPACE:
					pass
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
			if Input.is_key_pressed(KEY_SHIFT):
				return
			match event.button_index:
				MOUSE_BUTTON_LEFT:
					_dig_cmd = true
				MOUSE_BUTTON_RIGHT:
					_build_cmd = true


func _interact() -> void:
	var space_state := _ragdoll.get_world_3d().direct_space_state
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

	if not hit.is_empty() and hit.collider.name == "CommandPanel":
		var ship: Ship = Util.find_parent_by_type(hit.collider, Ship)
		if ship != null:
			_enter_ship(ship)


func _enter_ship(ship: Ship) -> void:
	var camera = get_viewport().get_camera_3d()
	camera.set_target(ship)
	ship.enable_controller()
	_ragdoll.stop_simulation()
	_ragdoll.queue_free()


func _get_solar_system() -> SolarSystem:
	var node := get_parent()
	while node != null:
		if node is SolarSystem:
			return node
		node = node.get_parent()
	return null
