extends WorldEnvironment
## Web export uses GLES compatibility, where custom sky shaders are unreliable.


const STARFIELD_DOME_SCENE: PackedScene = preload("res://scenes/starfield_dome.tscn")


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	if environment == null:
		return

	var web_env: Environment = environment.duplicate(true) as Environment
	web_env.background_mode = Environment.BG_COLOR
	web_env.background_color = Color(0.0, 0.0, 0.01, 1.0)
	web_env.background_energy_multiplier = 1.0
	web_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	web_env.ambient_light_color = Color(0.14, 0.16, 0.24, 1.0)
	web_env.ambient_light_energy = 0.65
	web_env.glow_enabled = false
	web_env.ssao_enabled = false
	web_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment = web_env

	call_deferred("_attach_starfield_dome")
	call_deferred("_apply_web_render_tweaks")


func _attach_starfield_dome() -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	if camera.get_node_or_null("StarfieldDome") != null:
		return
	var dome: Node3D = STARFIELD_DOME_SCENE.instantiate() as Node3D
	camera.add_child(dome)


func _apply_web_render_tweaks() -> void:
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		return
	_disable_directional_shadows(scene_root)


func _disable_directional_shadows(node: Node) -> void:
	if node is DirectionalLight3D:
		(node as DirectionalLight3D).shadow_enabled = false
	for child: Node in node.get_children():
		_disable_directional_shadows(child)
