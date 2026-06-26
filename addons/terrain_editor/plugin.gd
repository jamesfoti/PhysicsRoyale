@tool
extends EditorPlugin

const _Inspector = preload("res://addons/terrain_editor/terrain_world_inspector.gd")

var _inspector: EditorInspectorPlugin


func _enter_tree() -> void:
	_inspector = _Inspector.new()
	add_inspector_plugin(_inspector)


func _exit_tree() -> void:
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null
