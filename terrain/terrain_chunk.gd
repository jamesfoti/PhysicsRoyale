class_name TerrainChunkV2
extends MeshInstance3D
## One meshed chunk. Rebuilds from density when settings change.


var chunk_coord: Vector3i = Vector3i.ZERO


func rebuild(settings: TerrainWorldV2.SettingsSnapshot, edge_world_cache: Dictionary = {}) -> void:
	var cells := settings.cells_per_axis
	var extent := settings.chunk_world_size
	var sample_size := Vector3i.ONE * (cells + 1)
	var corner_local := _chunk_corner_local(settings)
	var half_extent := Vector3.ONE * extent * 0.5
	var world_corner := settings.world_origin + corner_local
	var world_center := world_corner + half_extent
	var grid_offset := Vector3i(
		chunk_coord.x * cells,
		chunk_coord.y * cells,
		chunk_coord.z * cells
	)
	var sphere_world := settings.bounds_center + settings.sphere_center
	var density: DensitySampler.WorldDensity
	if settings.planet_features_enabled and settings.sphere_enabled:
		density = DensitySampler.create_planet_world_density(
			sphere_world,
			settings.sphere_radius,
			settings.noise_seed,
			-1.0,
			-1.0,
			settings.planet_ravines_enabled,
			settings.planet_caves_enabled,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_falloff_enabled,
			settings.bounds_falloff_distance,
			settings.bounds_falloff_strength,
			settings.bounds_clip_inset,
			settings.planet_ravine_depth,
			settings.planet_ravine_width
		)
	else:
		density = DensitySampler.WorldDensity.create(
			settings.sphere_enabled,
			sphere_world,
			settings.sphere_radius,
			settings.noise_enabled,
			settings.noise_seed,
			settings.noise_frequency,
			settings.noise_amplitude,
			settings.noise_octaves,
			settings.noise_lacunarity,
			settings.noise_gain,
			settings.bounds_center,
			settings.bounds_half,
			settings.bounds_falloff_enabled,
			settings.bounds_falloff_distance,
			settings.bounds_falloff_strength,
			settings.bounds_clip_inset
		)
	var field := DensitySampler.build_chunk_field(
		density,
		sample_size,
		world_corner,
		extent
	)
	var mesh_result := FlyingEdgesMesher.build_mesh(
		field,
		extent,
		settings.iso_level,
		grid_offset,
		edge_world_cache,
		world_corner,
		world_center,
		density
	)
	mesh = FlyingEdgesMesher.to_array_mesh(mesh_result)
	position = corner_local + half_extent
	if settings.generate_collision and mesh.get_surface_count() > 0:
		_create_trimesh_collision()


func _chunk_corner_local(settings: TerrainWorldV2.SettingsSnapshot) -> Vector3:
	# Min-corner of this chunk in TerrainWorldV2 local space; grid is centered on the node origin.
	var extent := settings.chunk_world_size
	var grid_origin := (
		-Vector3(settings.chunks_x, settings.chunks_y, settings.chunks_z)
		* extent
		* 0.5
	)
	var chunk_offset := Vector3(chunk_coord) * extent
	return grid_origin + chunk_offset


func _create_trimesh_collision() -> void:
	for child in get_children():
		if child is StaticBody3D:
			child.queue_free()
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = mesh.create_trimesh_shape()
	body.add_child(shape)
	add_child(body)
