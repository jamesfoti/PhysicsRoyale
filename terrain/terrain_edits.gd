class_name TerrainEdits
extends RefCounted
## Runtime brush strokes layered on procedural density. Negative density = solid.


class BrushStroke:
	var position: Vector3 = Vector3.ZERO
	var radius: float = 1.0
	var add_solid: bool = false


var _strokes: Array[BrushStroke] = []


func add_brush(world_position: Vector3, radius: float, add_solid: bool) -> void:
	var stroke := BrushStroke.new()
	stroke.position = world_position
	stroke.radius = maxf(radius, 0.1)
	stroke.add_solid = add_solid
	_strokes.append(stroke)


func apply_to_density(density: float, world_pos: Vector3) -> float:
	var value := density
	for stroke: BrushStroke in _strokes:
		var sphere_sdf: float = world_pos.distance_to(stroke.position) - stroke.radius
		if stroke.add_solid:
			value = minf(value, sphere_sdf)
		else:
			value = maxf(value, -sphere_sdf)
	return value


func get_stroke_count() -> int:
	return _strokes.size()
