extends Node
class_name Main

const Settings = preload("res://settings.gd")

@onready var _main_menu : Control = $MainMenu
@onready var _settings_ui : Control = $SettingsUI

var _settings := Settings.new()
var _game : SolarSystem


func _ready():
	_settings_ui.set_settings(_settings)


func _on_MainMenu_start_requested():
	_start_game()


func _start_game() -> void:
	assert(_game == null)
	_main_menu.hide()
	var game_scene : PackedScene = load("res://scenes/game.tscn")
	_game = game_scene.instantiate()
	_game.set_settings(_settings)
	_game.set_settings_ui(_settings_ui)
	_game.exit_to_menu_requested.connect(_on_game_exit_to_menu_requested)
	_game.restart_requested.connect(_on_game_restart_requested)
	add_child(_game)


func _restart_game() -> void:
	if _game != null:
		remove_child(_game)
		_game.free()
		_game = null
	get_tree().paused = false
	_start_game()


func _on_game_restart_requested():
	_restart_game()


func _on_MainMenu_settings_requested():
	_settings_ui.show()


func _on_MainMenu_exit_requested():
	get_tree().quit()


func _on_game_exit_to_menu_requested():
	_game.queue_free()
	_game = null
	_main_menu.show()


func _process(delta):
	AudioServer.set_bus_volume_db(0, linear_to_db(_settings.main_volume_linear))

	DDD.visible = _settings.show_display_on_screen_debug_overlay

	var viewport := get_viewport()
	if _settings.wireframe != (viewport.debug_draw == Viewport.DEBUG_DRAW_WIREFRAME):
		if _settings.wireframe:
			viewport.debug_draw = Viewport.DEBUG_DRAW_WIREFRAME
		else:
			viewport.debug_draw = Viewport.DEBUG_DRAW_DISABLED
		print("Setting viewport draw mode to ", viewport.debug_draw)
	
	if _settings.antialias == Settings.ANTIALIAS_DISABLED:
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	elif _settings.antialias == Settings.ANTIALIAS_FXAA:
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA


func _unhandled_input(event: InputEvent):
	if _game != null:
		# Let the game handle it
		return
	if event is InputEventKey:
		if event.pressed and not event.is_echo():
			if event.keycode == KEY_ESCAPE:
				_settings_ui.hide()
