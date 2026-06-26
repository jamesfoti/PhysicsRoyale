@tool
extends EditorInspectorPlugin

const _TERRAIN_WORLD_SCRIPT = preload("res://terrain/terrain_world.gd")


func _can_handle(object: Object) -> bool:
	return object is Node3D and object.get_script() == _TERRAIN_WORLD_SCRIPT


func _parse_begin(object: Object) -> void:
	var terrain := object as Node3D
	var root := EditorInterface.get_edited_scene_root()
	var terrain_path := root.get_path_to(terrain) if root != null else NodePath()

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 6)

	var label := Label.new()
	label.text = "Terrain Editor"
	panel.add_child(label)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	panel.add_child(row)

	var build_btn := Button.new()
	build_btn.text = "Build Terrain"
	build_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	build_btn.pressed.connect(func() -> void: _on_build_pressed(terrain_path))
	row.add_child(build_btn)

	var destroy_btn := Button.new()
	destroy_btn.text = "Destroy Terrain"
	destroy_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	destroy_btn.pressed.connect(func() -> void: _on_destroy_pressed(terrain_path))
	row.add_child(destroy_btn)

	add_custom_control(panel)


func _get_terrain_node(terrain_path: NodePath) -> Node3D:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return null
	return root.get_node_or_null(terrain_path) as Node3D


func _on_build_pressed(terrain_path: NodePath) -> void:
	var terrain := _get_terrain_node(terrain_path)
	if terrain == null:
		push_error("[TerrainWorldV2] Could not find terrain node.")
		return
	if not terrain.has_method("rebuild_all"):
		push_error(
			"[TerrainWorldV2] Script not loaded — check the Output panel for errors in terrain_world.gd."
		)
		return
	terrain.rebuild_all()
	_mark_scene_unsaved()


func _on_destroy_pressed(terrain_path: NodePath) -> void:
	var terrain := _get_terrain_node(terrain_path)
	if terrain == null:
		push_error("[TerrainWorldV2] Could not find terrain node.")
		return
	if not terrain.has_method("destroy_all"):
		push_error(
			"[TerrainWorldV2] Script not loaded — check the Output panel for errors in terrain_world.gd."
		)
		return
	terrain.destroy_all()
	_mark_scene_unsaved()


func _mark_scene_unsaved() -> void:
	EditorInterface.mark_scene_as_unsaved()
