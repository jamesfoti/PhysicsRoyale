@tool
class_name TerrainWorldV2
extends Node3D
## Pure-GDScript chunked terrain for browser-friendly testing.

const _CHUNK_SCRIPT = preload("res://terrain/terrain_chunk.gd")
const RECOMMENDED_RAVINE_DEPTH := 12.0
const RECOMMENDED_RAVINE_WIDTH := 0.08


class SettingsSnapshot:
	var chunks_x: int = 3
	var chunks_y: int = 3
	var chunks_z: int = 3
	var cells_per_axis: int = 12
	var voxel_size: float = 1.0
	var iso_level: float = 0.0
	var world_origin: Vector3 = Vector3.ZERO
	var sphere_enabled: bool = true
	var sphere_center: Vector3 = Vector3.ZERO
	var sphere_radius: float = 18.0
	var planet_radius_chunks: float = 1.5
	var chunk_world_size: float = 12.0
	var chunk_resolution: int = 1
	var noise_enabled: bool = true
	var noise_seed: int = 42
	var noise_frequency: float = 0.08
	var noise_amplitude: float = 3.0
	var noise_octaves: int = 3
	var noise_lacunarity: float = 2.0
	var noise_gain: float = 0.5
	var generate_collision: bool = true
	var material: Material = null
	var bounds_center: Vector3 = Vector3.ZERO
	var bounds_half: Vector3 = Vector3.ZERO
	var bounds_falloff_enabled: bool = true
	var bounds_falloff_distance: float = 8.0
	var bounds_falloff_strength: float = 5.0
	var bounds_clip_inset: float = 0.5
	var planet_features_enabled: bool = false
	var planet_ravines_enabled: bool = true
	var planet_caves_enabled: bool = true
	var planet_ravine_depth: float = RECOMMENDED_RAVINE_DEPTH
	var planet_ravine_width: float = RECOMMENDED_RAVINE_WIDTH
	var terrain_edits: TerrainEdits = null
	var rebuild_collision: bool = true


@export_group("Planet Grid")
## Planet radius in chunk units. World radius = this × chunk_size (e.g. 1.5 × 12 = 18).
@export_range(0.5, 32.0, 0.1, "or_greater") var planet_radius_chunks: float = 1.5:
	set(value):
		planet_radius_chunks = maxf(value, 0.5)
		_request_rebuild()
## World-space edge length of each chunk cube (same on X, Y, and Z).
@export_range(1.0, 128.0, 0.5, "or_greater") var chunk_size: float = 12.0:
	set(value):
		chunk_size = maxf(value, 1.0)
		_request_rebuild()
## Resolution multiplier for voxel detail only. Voxels/axis = round(chunk_size) × resolution; voxel size shrinks, chunk world size stays fixed.
@export_range(1, 16, 1) var chunk_resolution: int = 1:
	set(value):
		chunk_resolution = maxi(value, 1)
		_request_rebuild()

@export_group("Sphere")
@export var sphere_enabled: bool = true:
	set(value):
		sphere_enabled = value
		_request_rebuild()
@export var sphere_center: Vector3 = Vector3.ZERO:
	set(value):
		sphere_center = value
		_request_rebuild()

@export_group("Noise")
@export var noise_enabled: bool = true:
	set(value):
		noise_enabled = value
		_request_rebuild()
@export var noise_seed: int = 42:
	set(value):
		noise_seed = value
		_request_rebuild()
@export var noise_frequency: float = 0.08:
	set(value):
		noise_frequency = maxf(value, 0.001)
		_request_rebuild()
@export var noise_amplitude: float = 3.0:
	set(value):
		noise_amplitude = value
		_request_rebuild()
@export_range(1, 8, 1) var noise_octaves: int = 3:
	set(value):
		noise_octaves = value
		_request_rebuild()
@export var noise_lacunarity: float = 2.0:
	set(value):
		noise_lacunarity = maxf(value, 1.0)
		_request_rebuild()
@export var noise_gain: float = 0.5:
	set(value):
		noise_gain = clampf(value, 0.01, 1.0)
		_request_rebuild()

@export_group("Meshing")
@export var iso_level: float = 0.0:
	set(value):
		iso_level = value
		_request_rebuild()
@export var generate_collision: bool = true:
	set(value):
		generate_collision = value
		_request_rebuild()
@export var terrain_material: Material

@export_group("Bounds")
@export var bounds_falloff_enabled: bool = true:
	set(value):
		bounds_falloff_enabled = value
		_request_rebuild()
@export var bounds_falloff_distance: float = 8.0:
	set(value):
		bounds_falloff_distance = maxf(value, 0.0)
		_request_rebuild()
@export var bounds_falloff_strength: float = 5.0:
	set(value):
		bounds_falloff_strength = maxf(value, 0.0)
		_request_rebuild()

@export_group("Planet Features")
## Use planet density (auto surface noise, ravines, caves). Enable this before tuning ravine sliders.
@export var planet_features_enabled: bool = false:
	set(value):
		planet_features_enabled = value
		_request_rebuild()
## Radial grooves carved into the sphere. Requires Planet Features.
@export var planet_ravines_enabled: bool = true:
	set(value):
		planet_ravines_enabled = value
		_request_rebuild()
## Near-surface cave pockets via smooth SDF subtract. Requires Planet Features.
@export var planet_caves_enabled: bool = true:
	set(value):
		planet_caves_enabled = value
		_request_rebuild()
## Ravine carve depth (world units). Recommended: ~1× chunk_size for radius ~1.5 chunks, ~100 at radius 1600. -1 = auto from radius.
@export_range(-1, 100.0, 0.5, "or_greater") var planet_ravine_depth: float = RECOMMENDED_RAVINE_DEPTH:
	get:
		return _planet_ravine_depth
	set(value):
		_planet_ravine_depth = (
			RECOMMENDED_RAVINE_DEPTH if value == null else float(value)
		)
		_request_rebuild()
## Ravine groove width (noise valley threshold). Higher = wider. Recommended: 0.08 for small planets, ~0.002 at radius 1600. -1 = auto from radius.
@export_range(-1, 0.5, 0.005, "or_greater") var planet_ravine_width: float = RECOMMENDED_RAVINE_WIDTH:
	get:
		return _planet_ravine_width
	set(value):
		_planet_ravine_width = (
			RECOMMENDED_RAVINE_WIDTH if value == null else float(value)
		)
		_request_rebuild()

@export_group("Runtime")
## When false (e.g. decorative sun mesh), this world is excluded from spawn and editing queries.
@export var is_playable_planet: bool = true
@export var rebuild_on_ready: bool = true
@export var auto_rebuild_in_editor: bool = false
@export var use_threaded_rebuild: bool = true
@export_range(1, 8, 1) var max_concurrent_rebuild_tasks: int = 4

var _chunks: Dictionary = {}
var _rebuild_queued := false
var _planet_ravine_depth: float = RECOMMENDED_RAVINE_DEPTH
var _planet_ravine_width: float = RECOMMENDED_RAVINE_WIDTH
var _edits: TerrainEdits = TerrainEdits.new()
var _dirty_chunks: Dictionary = {}
var _chunk_flush_pending: bool = false
var _continuous_edit_depth: int = 0
var _bake_density: DensitySampler.WorldDensity
var _pending_rebuild_coords: Dictionary = {}
var _pending_rebuild_collision: bool = false
var _async_rebuild_requested: bool = false
var _async_jobs: Dictionary = {}
var _running_async_tasks: int = 0
var _inflight_coords: Dictionary = {}
var _runtime_shader_material: ShaderMaterial


func _ready() -> void:
	_ensure_export_defaults()
	if is_playable_planet:
		add_to_group("terrain_world")
		add_to_group("planet")
	if rebuild_on_ready and not Engine.is_editor_hint():
		call_deferred("rebuild_all")
	elif terrain_material != null:
		_refresh_shader_material_uniforms()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED and _runtime_shader_material != null:
		_sync_terrain_shader_uniforms(_runtime_shader_material)


func _process(_delta: float) -> void:
	_poll_async_rebuilds()
	if _async_rebuild_requested:
		_async_rebuild_requested = false
		_dispatch_pending_rebuilds()


func _ensure_export_defaults() -> void:
	# Scenes saved before planet ravine exports were added can deserialize them as null.
	if get("planet_ravine_depth") == null:
		_planet_ravine_depth = RECOMMENDED_RAVINE_DEPTH
	if get("planet_ravine_width") == null:
		_planet_ravine_width = RECOMMENDED_RAVINE_WIDTH


func destroy_all() -> void:
	_clear_chunks()
	if Engine.is_editor_hint():
		print("[TerrainWorldV2] Destroyed terrain (editor)")


func rebuild_all() -> void:
	_invalidate_bake_density()
	_ensure_export_defaults()
	_clear_chunks()
	var settings := _make_settings_snapshot()
	var grid_chunks := _grid_chunks_per_axis()
	_rebuild_all_sync(settings, grid_chunks)


func _rebuild_all_sync(settings: SettingsSnapshot, grid_chunks: int) -> void:
	var edge_world_cache: Dictionary = {}
	var t0: int = Time.get_ticks_msec()
	for cz: int in grid_chunks:
		for cy: int in grid_chunks:
			for cx: int in grid_chunks:
				var coord := Vector3i(cx, cy, cz)
				_build_chunk_at(coord, settings, edge_world_cache)
	var elapsed: int = Time.get_ticks_msec() - t0
	_log_rebuild_complete(_chunks.size(), settings, grid_chunks, elapsed)


func _build_chunk_at(
	coord: Vector3i,
	settings: SettingsSnapshot,
	edge_world_cache: Dictionary
) -> void:
	var chunk: TerrainChunkV2 = _CHUNK_SCRIPT.new()
	chunk.name = "Chunk_%d_%d_%d" % [coord.x, coord.y, coord.z]
	chunk.chunk_coord = coord
	if not is_playable_planet:
		chunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(chunk)
	chunk.rebuild(settings, edge_world_cache)
	if settings.material != null:
		chunk.material_override = settings.material
	_register_editor_scene_node(chunk)
	_chunks[coord] = chunk


func _log_rebuild_complete(
	chunk_count: int,
	settings: SettingsSnapshot,
	grid_chunks: int,
	elapsed_ms: int
) -> void:
	print(
		"[TerrainWorldV2] Rebuilt ",
		chunk_count,
		" chunks (",
		settings.cells_per_axis,
		" cells/axis, ",
		grid_chunks,
		"^3 grid) in ",
		elapsed_ms,
		" ms"
	)


func get_chunk_count() -> int:
	return _chunks.size()


func get_total_vertex_count() -> int:
	var total: int = 0
	for coord_variant: Variant in _chunks.keys():
		var chunk: TerrainChunkV2 = _chunks[coord_variant] as TerrainChunkV2
		if chunk == null or chunk.mesh == null:
			continue
		var array_mesh: ArrayMesh = chunk.mesh as ArrayMesh
		if array_mesh == null:
			continue
		for surface_idx: int in array_mesh.get_surface_count():
			total += array_mesh.surface_get_array_len(surface_idx)
	return total


func get_total_triangle_count() -> int:
	var total_indices: int = 0
	for coord_variant: Variant in _chunks.keys():
		var chunk: TerrainChunkV2 = _chunks[coord_variant] as TerrainChunkV2
		if chunk == null or chunk.mesh == null:
			continue
		var array_mesh: ArrayMesh = chunk.mesh as ArrayMesh
		if array_mesh == null:
			continue
		for surface_idx: int in array_mesh.get_surface_count():
			total_indices += array_mesh.surface_get_array_index_len(surface_idx)
	return int(total_indices / 3)


func get_edited_voxel_count() -> int:
	return _edits.get_override_count()


func get_grid_chunks_per_axis() -> int:
	return _grid_chunks_per_axis()


func get_base_cells_per_axis() -> int:
	return maxi(1, int(round(chunk_size)))


func get_cells_per_axis() -> int:
	return get_base_cells_per_axis() * chunk_resolution


func get_voxels_per_chunk() -> int:
	var cells := get_cells_per_axis()
	return cells * cells * cells


func get_chunk_world_extent() -> float:
	return chunk_size


func get_world_step() -> float:
	return chunk_size / float(get_cells_per_axis())


func get_voxel_size() -> float:
	return get_world_step()


func get_sphere_radius() -> float:
	return planet_radius_chunks * chunk_size


func get_planet_center_world() -> Vector3:
	return global_position + sphere_center


func get_world_extents() -> Vector3:
	return Vector3.ONE * float(_grid_chunks_per_axis()) * chunk_size


func get_settings_snapshot() -> SettingsSnapshot:
	return _make_settings_snapshot()


func get_terrain_edits() -> TerrainEdits:
	return _edits


func begin_continuous_edit() -> void:
	_continuous_edit_depth += 1


func end_continuous_edit() -> void:
	_continuous_edit_depth = maxi(_continuous_edit_depth - 1, 0)
	if _continuous_edit_depth > 0:
		return
	_chunk_flush_pending = false
	if not _pending_rebuild_coords.is_empty():
		_dispatch_pending_rebuilds()


func apply_brush(world_position: Vector3, radius: float, add_solid: bool) -> void:
	_edits.set_voxel_size(get_voxel_size())
	var procedural := Callable(_get_bake_density(), "evaluate")
	_edits.add_brush(world_position, radius, add_solid, procedural)
	var coords: Array[Vector3i] = _get_chunk_coords_intersecting_sphere(world_position, radius)
	for coord: Vector3i in coords:
		_pending_rebuild_coords[coord] = true
	_pending_rebuild_collision = true
	_dispatch_pending_rebuilds()


func get_grid_origin_local() -> Vector3:
	return -get_world_extents() * 0.5


func _grid_chunks_per_axis() -> int:
	# Cubic grid sized to fit the planet plus one chunk of padding for noise and bounds falloff.
	return maxi(3, int(ceil(planet_radius_chunks * 2.0 + 2.0)))


func _make_settings_snapshot() -> SettingsSnapshot:
	var settings := SettingsSnapshot.new()
	var grid_chunks := _grid_chunks_per_axis()
	var world_step := get_world_step()
	var radius := get_sphere_radius()
	settings.chunks_x = grid_chunks
	settings.chunks_y = grid_chunks
	settings.chunks_z = grid_chunks
	settings.cells_per_axis = get_cells_per_axis()
	settings.voxel_size = world_step
	settings.bounds_clip_inset = maxf(chunk_size * 0.05, 0.25)
	settings.planet_radius_chunks = planet_radius_chunks
	settings.chunk_world_size = chunk_size
	settings.chunk_resolution = chunk_resolution
	settings.iso_level = iso_level
	settings.world_origin = global_position
	settings.sphere_enabled = sphere_enabled
	settings.sphere_center = sphere_center
	settings.sphere_radius = radius
	settings.noise_enabled = noise_enabled
	settings.noise_seed = noise_seed
	settings.noise_frequency = noise_frequency
	settings.noise_amplitude = noise_amplitude
	settings.noise_octaves = noise_octaves
	settings.noise_lacunarity = noise_lacunarity
	settings.noise_gain = noise_gain
	settings.generate_collision = generate_collision
	settings.material = _effective_material()
	settings.bounds_center = global_position
	settings.bounds_half = get_world_extents() * 0.5
	settings.bounds_falloff_enabled = bounds_falloff_enabled
	settings.bounds_falloff_distance = bounds_falloff_distance
	settings.bounds_falloff_strength = bounds_falloff_strength
	settings.planet_features_enabled = planet_features_enabled
	settings.planet_ravines_enabled = planet_ravines_enabled
	settings.planet_caves_enabled = planet_caves_enabled
	settings.planet_ravine_depth = _planet_ravine_depth
	settings.planet_ravine_width = _planet_ravine_width
	settings.terrain_edits = _edits
	settings.rebuild_collision = settings.generate_collision
	return settings


func _resolved_planet_ravine_depth() -> float:
	return _planet_ravine_depth


func _clear_chunks() -> void:
	for child in get_children():
		if not child is _CHUNK_SCRIPT:
			continue
		remove_child(child)
		if Engine.is_editor_hint():
			child.free()
		else:
			child.queue_free()
	_chunks.clear()


func _request_rebuild() -> void:
	if not is_node_ready():
		return
	if Engine.is_editor_hint() and not auto_rebuild_in_editor:
		return
	if _rebuild_queued:
		return
	_rebuild_queued = true
	call_deferred("_deferred_rebuild")


func _deferred_rebuild() -> void:
	_rebuild_queued = false
	rebuild_all()


func _use_threaded_rebuild() -> bool:
	return use_threaded_rebuild and not Engine.is_editor_hint()


func _dispatch_pending_rebuilds() -> void:
	if _pending_rebuild_coords.is_empty():
		return
	var rebuild_collision: bool = _pending_rebuild_collision
	if rebuild_collision:
		_pending_rebuild_collision = false
	var deferred: Array[Vector3i] = []
	for coord_variant: Variant in _pending_rebuild_coords.keys():
		var coord: Vector3i = coord_variant as Vector3i
		if _inflight_coords.has(coord):
			deferred.append(coord)
			continue
		if _running_async_tasks >= max_concurrent_rebuild_tasks:
			deferred.append(coord)
			continue
		_pending_rebuild_coords.erase(coord)
		_start_single_chunk_async_rebuild(coord, rebuild_collision)
	for coord: Vector3i in deferred:
		_pending_rebuild_coords[coord] = true
	if rebuild_collision and not deferred.is_empty():
		_pending_rebuild_collision = true


func _rebuild_coords(coords: Array[Vector3i], rebuild_collision: bool) -> void:
	if coords.is_empty():
		return
	if _use_threaded_rebuild():
		for coord: Vector3i in coords:
			_pending_rebuild_coords[coord] = true
		if rebuild_collision:
			_pending_rebuild_collision = true
		_dispatch_pending_rebuilds()
	else:
		var settings := _make_settings_snapshot()
		settings.rebuild_collision = settings.generate_collision and rebuild_collision
		_rebuild_chunk_coords(coords, settings)


func _start_single_chunk_async_rebuild(coord: Vector3i, rebuild_collision: bool) -> void:
	_inflight_coords[coord] = true
	var job := ChunkMeshBuilder.AsyncRebuildJob.new()
	job.coords = [coord]
	job.rebuild_collision = rebuild_collision
	job.settings = _make_thread_settings_snapshot()
	job.task_id = WorkerThreadPool.add_task(ChunkMeshBuilder.run_async_job.bind(job))
	_async_jobs[job.task_id] = job
	_running_async_tasks += 1


func _start_async_rebuild(coords: Array[Vector3i], rebuild_collision: bool) -> void:
	for coord: Vector3i in coords:
		_pending_rebuild_coords[coord] = true
	if rebuild_collision:
		_pending_rebuild_collision = true
	_dispatch_pending_rebuilds()


func _poll_async_rebuilds() -> void:
	if not _async_jobs.is_empty():
		var completed: Array[int] = []
		for task_id_variant: Variant in _async_jobs.keys():
			var task_id: int = task_id_variant as int
			if WorkerThreadPool.is_task_completed(task_id):
				completed.append(task_id)
		for task_id: int in completed:
			var job: ChunkMeshBuilder.AsyncRebuildJob = _async_jobs[task_id] as ChunkMeshBuilder.AsyncRebuildJob
			_async_jobs.erase(task_id)
			WorkerThreadPool.wait_for_task_completion(task_id)
			_running_async_tasks = maxi(_running_async_tasks - 1, 0)
			_apply_async_job(job)
	if (
		_running_async_tasks < max_concurrent_rebuild_tasks
		and not _pending_rebuild_coords.is_empty()
	):
		_dispatch_pending_rebuilds()


func _apply_async_job(job: ChunkMeshBuilder.AsyncRebuildJob) -> void:
	for coord: Vector3i in job.coords:
		_inflight_coords.erase(coord)
		var chunk: TerrainChunkV2 = _chunks.get(coord) as TerrainChunkV2
		if chunk == null:
			continue
		var build: ChunkMeshBuilder.ChunkBuildResult = (
			job.batch_result.chunks.get(coord) as ChunkMeshBuilder.ChunkBuildResult
		)
		if build == null:
			continue
		chunk.apply_build_result(build, generate_collision)
		if _effective_material() != null:
			chunk.material_override = _effective_material()


func _make_thread_settings_snapshot() -> SettingsSnapshot:
	var settings := _make_settings_snapshot()
	if settings.terrain_edits != null:
		settings.terrain_edits = settings.terrain_edits.duplicate_for_thread()
	return settings


func _queue_dirty_chunk_rebuild(force_collision: bool) -> void:
	if _chunk_flush_pending:
		if force_collision:
			call_deferred("_flush_dirty_chunks", true)
		return
	_chunk_flush_pending = true
	call_deferred("_flush_dirty_chunks", force_collision)


func _flush_dirty_chunks(force_collision: bool) -> void:
	_chunk_flush_pending = false
	if _dirty_chunks.is_empty():
		return
	var coords: Array[Vector3i] = []
	for coord_variant: Variant in _dirty_chunks.keys():
		coords.append(coord_variant as Vector3i)
	_dirty_chunks.clear()
	_rebuild_coords(coords, force_collision)


func _build_world_density(settings: SettingsSnapshot) -> DensitySampler.WorldDensity:
	var sphere_world: Vector3 = settings.bounds_center + settings.sphere_center
	if settings.planet_features_enabled and settings.sphere_enabled:
		return DensitySampler.create_planet_world_density(
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
	return DensitySampler.WorldDensity.create(
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


func _invalidate_bake_density() -> void:
	_bake_density = null


func _get_bake_density() -> DensitySampler.WorldDensity:
	if _bake_density == null:
		_bake_density = _build_world_density(_make_settings_snapshot())
	return _bake_density


func _rebuild_chunk_coords(
	coords: Array[Vector3i],
	settings: SettingsSnapshot = null
) -> void:
	if coords.is_empty():
		return
	if settings == null:
		settings = _make_settings_snapshot()
	var edge_world_cache: Dictionary = {}
	for coord: Vector3i in coords:
		var chunk: TerrainChunkV2 = _chunks.get(coord) as TerrainChunkV2
		if chunk == null:
			continue
		chunk.rebuild(settings, edge_world_cache)
		if settings.material != null:
			chunk.material_override = settings.material


func _get_chunk_coords_intersecting_sphere(center: Vector3, radius: float) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	var settings := _make_settings_snapshot()
	var padding: float = get_voxel_size() * 2.0
	var search_aabb := AABB(
		center - Vector3.ONE * (radius + padding),
		Vector3.ONE * (radius + padding) * 2.0
	)
	for coord_variant: Variant in _chunks.keys():
		var coord: Vector3i = coord_variant as Vector3i
		if _get_chunk_world_aabb(coord, settings).intersects(search_aabb):
			result.append(coord)
	return result


func _get_chunk_world_aabb(coord: Vector3i, settings: SettingsSnapshot) -> AABB:
	var extent: float = settings.chunk_world_size
	var corner_local: Vector3 = _chunk_corner_local(coord, settings)
	var world_corner: Vector3 = global_position + corner_local
	return AABB(world_corner, Vector3.ONE * extent)


func _chunk_corner_local(coord: Vector3i, settings: SettingsSnapshot) -> Vector3:
	var extent: float = settings.chunk_world_size
	var grid_origin: Vector3 = (
		-Vector3(settings.chunks_x, settings.chunks_y, settings.chunks_z)
		* extent
		* 0.5
	)
	return grid_origin + Vector3(coord) * extent


func _effective_material() -> Material:
	return _refresh_shader_material_uniforms()


func _refresh_shader_material_uniforms() -> Material:
	if terrain_material == null:
		return null
	var source: ShaderMaterial = terrain_material as ShaderMaterial
	if source == null or source.shader == null:
		return terrain_material
	if source.shader.resource_path != "res://shaders/terrain_spherical.gdshader":
		return terrain_material
	if _runtime_shader_material == null:
		_runtime_shader_material = source.duplicate() as ShaderMaterial
	_sync_terrain_shader_uniforms(_runtime_shader_material)
	return _runtime_shader_material


func _sync_terrain_shader_uniforms(mat: Material) -> void:
	var sm: ShaderMaterial = mat as ShaderMaterial
	if sm == null or sm.shader == null:
		return
	if sm.shader.resource_path != "res://shaders/terrain_spherical.gdshader":
		return
	sm.set_shader_parameter("planet_center", get_planet_center_world())
	sm.set_shader_parameter("planet_radius", get_sphere_radius())


func _register_editor_scene_node(node: Node) -> void:
	if not Engine.is_editor_hint():
		return
	var scene_root := get_tree().edited_scene_root
	if scene_root == null:
		return
	_assign_scene_owner(node, scene_root)


func _assign_scene_owner(node: Node, scene_root: Node) -> void:
	if node != scene_root:
		node.owner = scene_root
	for child in node.get_children():
		_assign_scene_owner(child, scene_root)
