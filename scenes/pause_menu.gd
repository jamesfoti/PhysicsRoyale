extends CanvasLayer
## Pause overlay: Resume, Controls, Restart, or Quit.

@onready var _panel: PanelContainer = $Panel
@onready var _main_menu: VBoxContainer = $Panel/Margin/MainMenu
@onready var _controls_menu: VBoxContainer = $Panel/Margin/ControlsMenu
@onready var _controls_text: Label = $Panel/Margin/ControlsMenu/ControlsText
@onready var _resume_button: Button = $Panel/Margin/MainMenu/ResumeButton
@onready var _controls_button: Button = $Panel/Margin/MainMenu/ControlsButton
@onready var _reset_button: Button = $Panel/Margin/MainMenu/ResetButton
@onready var _quit_button: Button = $Panel/Margin/MainMenu/QuitButton
@onready var _back_button: Button = $Panel/Margin/ControlsMenu/BackButton

const _CONTROLS_LINES: Array[String] = [
	"W / S — Move forward / backward",
	"Mouse — Turn player",
	"Mouse — Camera pitch",
	"Middle mouse + drag — Orbit camera",
	"Scroll wheel — Zoom in / out",
	"Space — Jump",
	"Shift — Run",
	"E — Inventory (torch, pickaxe, empty hands)",
	"P — Pause menu",
	"Esc — Free / capture mouse (or stow item / exit terrain edit)",
	"F3 — Debug overlay",
	"Ctrl — Toggle terrain focus while editing (stay put, aim with mouse)",
	"Hold left click — Paint terrain (threaded mesh rebuild)",
]

var _paused: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_controls_text.text = "\n".join(_CONTROLS_LINES)
	_show_main_menu()
	_resume_button.pressed.connect(_on_resume_pressed)
	_controls_button.pressed.connect(_on_controls_pressed)
	_reset_button.pressed.connect(_on_reset_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_back_button.pressed.connect(_on_back_pressed)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		if _paused:
			if _controls_menu.visible:
				_show_main_menu()
			else:
				_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()
		return

	if not _paused:
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _controls_menu.visible:
		_show_main_menu()
	else:
		_resume()
	get_viewport().set_input_as_handled()


func _on_resume_pressed() -> void:
	_resume()


func _on_controls_pressed() -> void:
	_show_controls_menu()


func _on_back_pressed() -> void:
	_show_main_menu()


func _on_reset_pressed() -> void:
	var player: PlanetPlayer = get_tree().get_first_node_in_group("player") as PlanetPlayer
	if player != null:
		player.respawn_random()
	_resume()


func _on_quit_pressed() -> void:
	get_tree().quit()


func _show_main_menu() -> void:
	_main_menu.visible = true
	_controls_menu.visible = false
	_panel.custom_minimum_size = Vector2(240, 0)


func _show_controls_menu() -> void:
	_main_menu.visible = false
	_controls_menu.visible = true
	_panel.custom_minimum_size = Vector2(320, 0)


func _pause() -> void:
	_paused = true
	visible = true
	_show_main_menu()
	get_tree().paused = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)


func _resume() -> void:
	_paused = false
	visible = false
	_show_main_menu()
	get_tree().paused = false
	_sync_game_mouse_mode()


func _sync_game_mouse_mode() -> void:
	var hud: Node = get_tree().get_first_node_in_group("terrain_hud")
	if hud != null and hud.has_method("sync_mouse_mode"):
		hud.call("sync_mouse_mode")
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
