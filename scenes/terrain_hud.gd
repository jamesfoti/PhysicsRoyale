extends CanvasLayer
## Collapsible debug overlay plus terrain edit mode toggle.


signal terrain_edit_mode_changed(mode: TerrainBrush.EditMode)

@onready var _bar: HBoxContainer = $Bar
@onready var _item_menu: PlayerItemMenu = $Bar/ItemAnchor/PlayerItemMenu
@onready var _anchor: VBoxContainer = $Bar/Anchor
@onready var _toggle_button: Button = $Bar/Anchor/ToggleButton
@onready var _panel: PanelContainer = $Bar/Anchor/Panel
@onready var _fps: Label = $Bar/Anchor/Panel/Margin/Fields/Fps
@onready var _position: Label = $Bar/Anchor/Panel/Margin/Fields/Position
@onready var _edit_mode_label: Label = $Bar/Anchor/Panel/Margin/Fields/EditMode

var _expanded: bool = false
var _edit_mode: TerrainBrush.EditMode = TerrainBrush.EditMode.OFF

const _MARGIN: float = 8.0


func _ready() -> void:
	add_to_group("terrain_hud")
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_set_expanded(false)
	_update_edit_mode_ui()
	get_viewport().size_changed.connect(_queue_layout)
	_panel.visibility_changed.connect(_queue_layout)
	_queue_layout()
	call_deferred("_apply_edit_mode_to_brush")


func _input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if _item_menu.is_open() and event.is_action_pressed("ui_cancel"):
		_item_menu.close_menu()
		get_viewport().set_input_as_handled()
		return
	if (
		event.is_action_pressed("ui_cancel")
		and _edit_mode != TerrainBrush.EditMode.OFF
	):
		set_edit_mode(TerrainBrush.EditMode.OFF)
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_set_expanded(not _expanded)
		get_viewport().set_input_as_handled()


func get_item_menu() -> PlayerItemMenu:
	return _item_menu


func get_edit_mode() -> TerrainBrush.EditMode:
	return _edit_mode


func set_edit_mode(mode: TerrainBrush.EditMode) -> void:
	if mode == TerrainBrush.EditMode.OFF:
		var player: PlanetPlayer = get_tree().get_first_node_in_group("player") as PlanetPlayer
		if player != null and player.is_terrain_focus_active():
			player.exit_terrain_focus()
	_edit_mode = mode
	_update_edit_mode_ui()
	terrain_edit_mode_changed.emit(_edit_mode)
	_apply_edit_mode_to_brush()
	sync_mouse_mode()


func sync_mouse_mode() -> void:
	if get_tree().paused or _item_menu.is_open():
		return
	var player: PlanetPlayer = get_tree().get_first_node_in_group("player") as PlanetPlayer
	if player != null and player.is_terrain_focus_active():
		Input.set_mouse_mode(Input.MOUSE_MODE_CONFINED_HIDDEN)
		return
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
	if not _expanded:
		return
	var player: Node3D = get_tree().get_first_node_in_group("player") as Node3D
	var pos_line: String = "Player's position: n/a"
	if player != null:
		var p: Vector3 = player.global_position
		pos_line = "Player's position: (x = %.0f, y = %.0f, z = %.0f)" % [p.x, p.y, p.z]
	_fps.text = "Frames Per Second (FPS): %d" % Engine.get_frames_per_second()
	_position.text = pos_line
	_edit_mode_label.text = _edit_mode_display_text()
	_queue_layout()


func _update_edit_mode_ui() -> void:
	if _expanded:
		_edit_mode_label.text = _edit_mode_display_text()


func _edit_mode_display_text() -> String:
	var text: String = "Terrain edit: %s" % _edit_mode_text()
	var player: PlanetPlayer = get_tree().get_first_node_in_group("player") as PlanetPlayer
	if player != null and player.is_terrain_focus_active():
		text += " (Ctrl focus)"
	return text


func _edit_mode_text() -> String:
	match _edit_mode:
		TerrainBrush.EditMode.DESTROY:
			return "Destroy (hold LMB)"
		TerrainBrush.EditMode.ADD:
			return "Add (hold LMB)"
	return "Off"


func _apply_edit_mode_to_brush() -> void:
	var brush: TerrainBrush = get_tree().get_first_node_in_group("terrain_brush") as TerrainBrush
	if brush != null:
		brush.set_edit_mode(_edit_mode)


func _on_toggle_pressed() -> void:
	_set_expanded(not _expanded)


func _queue_layout() -> void:
	call_deferred("_layout_anchor")


func _layout_anchor() -> void:
	_anchor.custom_minimum_size = Vector2.ZERO
	_toggle_button.custom_minimum_size = Vector2.ZERO

	if _expanded:
		var panel_width: float = _panel.get_minimum_size().x
		if panel_width > 0.0:
			_toggle_button.custom_minimum_size.x = panel_width

	_bar.offset_bottom = _MARGIN + _anchor.get_minimum_size().y


func _set_expanded(expanded: bool) -> void:
	_expanded = expanded
	_panel.visible = expanded
	_toggle_button.text = "Debug (F3) ▲" if expanded else "Debug (F3) ▼"
	_queue_layout()
