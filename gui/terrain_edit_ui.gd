extends PanelContainer

signal mode_changed(is_build_mode: bool)

@onready var _mode_button: Button = $MarginContainer/VBox/ModeButton

var is_build_mode := false


func _ready() -> void:
	_mode_button.pressed.connect(_on_mode_button_pressed)
	_update_button()


func _on_mode_button_pressed() -> void:
	is_build_mode = not is_build_mode
	_update_button()
	mode_changed.emit(is_build_mode)


func _update_button() -> void:
	if is_build_mode:
		_mode_button.text = "Mode: Add"
		_mode_button.modulate = Color(0.25, 0.85, 1.0)
	else:
		_mode_button.text = "Mode: Destroy"
		_mode_button.modulate = Color(1.0, 0.45, 0.15)
