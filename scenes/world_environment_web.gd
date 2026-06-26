extends WorldEnvironment
## Tweaks environment settings for the web GLES compatibility renderer.


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	if environment == null:
		return

	var web_env: Environment = environment.duplicate() as Environment
	# Glow washes out custom sky shaders to white on the compatibility renderer.
	web_env.glow_enabled = false
	web_env.ssao_enabled = false
	environment = web_env
