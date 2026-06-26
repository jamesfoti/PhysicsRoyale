class_name FlyingEdgesMesher
extends RefCounted
## Flying Edges-style mesher with per-chunk edge→vertex dedup and cross-chunk world-position cache.


class MeshResult:
	var vertices: PackedVector3Array = PackedVector3Array()
	var normals: PackedVector3Array = PackedVector3Array()
	var indices: PackedInt32Array = PackedInt32Array()


static func build_mesh(
	field: SignedDensityField,
	chunk_extent: float,
	iso_level: float = 0.0,
	grid_offset: Vector3i = Vector3i.ZERO,
	edge_world_cache: Dictionary = {},
	chunk_world_origin: Vector3 = Vector3.ZERO,
	chunk_world_center: Vector3 = Vector3.ZERO,
	density: DensitySampler.WorldDensity = null
) -> MeshResult:
	var result := MeshResult.new()
	if not field.is_valid():
		return result

	var cells := field.cell_counts()
	var world_step := chunk_extent / float(cells.x)
	var tri_table := FlyingEdgesTables.get_tri_table()
	var edge_vertex_cache: Dictionary = {}

	for z in cells.z:
		for y in cells.y:
			for x in cells.x:
				_process_cell(
					field,
					world_step,
					iso_level,
					grid_offset,
					edge_world_cache,
					edge_vertex_cache,
					chunk_world_origin,
					chunk_world_center,
					x,
					y,
					z,
					tri_table,
					result
				)

	if density != null:
		_compute_gradient_normals(result, density, chunk_world_center, world_step)
	else:
		_compute_face_normals(result)
	return result


static func to_array_mesh(mesh_result: MeshResult) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	if mesh_result.vertices.is_empty() or mesh_result.indices.is_empty():
		return mesh
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = mesh_result.vertices
	arrays[Mesh.ARRAY_NORMAL] = mesh_result.normals
	arrays[Mesh.ARRAY_INDEX] = mesh_result.indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func _process_cell(
	field: SignedDensityField,
	world_step: float,
	iso: float,
	grid_offset: Vector3i,
	edge_world_cache: Dictionary,
	edge_vertex_cache: Dictionary,
	chunk_world_origin: Vector3,
	chunk_world_center: Vector3,
	cx: int,
	cy: int,
	cz: int,
	tri_table: Array[PackedInt32Array],
	result: MeshResult
) -> void:
	var case_index := _case_index(field, iso, cx, cy, cz)
	if case_index == 0 or case_index == 255:
		return

	var edge_mask: int = FlyingEdgesTables.EDGE_TABLE[case_index]
	if edge_mask == 0:
		return

	var local_edges: PackedInt32Array = PackedInt32Array()
	local_edges.resize(12)
	for i in 12:
		local_edges[i] = -1

	for edge_id in 12:
		var bit: int = 1 << edge_id
		if (edge_mask & bit) == 0:
			continue
		local_edges[edge_id] = _create_edge_vertex(
			field,
			world_step,
			iso,
			grid_offset,
			edge_world_cache,
			edge_vertex_cache,
			chunk_world_origin,
			chunk_world_center,
			cx,
			cy,
			cz,
			edge_id,
			result.vertices
		)

	var row: PackedInt32Array = tri_table[case_index]
	var tri_i := 0
	while tri_i < row.size() and row[tri_i] != -1:
		var e0: int = row[tri_i]
		var e1: int = row[tri_i + 1]
		var e2: int = row[tri_i + 2]
		var i0: int = local_edges[e0]
		var i1: int = local_edges[e1]
		var i2: int = local_edges[e2]
		if i0 >= 0 and i1 >= 0 and i2 >= 0:
			# Paul Bourke tables wound for "inside = below iso"; flip for Godot CCW outward.
			result.indices.append_array([i0, i2, i1])
		tri_i += 3


static func _case_index(
	field: SignedDensityField,
	iso_level: float,
	x: int,
	y: int,
	z: int
) -> int:
	var case_index := 0
	if field.get_sample(x, y, z) < iso_level:
		case_index |= 1
	if field.get_sample(x + 1, y, z) < iso_level:
		case_index |= 2
	if field.get_sample(x + 1, y, z + 1) < iso_level:
		case_index |= 4
	if field.get_sample(x, y, z + 1) < iso_level:
		case_index |= 8
	if field.get_sample(x, y + 1, z) < iso_level:
		case_index |= 16
	if field.get_sample(x + 1, y + 1, z) < iso_level:
		case_index |= 32
	if field.get_sample(x + 1, y + 1, z + 1) < iso_level:
		case_index |= 64
	if field.get_sample(x, y + 1, z + 1) < iso_level:
		case_index |= 128
	return case_index


static func _create_edge_vertex(
	field: SignedDensityField,
	world_step: float,
	iso: float,
	grid_offset: Vector3i,
	edge_world_cache: Dictionary,
	edge_vertex_cache: Dictionary,
	chunk_world_origin: Vector3,
	chunk_world_center: Vector3,
	cx: int,
	cy: int,
	cz: int,
	edge_id: int,
	vertices: PackedVector3Array
) -> int:
	var cache_key := _edge_cache_key(grid_offset, cx, cy, cz, edge_id)
	if edge_vertex_cache.has(cache_key):
		return edge_vertex_cache[cache_key]

	var world_pos: Vector3
	if edge_world_cache.has(cache_key):
		world_pos = edge_world_cache[cache_key]
	else:
		var corners := FlyingEdgesTables.EDGE_CORNERS[edge_id]
		var c0: Vector3i = _corner_offset(corners.x)
		var c1: Vector3i = _corner_offset(corners.y)
		var p0 := Vector3(cx + c0.x, cy + c0.y, cz + c0.z)
		var p1 := Vector3(cx + c1.x, cy + c1.y, cz + c1.z)
		var v0 := field.get_sample(int(p0.x), int(p0.y), int(p0.z))
		var v1 := field.get_sample(int(p1.x), int(p1.y), int(p1.z))
		var denom := v1 - v0
		var t: float
		if absf(denom) < 0.00001:
			t = 0.5
		else:
			t = (iso - v0) / denom
		t = clampf(t, 0.0, 1.0)
		var grid_pos := p0.lerp(p1, t) * world_step
		world_pos = chunk_world_origin + grid_pos
		edge_world_cache[cache_key] = world_pos

	var local_pos := world_pos - chunk_world_center
	var index := vertices.size()
	vertices.append(local_pos)
	edge_vertex_cache[cache_key] = index
	return index


static func _edge_cache_key(
	grid_offset: Vector3i,
	cx: int,
	cy: int,
	cz: int,
	edge_id: int
) -> String:
	var corners := FlyingEdgesTables.EDGE_CORNERS[edge_id]
	var c0: Vector3i = _corner_offset(corners.x)
	var c1: Vector3i = _corner_offset(corners.y)
	var base := Vector3i(cx, cy, cz)
	var p0: Vector3i = grid_offset + base + c0
	var p1: Vector3i = grid_offset + base + c1
	if _lex_less(p1, p0):
		var tmp: Vector3i = p0
		p0 = p1
		p1 = tmp
	return "%d,%d,%d,%d,%d,%d" % [p0.x, p0.y, p0.z, p1.x, p1.y, p1.z]


static func _lex_less(a: Vector3i, b: Vector3i) -> bool:
	if a.x != b.x:
		return a.x < b.x
	if a.y != b.y:
		return a.y < b.y
	return a.z < b.z


static func _corner_offset(corner_id: int) -> Vector3i:
	match corner_id:
		0:
			return Vector3i(0, 0, 0)
		1:
			return Vector3i(1, 0, 0)
		2:
			return Vector3i(1, 0, 1)
		3:
			return Vector3i(0, 0, 1)
		4:
			return Vector3i(0, 1, 0)
		5:
			return Vector3i(1, 1, 0)
		6:
			return Vector3i(1, 1, 1)
		7:
			return Vector3i(0, 1, 1)
	return Vector3i.ZERO


static func _compute_gradient_normals(
	mesh_result: MeshResult,
	density: DensitySampler.WorldDensity,
	chunk_world_center: Vector3,
	world_step: float
) -> void:
	mesh_result.normals.resize(mesh_result.vertices.size())
	var epsilon := maxf(world_step * 0.5, 0.05)
	for i in mesh_result.vertices.size():
		var world_pos := chunk_world_center + mesh_result.vertices[i]
		var grad := density.gradient(world_pos, epsilon)
		if grad.length_squared() > 0.000001:
			mesh_result.normals[i] = grad.normalized()
		else:
			mesh_result.normals[i] = Vector3.UP


static func _compute_face_normals(mesh_result: MeshResult) -> void:
	mesh_result.normals.resize(mesh_result.vertices.size())
	for i in mesh_result.indices.size() / 3:
		var i0: int = mesh_result.indices[i * 3]
		var i1: int = mesh_result.indices[i * 3 + 1]
		var i2: int = mesh_result.indices[i * 3 + 2]
		var v0: Vector3 = mesh_result.vertices[i0]
		var v1: Vector3 = mesh_result.vertices[i1]
		var v2: Vector3 = mesh_result.vertices[i2]
		var face_normal := (v1 - v0).cross(v2 - v0)
		mesh_result.normals[i0] += face_normal
		mesh_result.normals[i1] += face_normal
		mesh_result.normals[i2] += face_normal
	for i in mesh_result.normals.size():
		var n: Vector3 = mesh_result.normals[i]
		if n.length_squared() > 0.000001:
			mesh_result.normals[i] = n.normalized()
		else:
			mesh_result.normals[i] = Vector3.UP
