extends Control

const Settings = preload("res://settings.gd")
const Binding = preload("res://binding.gd")
const MouseCapture = preload("res://gui/mouse_capture.gd")

@onready var _toggle_button : Button = $VBox/ToggleButton
@onready var _panel : PanelContainer = $VBox/PanelContainer
@onready var _show_display_on_screen_debug_overlay_checkbox : CheckBox = \
	$VBox/PanelContainer/VBox/ShowDisplayOnScreenDebugOverlay
@onready var _show_octree_nodes_checkbox : CheckBox = $VBox/PanelContainer/VBox/ShowOctreeNodes
@onready var _show_mesh_updates_checkbox : CheckBox = $VBox/PanelContainer/VBox/ShowMeshUpdates
@onready var _show_edited_data_blocks_checkbox : CheckBox = \
	$VBox/PanelContainer/VBox/ShowEditedDataBlocks
@onready var _wireframe_checkbox : CheckBox = $VBox/PanelContainer/VBox/Wireframe

var _settings : Settings
var _bindings : Array[Binding.BindingBase] = []
var _expanded := false


func _ready():
	_toggle_button.focus_mode = Control.FOCUS_NONE
	_set_expanded(false)
	_update_toggle_label()


func _process(_delta: float) -> void:
	_update_debug_text_position()


func _update_debug_text_position() -> void:
	if _settings == null or not _settings.show_display_on_screen_debug_overlay:
		return
	var rect: Rect2 = $VBox.get_global_rect()
	DDD.set_text_screen_offset(Vector2(rect.position.x, rect.end.y + 4.0))


func set_settings(s: Settings):
	assert(_settings == null)
	_settings = s

	_bindings.append(Binding.create(_settings, "show_display_on_screen_debug_overlay",
		_show_display_on_screen_debug_overlay_checkbox))
	_bindings.append(Binding.create(_settings, "show_octree_nodes", _show_octree_nodes_checkbox))
	_bindings.append(Binding.create(_settings, "show_mesh_updates", _show_mesh_updates_checkbox))
	_bindings.append(Binding.create(_settings, "show_edited_data_blocks",
		_show_edited_data_blocks_checkbox))
	_bindings.append(Binding.create(_settings, "wireframe", _wireframe_checkbox))

	_update_ui()


func toggle():
	_set_expanded(not _expanded)


func close_if_open():
	if _expanded:
		_set_expanded(false)


func _on_toggle_button_pressed():
	toggle()


func _set_expanded(expanded: bool):
	_expanded = expanded
	_panel.visible = expanded
	_update_toggle_label()
	_update_debug_text_position()

	var mouse_capture := _get_mouse_capture()
	if mouse_capture != null:
		mouse_capture.set_ui_blocks_capture(expanded)
		if expanded:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			mouse_capture.capture()


func _get_mouse_capture() -> MouseCapture:
	var solar_system := get_parent().get_parent()
	if solar_system.has_node("MouseCapture"):
		return solar_system.get_node("MouseCapture")
	return null


func _update_toggle_label():
	if _expanded:
		_toggle_button.text = "Close Debug (F3)"
	else:
		_toggle_button.text = "Debug (F3)"


func _update_ui():
	for binding in _bindings:
		binding.update_ui()
