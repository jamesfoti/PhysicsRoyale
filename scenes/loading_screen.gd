extends Control
## Shows the game sky while the main scene loads in the background.


const GAME_SCENE_PATH: String = "res://scenes/terrain_test.tscn"

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _status: Label = $UI/Margin/VBox/Status
@onready var _progress: ProgressBar = $UI/Margin/VBox/ProgressBar


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name", "PhysicsRoyale"))
	_set_progress(0, "Loading")
	call_deferred("_begin_load")


func _begin_load() -> void:
	await get_tree().process_frame

	var err: Error = ResourceLoader.load_threaded_request(GAME_SCENE_PATH)
	if err != OK:
		push_warning("[LoadingScreen] Threaded load unavailable, loading synchronously.")
		_load_sync()
		return

	while true:
		var progress_status: Array = []
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			GAME_SCENE_PATH,
			progress_status
		)

		match status:
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, ResourceLoader.THREAD_LOAD_FAILED:
				_load_sync()
				return
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var progress: float = 0.0
				if progress_status.size() > 0:
					progress = progress_status[0] as float
				_set_progress(int(round(progress * 100.0)), _asset_load_message(progress))
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				var game_scene: PackedScene = (
					ResourceLoader.load_threaded_get(GAME_SCENE_PATH) as PackedScene
				)
				if game_scene == null:
					_load_sync()
					return
				_start_game(game_scene)
				return


func _load_sync() -> void:
	_set_progress(0, "Loading game scene")
	await get_tree().process_frame
	var game_scene: PackedScene = load(GAME_SCENE_PATH) as PackedScene
	if game_scene == null:
		_status.text = "Failed to load game"
		return
	_start_game(game_scene)


func _asset_load_message(asset_ratio: float) -> String:
	if asset_ratio < 0.25:
		return "Loading game scene"
	if asset_ratio < 0.55:
		return "Loading characters and props"
	if asset_ratio < 0.85:
		return "Loading shaders and materials"
	return "Loading game resources"


func _set_progress(percent: int, message: String) -> void:
	var clamped: int = clampi(percent, 0, 100)
	_progress.value = float(clamped)
	_status.text = "%s — %d%%" % [message, clamped]


func _start_game(game_scene: PackedScene) -> void:
	_set_progress(100, "Loading")
	var game_root: Node = game_scene.instantiate()
	get_tree().root.add_child(game_root)
	get_tree().current_scene = game_root
	queue_free()
