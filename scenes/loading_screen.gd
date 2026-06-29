extends Control
## Shows the game sky while the main scene loads in the background.


const GAME_SCENE_PATH: String = "res://scenes/terrain_test.tscn"
const ASSET_PROGRESS_WEIGHT: float = 0.35
const DISPLAY_SPEED: float = 0.42
const DISPLAY_CATCHUP_EPSILON: float = 0.004
const ASSET_IDLE_CREEP_SPEED: float = 0.05
const ASSET_IDLE_CREEP_CAP: float = 0.92

@onready var _title: Label = $UI/Margin/VBox/Title
@onready var _status: Label = $UI/Margin/VBox/Status
@onready var _progress: ProgressBar = $UI/Margin/VBox/ProgressBar

var _game_scene: PackedScene
var _entering_game: bool = false
var _loading_assets: bool = false
var _last_reported_asset_ratio: float = 0.0
var _target_ratio: float = 0.0
var _display_ratio: float = 0.0
var _status_message: String = "Loading startup"


func _ready() -> void:
	_title.text = str(ProjectSettings.get_setting("application/config/name", "PhysicsRoyale"))
	_set_target_progress(0.0, "Loading startup")
	set_process(true)
	call_deferred("_begin_load")


func _process(delta: float) -> void:
	_display_ratio = move_toward(_display_ratio, _target_ratio, DISPLAY_SPEED * delta)

	if _loading_assets:
		var reported_cap: float = _last_reported_asset_ratio * ASSET_PROGRESS_WEIGHT
		var idle_cap: float = ASSET_PROGRESS_WEIGHT * ASSET_IDLE_CREEP_CAP
		if _target_ratio < reported_cap:
			_target_ratio = reported_cap
		elif _target_ratio < idle_cap:
			_target_ratio = minf(_target_ratio + ASSET_IDLE_CREEP_SPEED * delta, idle_cap)

	_apply_display()


func _begin_load() -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	_loading_assets = true
	var err: Error = ResourceLoader.load_threaded_request(GAME_SCENE_PATH)
	if err != OK:
		push_warning("[LoadingScreen] Threaded load unavailable, loading synchronously.")
		await _load_sync()
		return

	while not _entering_game:
		var progress_status: Array = []
		var status: ResourceLoader.ThreadLoadStatus = ResourceLoader.load_threaded_get_status(
			GAME_SCENE_PATH,
			progress_status
		)

		match status:
			ResourceLoader.THREAD_LOAD_INVALID_RESOURCE, ResourceLoader.THREAD_LOAD_FAILED:
				await _load_sync()
				return
			ResourceLoader.THREAD_LOAD_IN_PROGRESS:
				var progress: float = 0.0
				if progress_status.size() > 0:
					progress = progress_status[0] as float
				_last_reported_asset_ratio = progress
				_set_asset_progress(progress)
				await get_tree().process_frame
			ResourceLoader.THREAD_LOAD_LOADED:
				_game_scene = ResourceLoader.load_threaded_get(GAME_SCENE_PATH) as PackedScene
				if _game_scene == null:
					await _load_sync()
					return
				_loading_assets = false
				_set_target_progress(ASSET_PROGRESS_WEIGHT, "Loading game scene")
				await _wait_until_display_reaches(ASSET_PROGRESS_WEIGHT)
				await _finish_loading()
				return


func _load_sync() -> void:
	_loading_assets = false
	_set_target_progress(0.0, "Loading game scene")
	await get_tree().process_frame
	_game_scene = load(GAME_SCENE_PATH) as PackedScene
	if _game_scene == null:
		_status.text = "Failed to load game"
		return
	_set_target_progress(ASSET_PROGRESS_WEIGHT, "Loading game scene")
	await _wait_until_display_reaches(ASSET_PROGRESS_WEIGHT)
	await _finish_loading()


func _set_asset_progress(asset_ratio: float) -> void:
	var clamped: float = clampf(asset_ratio, 0.0, 1.0)
	_set_target_progress(clamped * ASSET_PROGRESS_WEIGHT, _asset_load_message(clamped))


func _asset_load_message(asset_ratio: float) -> String:
	if asset_ratio < 0.25:
		return "Loading game scene"
	if asset_ratio < 0.55:
		return "Loading characters and props"
	if asset_ratio < 0.85:
		return "Loading shaders and materials"
	return "Loading game resources"


func _set_target_progress(ratio: float, message: String) -> void:
	_target_ratio = clampf(ratio, 0.0, 1.0)
	_status_message = message
	_apply_display()


func _apply_display() -> void:
	var percent: int = int(round(_display_ratio * 100.0))
	_progress.value = float(percent)
	_status.text = "%s — %d%%" % [_status_message, percent]


func _wait_until_display_reaches(ratio: float) -> void:
	var goal: float = clampf(ratio, 0.0, 1.0)
	_target_ratio = maxf(_target_ratio, goal)
	while _display_ratio < goal - DISPLAY_CATCHUP_EPSILON:
		await get_tree().process_frame


func _on_terrain_rebuild_progress(completed_chunks: int, total_chunks: int) -> void:
	if total_chunks <= 0:
		return
	var terrain_ratio: float = float(completed_chunks) / float(total_chunks)
	var overall: float = ASSET_PROGRESS_WEIGHT + terrain_ratio * (1.0 - ASSET_PROGRESS_WEIGHT)
	var message: String = "Loading planet terrain (%d / %d chunks)" % [
		completed_chunks, total_chunks
	]
	_set_target_progress(overall, message)


func _finish_loading() -> void:
	if _entering_game or _game_scene == null:
		return
	_entering_game = true

	_set_target_progress(ASSET_PROGRESS_WEIGHT, "Loading world")
	await _wait_until_display_reaches(ASSET_PROGRESS_WEIGHT)

	var game_root: Node = _game_scene.instantiate()
	var terrain: TerrainWorldV2 = game_root.get_node_or_null("TerrainWorld") as TerrainWorldV2
	var wait_for_terrain: bool = terrain != null and terrain.rebuild_on_ready

	if wait_for_terrain and not terrain.is_initial_rebuild_complete():
		terrain.initial_rebuild_progress.connect(_on_terrain_rebuild_progress)

	get_tree().root.add_child(game_root)
	await get_tree().process_frame

	if wait_for_terrain and not terrain.is_initial_rebuild_complete():
		_set_target_progress(ASSET_PROGRESS_WEIGHT, "Loading planet terrain")
		await terrain.initial_rebuild_finished
		if terrain.initial_rebuild_progress.is_connected(_on_terrain_rebuild_progress):
			terrain.initial_rebuild_progress.disconnect(_on_terrain_rebuild_progress)

	_set_target_progress(1.0, "Loading — ready to play")
	await _wait_until_display_reaches(1.0)
	await get_tree().process_frame

	var loading_screen: Node = get_tree().current_scene
	get_tree().current_scene = game_root
	if loading_screen != null and loading_screen != game_root:
		loading_screen.queue_free()
