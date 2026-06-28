class_name AsteroidMeshBuilder
extends RefCounted
## Builds a noisy icosphere mesh and matching convex collision shape.


const _ICO_INDICES: Array[int] = [
	0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11,
	1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
	3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9,
	4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1,
]


static func build(
	mesh_seed: int,
	radius: float,
	subdivisions: int = 2,
	roughness: float = 0.35
) -> Dictionary:
	var vertices: Array[Vector3] = []
	for v: Vector3 in _base_ico_vertices():
		vertices.append(v)

	var indices: Array[int] = []
	for i: int in _ICO_INDICES.size():
		indices.append(_ICO_INDICES[i])

	for _sub: int in subdivisions:
		_subdivide(vertices, indices)

	_displace_vertices(vertices, mesh_seed, radius, roughness)

	var mesh: ArrayMesh = _build_array_mesh(vertices, indices)
	var shape: Shape3D = mesh.create_convex_shape(true, false)
	return {"mesh": mesh, "shape": shape}


static func _base_ico_vertices() -> PackedVector3Array:
	var phi: float = (1.0 + sqrt(5.0)) * 0.5
	var raw: Array[Vector3] = [
		Vector3(-1.0, phi, 0.0),
		Vector3(1.0, phi, 0.0),
		Vector3(-1.0, -phi, 0.0),
		Vector3(1.0, -phi, 0.0),
		Vector3(0.0, -1.0, phi),
		Vector3(0.0, 1.0, phi),
		Vector3(0.0, -1.0, -phi),
		Vector3(0.0, 1.0, -phi),
		Vector3(phi, 0.0, -1.0),
		Vector3(phi, 0.0, 1.0),
		Vector3(-phi, 0.0, -1.0),
		Vector3(-phi, 0.0, 1.0),
	]
	var verts: PackedVector3Array = PackedVector3Array()
	for v: Vector3 in raw:
		verts.append(v.normalized())
	return verts


static func _subdivide(vertices: Array[Vector3], indices: Array[int]) -> void:
	var new_indices: Array[int] = []
	var midpoint_cache: Dictionary = {}

	for tri_i: int in range(0, indices.size(), 3):
		var i0: int = indices[tri_i]
		var i1: int = indices[tri_i + 1]
		var i2: int = indices[tri_i + 2]
		var m01: int = _get_midpoint(i0, i1, vertices, midpoint_cache)
		var m12: int = _get_midpoint(i1, i2, vertices, midpoint_cache)
		var m20: int = _get_midpoint(i2, i0, vertices, midpoint_cache)
		new_indices.append_array([i0, m01, m20, i1, m12, m01, i2, m20, m12, m01, m12, m20])

	indices.clear()
	indices.append_array(new_indices)


static func _get_midpoint(
	i0: int,
	i1: int,
	vertices: Array[Vector3],
	cache: Dictionary
) -> int:
	var key: int = mini(i0, i1) * 10000 + maxi(i0, i1)
	if cache.has(key):
		return cache[key]

	var midpoint: Vector3 = (vertices[i0] + vertices[i1]) * 0.5
	midpoint = midpoint.normalized()
	var index: int = vertices.size()
	vertices.append(midpoint)
	cache[key] = index
	return index


static func _displace_vertices(
	vertices: Array[Vector3],
	mesh_seed: int,
	radius: float,
	roughness: float
) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = mesh_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.85
	noise.fractal_octaves = 3

	for i: int in vertices.size():
		var direction: Vector3 = vertices[i].normalized()
		var sample: float = noise.get_noise_3d(
			direction.x * 2.4,
			direction.y * 2.4,
			direction.z * 2.4
		)
		var scale: float = 1.0 + sample * roughness
		vertices[i] = direction * radius * scale


static func _build_array_mesh(vertices: Array[Vector3], indices: Array[int]) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i: int in indices.size():
		var v: Vector3 = vertices[indices[i]]
		st.set_normal(v.normalized())
		st.add_vertex(v)

	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, null)
	return mesh
