class_name TerrainEdits
extends RefCounted
## Baked voxel density overrides. Negative density = solid.


var _voxel_size: float = 1.0
var _overrides: Dictionary = {}


func set_voxel_size(voxel_size: float) -> void:
	_voxel_size = maxf(voxel_size, 0.001)


func add_brush(
	world_position: Vector3,
	radius: float,
	add_solid: bool,
	procedural_density: Callable
) -> void:
	var brush_radius: float = maxf(radius, 0.1)
	var extent_voxels: int = int(ceil(brush_radius / _voxel_size)) + 1
	var center_key: Vector3i = position_to_key(world_position, _voxel_size)
	var radius_sq: float = brush_radius * brush_radius

	for dz: int in range(-extent_voxels, extent_voxels + 1):
		for dy: int in range(-extent_voxels, extent_voxels + 1):
			for dx: int in range(-extent_voxels, extent_voxels + 1):
				var key: Vector3i = center_key + Vector3i(dx, dy, dz)
				var sample_pos: Vector3 = key_to_position(key, _voxel_size)
				if sample_pos.distance_squared_to(world_position) > radius_sq:
					continue
				var value: float
				if _overrides.has(key):
					value = _overrides[key] as float
				else:
					value = procedural_density.call(sample_pos) as float
				var sphere_sdf: float = sample_pos.distance_to(world_position) - brush_radius
				var new_value: float
				if add_solid:
					new_value = minf(value, sphere_sdf)
				else:
					new_value = maxf(value, -sphere_sdf)
				if is_equal_approx(new_value, value):
					continue
				_overrides[key] = new_value


func apply_to_density(density: float, world_pos: Vector3) -> float:
	var key: Vector3i = position_to_key(world_pos, _voxel_size)
	if _overrides.has(key):
		return _overrides[key] as float
	return density


func get_override_count() -> int:
	return _overrides.size()


func duplicate_for_thread() -> TerrainEdits:
	var copy := TerrainEdits.new()
	copy._voxel_size = _voxel_size
	for key: Variant in _overrides.keys():
		copy._overrides[key] = _overrides[key]
	return copy


static func position_to_key(world_pos: Vector3, voxel_size: float) -> Vector3i:
	var inv: float = 1.0 / maxf(voxel_size, 0.001)
	return Vector3i(
		int(round(world_pos.x * inv)),
		int(round(world_pos.y * inv)),
		int(round(world_pos.z * inv))
	)


static func key_to_position(key: Vector3i, voxel_size: float) -> Vector3:
	return Vector3(key) * voxel_size
