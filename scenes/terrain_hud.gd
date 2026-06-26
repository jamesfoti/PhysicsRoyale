extends CanvasLayer
## Collapsible debug overlay: FPS and player position. Toggle with F3 or the Debug button.


@onready var _bar: HBoxContainer = $Bar
@onready var _anchor: VBoxContainer = $Bar/Anchor
@onready var _toggle_button: Button = $Bar/Anchor/ToggleButton
@onready var _panel: PanelContainer = $Bar/Anchor/Panel
@onready var _fps: Label = $Bar/Anchor/Panel/Margin/Fields/Fps
@onready var _position: Label = $Bar/Anchor/Panel/Margin/Fields/Position

var _expanded: bool = false

const _MARGIN: float = 8.0


func _ready() -> void:
	_toggle_button.pressed.connect(_on_toggle_pressed)
	_set_expanded(false)
	get_viewport().size_changed.connect(_queue_layout)
	_panel.visibility_changed.connect(_queue_layout)
	_queue_layout()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F3:
		_set_expanded(not _expanded)
		get_viewport().set_input_as_handled()


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
	_queue_layout()


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
	_toggle_button.text = "Debug ▲" if expanded else "Debug ▼"
	_queue_layout()
