extends Control


signal resume_requested
signal settings_requested
signal restart_requested
signal exit_to_os_requested


func _unhandled_input(event: InputEvent):
	if not visible:
		return
	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			if event.keycode == KEY_ESCAPE or event.keycode == KEY_P:
				resume_requested.emit()
				get_viewport().set_input_as_handled()


func _on_Resume_pressed():
	resume_requested.emit()


func _on_Settings_pressed():
	settings_requested.emit()


func _on_Restart_pressed():
	restart_requested.emit()


func _on_ExitToOs_pressed():
	exit_to_os_requested.emit()
