extends Node3D

const TORCH_SCENE: PackedScene = preload("res://props/torch.tscn")
const PICKAXE_SCENE: PackedScene = preload("res://props/pickaxe.tscn")
const TORCH_ANIM_GLB_PATH: String = "res://character/godot_plush/custom_animations/torch_animations.glb"

const TORCH_BONES: PackedStringArray = [
	"DEF-upper_arm.R",
	"DEF-forearm.R",
	"DEF-hand.R",
]

const PICKAXE_BONES: PackedStringArray = TORCH_BONES

const _TORCH_HOLD_ROTATIONS: Dictionary = {
	"DEF-upper_arm.R": Quaternion(0.786067, -0.500055, 0.253898, -0.25996),
	"DEF-forearm.R": Quaternion(0.752018, -0.656139, 0.01661, 0.060617),
	"DEF-hand.R": Quaternion(0.949144, 0.175933, -0.062537, 0.253501),
}

const _PICKAXE_HOLD_ROTATIONS: Dictionary = {
	"DEF-upper_arm.R": Quaternion(0.829296, -0.380791, 0.22103, -0.344112),
	"DEF-forearm.R": Quaternion(0.771893, -0.629764, 0.021281, 0.084413),
	"DEF-hand.R": Quaternion(0.923756, 0.223486, -0.095665, 0.295935),
}

@export var torch_draw_time: float = 0.25
@export var torch_light_blend: float = 0.3
@export var torch_hide_blend: float = 0.25
@export var pickaxe_draw_time: float = 0.25

@onready var godot_plush_mesh: MeshInstance3D = $GodotPlushModel/Rig/Skeleton3D/GodotPlushMesh
@onready var physical_bone_simulator_3d = %PhysicalBoneSimulator3D
@onready var animation_tree: AnimationTree = %AnimationTree
@onready var state_machine: AnimationNodeStateMachinePlayback = animation_tree.get(
	"parameters/StateMachine/playback"
)
@onready var _skeleton: Skeleton3D = $GodotPlushModel/Rig/Skeleton3D
@onready var _anim_player: AnimationPlayer = $GodotPlushModel/AnimationPlayer

@export var ragdoll: bool = false : set = _set_ragdoll
var tilt: float = 0.0 : set = _set_tilt
var squash_and_stretch = 1.0 : set = _set_squash_and_stretch

var _torch: GameTorch
var _torch_attachment: BoneAttachment3D
var _torch_blend: float = 0.0
var _torch_equipped: bool = false
var _torch_animating: bool = false

var _pickaxe: GamePickaxe
var _pickaxe_attachment: BoneAttachment3D
var _pickaxe_blend: float = 0.0
var _pickaxe_equipped: bool = false
var _pickaxe_animating: bool = false
var _terrain_edit_active: bool = false

signal footstep(intensity: float)
signal waved
signal torch_equipped_changed(equipped: bool)
signal pickaxe_equipped_changed(equipped: bool)


func _ready() -> void:
	_set_ragdoll(ragdoll)
	if OS.has_feature("web"):
		_apply_web_material()
	_register_torch_animations()
	_setup_torch_attachment()
	_setup_pickaxe_attachment()
	get_tree().process_frame.connect(_apply_hand_item_pose)


func _apply_web_material() -> void:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_texture = preload("res://character/godot_plush/material/godot_plush_albedo.png")
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	godot_plush_mesh.material_override = mat


func _set_ragdoll(value: bool) -> void:
	ragdoll = value
	if not is_inside_tree():
		return
	physical_bone_simulator_3d.active = ragdoll
	animation_tree.active = not ragdoll
	if ragdoll:
		physical_bone_simulator_3d.physical_bones_start_simulation()
	else:
		physical_bone_simulator_3d.physical_bones_stop_simulation()


func _set_tilt(value: float) -> void:
	tilt = clamp(value, -1.0, 1.0)
	animation_tree.set("parameters/AddTilt/add_amount", abs(tilt))
	animation_tree.set("parameters/TiltAmount/blend_position", tilt)


func set_state(state_name: String) -> void:
	state_machine.travel(state_name)


func wave() -> void:
	waved.emit()
	animation_tree.set("parameters/WaveOneShot/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func is_waving() -> bool:
	return animation_tree.get("parameters/WaveOneShot/active")


func toggle_torch() -> void:
	if _torch_animating or ragdoll or _terrain_edit_active:
		return
	if _torch_equipped:
		stow_torch()
	else:
		equip_torch()


func equip_torch() -> void:
	if _torch_animating or ragdoll or _terrain_edit_active or _torch_equipped:
		return
	_draw_torch()


func stow_torch() -> void:
	if _torch_animating or not _torch_equipped:
		return
	_stow_torch()


func is_torch_equipped() -> bool:
	return _torch_equipped


func is_torch_busy() -> bool:
	return _torch_animating


func set_terrain_edit_equipped(active: bool) -> void:
	if active == _terrain_edit_active:
		return
	_terrain_edit_active = active
	if active:
		if _torch != null and _torch_equipped:
			_torch.visible = false
		_equip_pickaxe()
	else:
		_unequip_pickaxe()
		if _torch != null and _torch_equipped:
			_torch.visible = true


func is_pickaxe_equipped() -> bool:
	return _pickaxe_equipped


func is_pickaxe_busy() -> bool:
	return _pickaxe_animating


func _equip_pickaxe() -> void:
	if _pickaxe_animating or _pickaxe_equipped:
		return
	_pickaxe_animating = true
	if _pickaxe != null:
		_pickaxe.visible = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_pickaxe_blend, _pickaxe_blend, 1.0, pickaxe_draw_time)
	tween.tween_callback(_finish_equip_pickaxe)


func _unequip_pickaxe() -> void:
	if not _pickaxe_equipped and not _pickaxe_animating:
		_pickaxe_blend = 0.0
		if _pickaxe != null:
			_pickaxe.visible = false
		return
	_pickaxe_animating = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_pickaxe_blend, _pickaxe_blend, 0.0, pickaxe_draw_time)
	tween.tween_callback(_finish_unequip_pickaxe)


func _finish_equip_pickaxe() -> void:
	_pickaxe_equipped = true
	_pickaxe_animating = false
	if _pickaxe != null:
		_pickaxe.visible = true
	pickaxe_equipped_changed.emit(true)


func _finish_unequip_pickaxe() -> void:
	_pickaxe_equipped = false
	_pickaxe_animating = false
	if _pickaxe != null:
		_pickaxe.visible = false
	pickaxe_equipped_changed.emit(false)


func _set_pickaxe_blend(value: float) -> void:
	_pickaxe_blend = value
	if _pickaxe == null:
		return
	if _pickaxe_animating and not _pickaxe_equipped:
		_pickaxe.visible = value > 0.05
	elif _pickaxe_animating and _pickaxe_equipped and value <= torch_hide_blend:
		_pickaxe.visible = false


func _draw_torch() -> void:
	_torch_animating = true
	if _torch != null:
		_torch.visible = true
	var tween := create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_torch_blend, _torch_blend, 1.0, torch_draw_time)
	tween.tween_callback(_finish_draw_torch)


func _stow_torch() -> void:
	_torch_animating = true
	if _torch != null:
		_torch.set_lit(false)
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.tween_method(_set_torch_blend, _torch_blend, 0.0, torch_draw_time)
	tween.tween_callback(_finish_stow_torch)


func _finish_draw_torch() -> void:
	_torch_equipped = true
	_torch_animating = false
	if _torch != null:
		_torch.visible = true
		_torch.set_lit(true)
	torch_equipped_changed.emit(true)


func _finish_stow_torch() -> void:
	_torch_equipped = false
	_torch_animating = false
	if _torch != null:
		_torch.visible = false
	torch_equipped_changed.emit(false)


func _set_torch_blend(value: float) -> void:
	_torch_blend = value
	if _torch == null:
		return
	if _torch_animating and not _torch_equipped:
		if value >= torch_light_blend:
			_torch.set_lit(true)
	elif _torch_animating and _torch_equipped and value <= torch_hide_blend:
		_torch.visible = false


func _apply_hand_item_pose() -> void:
	if _skeleton == null:
		return
	if _pickaxe_blend > 0.0001:
		_apply_arm_pose_blend(PICKAXE_BONES, _PICKAXE_HOLD_ROTATIONS, _pickaxe_blend)
	elif _torch_blend > 0.0001:
		_apply_arm_pose_blend(TORCH_BONES, _TORCH_HOLD_ROTATIONS, _torch_blend)


func _apply_arm_pose_blend(
	bones: PackedStringArray,
	hold_rotations: Dictionary,
	blend: float
) -> void:
	for bone_name: String in bones:
		var bone_idx: int = _skeleton.find_bone(bone_name)
		if bone_idx < 0:
			continue
		var animated: Quaternion = _skeleton.get_bone_pose_rotation(bone_idx)
		var hold: Quaternion = hold_rotations[bone_name] as Quaternion
		_skeleton.set_bone_pose_rotation(bone_idx, animated.slerp(hold, blend))


func _setup_torch_attachment() -> void:
	_torch_attachment = BoneAttachment3D.new()
	_torch_attachment.bone_name = "DEF-hand.R"
	_skeleton.add_child(_torch_attachment)
	_torch = TORCH_SCENE.instantiate() as GameTorch
	_torch_attachment.add_child(_torch)
	_torch.position = Vector3(0.0, 0.08, 0.02)
	_torch.rotation_degrees = Vector3(95.0, 5.0, -90.0)
	_torch.scale = Vector3.ONE * 0.85
	_torch.visible = false


func _setup_pickaxe_attachment() -> void:
	_pickaxe_attachment = BoneAttachment3D.new()
	_pickaxe_attachment.bone_name = "DEF-hand.R"
	_skeleton.add_child(_pickaxe_attachment)
	_pickaxe = PICKAXE_SCENE.instantiate() as GamePickaxe
	_pickaxe_attachment.add_child(_pickaxe)
	_pickaxe.position = Vector3(0.0, 0.04, 0.0)
	_pickaxe.rotation_degrees = Vector3(88.0, 12.0, -92.0)
	_pickaxe.scale = Vector3.ONE * 0.75
	_pickaxe.visible = false


func _register_torch_animations() -> void:
	if not ResourceLoader.exists(TORCH_ANIM_GLB_PATH):
		return
	var lib: AnimationLibrary = _anim_player.get_animation_library("custom_animations")
	if lib == null:
		return
	if lib.has_animation("torch_pull_out"):
		return
	var packed: PackedScene = load(TORCH_ANIM_GLB_PATH) as PackedScene
	if packed == null:
		return
	var temp: Node = packed.instantiate()
	var src_player: AnimationPlayer = temp.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if src_player == null:
		temp.queue_free()
		return
	for anim_name: String in ["torch_pull_out", "torch_hold", "torch_put_away"]:
		if not src_player.has_animation(anim_name):
			continue
		var anim: Animation = src_player.get_animation(anim_name)
		lib.add_animation(anim_name, anim)
	temp.queue_free()


func _set_squash_and_stretch(value: float) -> void:
	squash_and_stretch = value
	var negative = 1.0 + (1.0 - squash_and_stretch)
	godot_plush_mesh.scale = Vector3(negative, squash_and_stretch, negative)


func emit_footstep(intensity: float = 1.0) -> void:
	footstep.emit(intensity)
