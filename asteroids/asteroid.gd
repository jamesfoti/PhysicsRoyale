extends RigidBody3D
class_name Asteroid
## Procedural rocky body that falls toward a planet and carves terrain on impact.


signal impacted(planet: TerrainWorldV2, position: Vector3, crater_radius: float)

const _MIN_DIR_LEN_SQ: float = 0.0001

@export var gravity_strength: float = 4.0
@export var min_impact_speed: float = 2.0
@export var crater_radius_scale: float = 0.18
@export var min_crater_radius: float = 1.5
@export var max_crater_radius: float = 7.0
@export var max_lifetime: float = 120.0

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _target_planet: TerrainWorldV2
var _asteroid_radius: float = 1.0
var _impacted: bool = false
var _lifetime: float = 0.0


func _ready() -> void:
	add_to_group("asteroid")
	can_sleep = false
	body_entered.connect(_on_body_entered)


func setup(
	planet: TerrainWorldV2,
	mesh_seed: int,
	radius: float,
	initial_velocity: Vector3,
	mesh_subdivisions: int = 2,
	surface_roughness: float = 0.35
) -> void:
	_target_planet = planet
	_asteroid_radius = radius

	var built: Dictionary = AsteroidMeshBuilder.build(
		mesh_seed,
		radius,
		mesh_subdivisions,
		surface_roughness
	)
	_mesh_instance.mesh = built["mesh"] as ArrayMesh
	_collision_shape.shape = built["shape"] as Shape3D

	mass = maxf(radius * radius * radius * 0.65, 0.5)
	linear_velocity = initial_velocity
	angular_velocity = Vector3(
		randf_range(-2.5, 2.5),
		randf_range(-2.5, 2.5),
		randf_range(-2.5, 2.5)
	) / maxf(radius, 0.5)


func _physics_process(delta: float) -> void:
	_lifetime += delta
	if _lifetime >= max_lifetime:
		queue_free()
		return
	if _target_planet == null or _impacted:
		return

	var center: Vector3 = _planet_center()
	var dist: float = global_position.distance_to(center)
	var planet_radius: float = _target_planet.get_sphere_radius()
	if dist > planet_radius * 8.0:
		queue_free()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	if _target_planet == null or _impacted:
		return

	var center: Vector3 = _planet_center()
	var to_center: Vector3 = center - state.transform.origin
	if to_center.length_squared() < _MIN_DIR_LEN_SQ:
		return

	state.linear_velocity += to_center.normalized() * gravity_strength * state.step


func _on_body_entered(body: Node) -> void:
	if _impacted:
		return
	var terrain: TerrainWorldV2 = _terrain_from_node(body)
	if terrain == null:
		return
	_apply_impact(terrain)


func _apply_impact(terrain: TerrainWorldV2) -> void:
	if _impacted:
		return
	_impacted = true

	var impact_speed: float = linear_velocity.length()
	if impact_speed < min_impact_speed:
		queue_free()
		return

	var crater_radius: float = clampf(
		_asteroid_radius * 1.25 + impact_speed * crater_radius_scale,
		min_crater_radius,
		max_crater_radius
	)
	var impact_point: Vector3 = _estimate_impact_point(terrain)

	terrain.apply_brush(impact_point, crater_radius, false)
	impacted.emit(terrain, impact_point, crater_radius)
	queue_free()


func _estimate_impact_point(terrain: TerrainWorldV2) -> Vector3:
	var center: Vector3 = terrain.global_position + terrain.sphere_center
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		global_position,
		center
	)
	query.collide_with_areas = false
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		return hit.position

	var direction: Vector3 = (global_position - center).normalized()
	if direction.length_squared() < _MIN_DIR_LEN_SQ:
		return global_position
	return center + direction * terrain.get_sphere_radius()


func _terrain_from_node(node: Node) -> TerrainWorldV2:
	var current: Node = node
	while current != null:
		if current is TerrainWorldV2:
			var terrain: TerrainWorldV2 = current as TerrainWorldV2
			if terrain.generate_collision:
				return terrain
			return null
		current = current.get_parent()
	return null


func _planet_center() -> Vector3:
	return _target_planet.global_position + _target_planet.sphere_center
