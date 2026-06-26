class_name SignedDensityField
extends RefCounted
## 3D grid of signed density samples. Negative = inside, positive = outside.
## Grid dimensions are sample counts (cells + 1 along each axis).

var size: Vector3i = Vector3i.ZERO
var values: PackedFloat32Array = PackedFloat32Array()


func _init(sample_size: Vector3i = Vector3i.ZERO) -> void:
	if sample_size != Vector3i.ZERO:
		resize(sample_size)


func resize(sample_size: Vector3i) -> void:
	size = sample_size
	var count := size.x * size.y * size.z
	values.resize(count)
	values.fill(1.0)


func is_valid() -> bool:
	return size.x > 1 and size.y > 1 and size.z > 1


func cell_counts() -> Vector3i:
	return size - Vector3i.ONE


func _index(x: int, y: int, z: int) -> int:
	return x + y * size.x + z * size.x * size.y


func in_bounds(x: int, y: int, z: int) -> bool:
	return x >= 0 and y >= 0 and z >= 0 and x < size.x and y < size.y and z < size.z


func get_sample(x: int, y: int, z: int) -> float:
	return values[_index(x, y, z)]


func set_sample(x: int, y: int, z: int, value: float) -> void:
	values[_index(x, y, z)] = value


func sample_world(world_pos: Vector3, origin: Vector3, voxel_size: float) -> float:
	var local := (world_pos - origin) / voxel_size
	var fx := local.x
	var fy := local.y
	var fz := local.z
	if fx < 0.0 or fy < 0.0 or fz < 0.0:
		return 1.0
	if fx > float(size.x - 1) or fy > float(size.y - 1) or fz > float(size.z - 1):
		return 1.0
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var z0 := int(floor(fz))
	var x1 := mini(x0 + 1, size.x - 1)
	var y1 := mini(y0 + 1, size.y - 1)
	var z1 := mini(z0 + 1, size.z - 1)
	var tx := fx - float(x0)
	var ty := fy - float(y0)
	var tz := fz - float(z0)
	var c000 := get_sample(x0, y0, z0)
	var c100 := get_sample(x1, y0, z0)
	var c010 := get_sample(x0, y1, z0)
	var c110 := get_sample(x1, y1, z0)
	var c001 := get_sample(x0, y0, z1)
	var c101 := get_sample(x1, y0, z1)
	var c011 := get_sample(x0, y1, z1)
	var c111 := get_sample(x1, y1, z1)
	var c00 := lerpf(c000, c100, tx)
	var c10 := lerpf(c010, c110, tx)
	var c01 := lerpf(c001, c101, tx)
	var c11 := lerpf(c011, c111, tx)
	var c0 := lerpf(c00, c10, ty)
	var c1 := lerpf(c01, c11, ty)
	return lerpf(c0, c1, tz)
