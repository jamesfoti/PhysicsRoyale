extends Node3D
class_name GameTorch
## Hand-held torch: particle flames, glow shader, and flickering OmniLight3D.


@export var light_energy: float = 2.5
@export var light_range: float = 10.0
@export var light_color: Color = Color(1.0, 0.72, 0.38, 1.0)
@export var flicker_strength: float = 0.22
@export var cast_shadows: bool = false
@export_range(0.0, 10.0, 0.01) var light_attenuation: float = 0.85

@onready var _flame_anchor: Node3D = $FlameAnchor
@onready var _light: OmniLight3D = $FlameAnchor/TorchLight
@onready var _flame_glow: MeshInstance3D = $FlameAnchor/FlameGlow
@onready var _flame_particles: GPUParticles3D = $FlameAnchor/FlameParticles
@onready var _ember_particles: GPUParticles3D = $FlameAnchor/EmberParticles

var _lit: bool = false
var _base_light_energy: float = 2.5
var _flicker_time: float = 0.0


func _ready() -> void:
	_base_light_energy = light_energy
	_hide_legacy_flame_cone()
	_snap_flame_anchor()
	_configure_light()
	set_lit(false)


func _process(delta: float) -> void:
	if _lit and _flame_glow.visible:
		_billboard_flame_glow()
	if not _lit or _light == null:
		return
	_flicker_time += delta
	var n: float = sin(_flicker_time * 11.0) * 0.5 + sin(_flicker_time * 6.3 + 1.2) * 0.35
	_light.light_energy = _base_light_energy * (1.0 + n * flicker_strength)


func is_lit() -> bool:
	return _lit


func set_lit(enabled: bool) -> void:
	_lit = enabled
	_light.visible = enabled
	_flame_glow.visible = enabled
	_flame_particles.emitting = enabled
	_ember_particles.emitting = enabled
	if not enabled:
		_flame_particles.amount_ratio = 0.0
		_ember_particles.amount_ratio = 0.0
	else:
		_flame_particles.amount_ratio = 1.0
		_ember_particles.amount_ratio = 1.0


func toggle() -> void:
	set_lit(not _lit)


func _configure_light() -> void:
	_light.light_color = light_color
	_light.light_energy = light_energy
	_light.omni_range = light_range
	_light.omni_attenuation = light_attenuation
	_light.shadow_enabled = cast_shadows


func _hide_legacy_flame_cone() -> void:
	var legacy_flame: Node = find_child("TorchFlame", true, false)
	if legacy_flame == null:
		return
	if legacy_flame is GeometryInstance3D:
		var mesh: GeometryInstance3D = legacy_flame as GeometryInstance3D
		mesh.visible = false
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		legacy_flame.visible = false


func _snap_flame_anchor() -> void:
	var head: Node3D = find_child("TorchHead", true, false) as Node3D
	if head == null:
		return
	# Sit flame effects just above the metal cup.
	_flame_anchor.position = head.position + Vector3(0.0, 0.1, 0.0)


func _billboard_flame_glow() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var cam_pos: Vector3 = camera.global_position
	var glow_pos: Vector3 = _flame_glow.global_position
	var facing: Vector3 = Vector3(cam_pos.x - glow_pos.x, 0.0, cam_pos.z - glow_pos.z)
	if facing.length_squared() < 0.0001:
		return
	_flame_glow.look_at(glow_pos + facing.normalized(), Vector3.UP)
