extends MeshInstance3D

@export var edit_radius := 3.5
@export var ring_segments := 64
@export var ring_width := 0.25
@export var surface_lift := 0.08

var _dig_color := Color(1.0, 0.45, 0.15, 0.92)
var _build_color := Color(0.25, 0.85, 1.0, 0.92)


func _ready() -> void:
	mesh = _build_ring_mesh()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = _dig_color
	material_override = mat
	visible = false


func show_at(hit_position: Vector3, normal: Vector3, build_mode: bool = false) -> void:
	visible = true
	var up := normal.normalized()
	var tangent := up.cross(Vector3.UP)
	if tangent.length_squared() < 0.0001:
		tangent = up.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(up).normalized()
	global_transform = Transform3D(Basis(tangent, up, bitangent), hit_position + up * surface_lift)

	if material_override is StandardMaterial3D:
		material_override.albedo_color = _build_color if build_mode else _dig_color


func hide_cursor() -> void:
	visible = false


func _build_ring_mesh() -> ArrayMesh:
	var inner_radius := maxf(edit_radius - ring_width, edit_radius * 0.5)
	var outer_radius := edit_radius
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()

	for segment_index in ring_segments + 1:
		var angle := TAU * float(segment_index) / float(ring_segments)
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		vertices.append(direction * inner_radius)
		vertices.append(direction * outer_radius)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)

	for segment_index in ring_segments:
		var base_index := segment_index * 2
		indices.append_array([
			base_index,
			base_index + 1,
			base_index + 2,
			base_index + 1,
			base_index + 3,
			base_index + 2,
		])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices

	var ring_mesh := ArrayMesh.new()
	ring_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return ring_mesh
