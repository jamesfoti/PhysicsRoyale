extends Node3D
class_name SunBody
## Terrain-meshed sun with a directional light that shines toward the planet.


@export var planet_path: NodePath
@export var light_energy: float = 1.25
@export var light_color: Color = Color(1.0, 0.94, 0.82, 1.0)

@onready var _terrain: TerrainWorldV2 = $TerrainWorld
@onready var _light: DirectionalLight3D = $DirectionalLight3D
@onready var _corona: SunCorona = $Corona
@onready var _corona_rays: SunCorona = $CoronaRays


func _ready() -> void:
	add_to_group("sun")
	_light.light_energy = light_energy
	_light.light_color = light_color
	_light.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_AND_SKY
	call_deferred("_configure_sun_mesh")
	call_deferred("_update_light_direction")


func _configure_sun_mesh() -> void:
	if _terrain == null:
		return
	for child: Node in _terrain.get_children():
		if child is MeshInstance3D:
			(child as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var sun_radius: float = _terrain.get_sphere_radius()
	_corona.configure(sun_radius)
	_corona_rays.configure(sun_radius)


func _update_light_direction() -> void:
	var planet: Node3D = get_node_or_null(planet_path) as Node3D
	if planet == null:
		return
	_light.global_position = global_position
	_light.look_at(planet.global_position, Vector3.UP)
