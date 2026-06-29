extends MeshInstance3D
class_name SunCorona
## Billboard glow and ray burst drawn in front of the sun mesh.


@export var radius_multiplier: float = 3.2
@export var billboard_enabled: bool = true

var _sun_radius: float = 8.0


func configure(sun_radius: float) -> void:
	_sun_radius = maxf(sun_radius, 1.0)
	_update_scale()
	_apply_renderer_tweaks()


func _ready() -> void:
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_update_scale()
	_apply_renderer_tweaks()


func _process(_delta: float) -> void:
	if not billboard_enabled:
		return
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	look_at(camera.global_position, Vector3.UP)


func _update_scale() -> void:
	var diameter: float = _sun_radius * radius_multiplier * 2.0
	scale = Vector3(diameter, diameter, 1.0)


func _apply_renderer_tweaks() -> void:
	var mat: ShaderMaterial = material_override as ShaderMaterial
	if mat == null:
		return
	mat.render_priority = 0
