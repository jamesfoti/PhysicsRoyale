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
@export var rebuild_on_ready: bool = true
@export var auto_rebuild_in_editor: bool = false

var _chunks: Dictionary = {}
var _rebuild_queued := false
var _planet_ravine_depth: float = RECOMMENDED_RAVINE_DEPTH
var _planet_ravine_width: float = RECOMMENDED_RAVINE_WIDTH
var _edits: TerrainEdits = TerrainEdits.new()


func _ready() -> void:
	_ensure_export_defaults()
	add_to_group("terrain_world")
	if rebuild_on_ready and not Engine.is_editor_hint():
		rebuild_all()


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
	_ensure_export_defaults()
	_clear_chunks()
	var settings := _make_settings_snapshot()
	var grid_chunks := _grid_chunks_per_axis()
	var edge_world_cache: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	for cz in grid_chunks:
		for cy in grid_chunks:
			for cx in grid_chunks:
				var coord := Vector3i(cx, cy, cz)
				var chunk := _CHUNK_SCRIPT.new()
				chunk.name = "Chunk_%d_%d_%d" % [cx, cy, cz]
				chunk.chunk_coord = coord
				add_child(chunk)
				chunk.rebuild(settings, edge_world_cache)
				if settings.material != null:
					chunk.material_override = settings.material
				_register_editor_scene_node(chunk)
				_chunks[coord] = chunk
	var elapsed := Time.get_ticks_msec() - t0
	print(
		"[TerrainWorldV2] Rebuilt ",
		_chunks.size(),
		" chunks (",
		settings.cells_per_axis,
		" cells/axis, ",
		grid_chunks,
		"^3 grid) in ",
		elapsed,
		" ms"
	)


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


func get_world_extents() -> Vector3:
	return Vector3.ONE * float(_grid_chunks_per_axis()) * chunk_size


func get_settings_snapshot() -> SettingsSnapshot:
	return _make_settings_snapshot()


func get_terrain_edits() -> TerrainEdits:
	return _edits


func apply_brush(world_position: Vector3, radius: float, add_solid: bool) -> void:
	_edits.add_brush(world_position, radius, add_solid)
	var coords: Array[Vector3i] = _get_chunk_coords_intersecting_sphere(world_position, radius)
	_rebuild_chunk_coords(coords)


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
	settings.material = terrain_material
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


func _rebuild_chunk_coords(coords: Array[Vector3i]) -> void:
	if coords.is_empty():
		return
	var settings := _make_settings_snapshot()
	var edge_world_cache: Dictionary = {}
	var t0 := Time.get_ticks_msec()
	for coord: Vector3i in coords:
		var chunk: TerrainChunkV2 = _chunks.get(coord) as TerrainChunkV2
		if chunk == null:
			continue
		chunk.rebuild(settings, edge_world_cache)
		if settings.material != null:
			chunk.material_override = settings.material
	var elapsed := Time.get_ticks_msec() - t0
	print("[TerrainWorldV2] Rebuilt ", coords.size(), " chunk(s) after edit in ", elapsed, " ms")


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
