extends Node3D
## Large star dome mesh scaled to follow the camera.


const DOME_RADIUS: float = 800.0

@onready var _mesh: MeshInstance3D = $MeshInstance3D


func _ready() -> void:
	_mesh.scale = Vector3(DOME_RADIUS, DOME_RADIUS, DOME_RADIUS)
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
