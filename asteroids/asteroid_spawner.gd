extends Node
class_name AsteroidSpawner
## Spawns procedural asteroids on trajectories toward playable planets.


const AsteroidScene: PackedScene = preload("res://asteroids/asteroid.tscn")

@export var enabled: bool = true
@export var spawn_interval_min: float = 8.0
@export var spawn_interval_max: float = 18.0
@export var max_active: int = 6
@export var min_radius: float = 0.6
@export var max_radius: float = 2.2
@export var min_speed: float = 8.0
@export var max_speed: float = 22.0
@export var spawn_distance_min: float = 2.4
@export var spawn_distance_max: float = 4.0
@export var mesh_subdivisions: int = 2
@export var initial_delay: float = 4.0

var _spawn_timer: float = 0.0


func _ready() -> void:
	add_to_group("asteroid_spawner")
	_spawn_timer = initial_delay


func _process(delta: float) -> void:
	if not enabled or Engine.is_editor_hint():
		return
	if _count_active_asteroids() >= max_active:
		return

	_spawn_timer -= delta
	if _spawn_timer > 0.0:
		return

	_spawn_timer = randf_range(spawn_interval_min, spawn_interval_max)
	_try_spawn()


func _try_spawn() -> void:
	var planets: Array[Node] = get_tree().get_nodes_in_group("planet")
	if planets.is_empty():
		return

	var planet: TerrainWorldV2 = planets[randi() % planets.size()] as TerrainWorldV2
	if planet == null:
		return

	var center: Vector3 = planet.global_position + planet.sphere_center
	var planet_radius: float = planet.get_sphere_radius()
	var spawn_dir: Vector3 = _random_unit_vector()
	var spawn_dist: float = planet_radius * randf_range(spawn_distance_min, spawn_distance_max)
	var spawn_pos: Vector3 = center + spawn_dir * spawn_dist

	var to_planet: Vector3 = (center - spawn_pos).normalized()
	var tangent: Vector3 = spawn_dir.cross(Vector3.UP)
	if tangent.length_squared() < 0.01:
		tangent = spawn_dir.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var approach: Vector3 = (
		to_planet + tangent * randf_range(-0.35, 0.35)
	).normalized()

	var radius: float = randf_range(min_radius, max_radius)
	var speed: float = randf_range(min_speed, max_speed)
	var mesh_seed: int = randi()

	var asteroid: Asteroid = AsteroidScene.instantiate() as Asteroid
	get_tree().current_scene.add_child(asteroid)
	asteroid.global_position = spawn_pos
	asteroid.setup(
		planet,
		mesh_seed,
		radius,
		approach * speed,
		mesh_subdivisions,
		randf_range(0.25, 0.45)
	)


func _count_active_asteroids() -> int:
	return get_tree().get_nodes_in_group("asteroid").size()


func _random_unit_vector() -> Vector3:
	return Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
		randf_range(-1.0, 1.0),
	).normalized()
