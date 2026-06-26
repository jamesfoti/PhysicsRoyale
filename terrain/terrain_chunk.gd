class_name TerrainChunkV2
extends MeshInstance3D
## One meshed chunk. Rebuilds from density when settings change.


var chunk_coord: Vector3i = Vector3i.ZERO


func rebuild(settings: TerrainWorldV2.SettingsSnapshot, edge_world_cache: Dictionary = {}) -> void:
	var build: ChunkMeshBuilder.ChunkBuildResult = ChunkMeshBuilder.build_chunk(
		chunk_coord,
		settings,
		edge_world_cache
	)
	apply_build_result(build, settings.rebuild_collision)


func apply_build_result(build: ChunkMeshBuilder.ChunkBuildResult, rebuild_collision: bool) -> void:
	mesh = FlyingEdgesMesher.to_array_mesh(build.mesh_result)
	position = build.local_position
	if rebuild_collision and mesh.get_surface_count() > 0:
		_create_trimesh_collision()


func update_collision() -> void:
	if mesh != null and mesh.get_surface_count() > 0:
		_create_trimesh_collision()


func _create_trimesh_collision() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
