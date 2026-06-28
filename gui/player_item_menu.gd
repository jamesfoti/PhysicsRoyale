extends VBoxContainer
class_name PlayerItemMenu
## Popup list of hand items; selection activates torch or pickaxe / terrain edit.


signal item_selected(item: PlayerItems.Item)

@onready var _toggle_button: Button = $ToggleButton
@onready var _popup: PanelContainer = $Popup
@onready var _none_button: Button = $Popup/Margin/Buttons/NoneButton
@onready var _torch_button: Button = $Popup/Margin/Buttons/TorchButton
@onready var _pickaxe_destroy_button: Button = $Popup/Margin/Buttons/PickaxeDestroyButton
@onready var _pickaxe_add_button: Button = $Popup/Margin/Buttons/PickaxeAddButton

var _open: bool = false
var _active_item: PlayerItems.Item = PlayerItems.Item.NONE


func _ready() -> void:
	add_to_group("player_item_menu")
	_toggle_button.focus_mode = Control.FOCUS_NONE
	for button: Button in [
		_none_button,
		_torch_button,
		_pickaxe_destroy_button,
		_pickaxe_add_button,
	]:
		button.focus_mode = Control.FOCUS_NONE
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_none_button.pressed.connect(_select.bind(PlayerItems.Item.NONE))
	_torch_button.pressed.connect(_select.bind(PlayerItems.Item.TORCH))
	_pickaxe_destroy_button.pressed.connect(_select.bind(PlayerItems.Item.PICKAXE_DESTROY))
	_pickaxe_add_button.pressed.connect(_select.bind(PlayerItems.Item.PICKAXE_ADD))
	_set_open(false)
	_refresh_buttons()


func is_open() -> bool:
	return _open


func toggle_menu() -> void:
	_set_open(not _open)


func close_menu() -> void:
	_set_open(false)


func set_active_item(item: PlayerItems.Item) -> void:
	_active_item = item
	_refresh_buttons()


func _select(item: PlayerItems.Item) -> void:
	item_selected.emit(item)
	close_menu()


func _on_toggle_pressed() -> void:
	toggle_menu()


func _set_open(open: bool) -> void:
	_open = open
	_popup.visible = open
	_toggle_button.text = "Inventory (E) ▲" if open else "Inventory (E) ▼"
	if open:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	else:
		var hud: Node = get_tree().get_first_node_in_group("terrain_hud")
		if hud != null and hud.has_method("sync_mouse_mode"):
			hud.sync_mouse_mode()


func _refresh_buttons() -> void:
	_reset_button_style(_none_button, _active_item == PlayerItems.Item.NONE)
	_reset_button_style(_torch_button, _active_item == PlayerItems.Item.TORCH)
	_reset_button_style(
		_pickaxe_destroy_button,
		_active_item == PlayerItems.Item.PICKAXE_DESTROY
	)
	_reset_button_style(_pickaxe_add_button, _active_item == PlayerItems.Item.PICKAXE_ADD)


func _reset_button_style(button: Button, active: bool) -> void:
	button.modulate = Color(0.55, 1.0, 0.65) if active else Color.WHITE
