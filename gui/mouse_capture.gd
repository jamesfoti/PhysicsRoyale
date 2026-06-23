extends Control

@export var capture_mouse_in_ready := true

signal escaped

var _ui_blocks_capture := false
var _capture_allowed := true


func set_ui_blocks_capture(blocks: bool):
	_ui_blocks_capture = blocks


func set_capture_allowed(allowed: bool) -> void:
	_capture_allowed = allowed
	if not allowed and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _ready():
	if capture_mouse_in_ready:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func capture():
	if not _capture_allowed:
		return
	# Remove focus from the HUD
	var focus_owner = get_viewport().gui_get_focus_owner()
	if focus_owner != null:
		focus_owner.release_focus()
	
	# Capture the mouse for the game
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.pressed and Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			if _capture_allowed and not _ui_blocks_capture:
				capture()
	
	elif event is InputEventKey:
		if event.pressed and event.keycode == KEY_ESCAPE:
			if Input.get_mouse_mode() != Input.MOUSE_MODE_VISIBLE:
				# Get the mouse back
				Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
				emit_signal("escaped")
