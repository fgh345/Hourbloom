extends RefCounted
## A single clock for short character actions. Gameplay effects fire once at contact.

const DURATIONS := {&"Seed": 0.72, &"Harvest": 0.72, &"Pickup": 0.64, &"Drop": 0.64, &"Interact": 0.55}
const CONTACT := {&"Seed": 0.40, &"Harvest": 0.43, &"Pickup": 0.38, &"Drop": 0.38, &"Interact": 0.30}
const BLEND := 0.08

var _player: CharacterBody3D
var _visual: Node3D
var _tree: AnimationTree
var _kind: StringName = &""
var _revision := 0
var _elapsed := 0.0
var _committed := false
var _origin := Vector3.ZERO
var _yaw := 0.0
var _visual_yaw := 0.0
var _effect: Callable
var _valid: Callable

func _init(player: CharacterBody3D, visual: Node3D, tree: AnimationTree) -> void:
	_player = player
	_visual = visual
	_tree = tree

func is_active() -> bool:
	return _kind != &""

func start(kind: StringName, effect: Callable, valid: Callable = Callable()) -> bool:
	if is_active() or not DURATIONS.has(kind) or _tree == null or _visual == null or not effect.is_valid():
		return false
	if not _player.is_inside_tree() or not _player.is_on_floor() or _player.is_godmode or GameInput.is_gameplay_input_blocked(_player.get_tree()):
		return false
	if _tree.get("parameters/basic_action_blend/blend_amount") == null:
		return false
	_revision += 1
	_kind = kind
	_effect = effect
	_valid = valid
	_elapsed = 0.0
	_committed = false
	_origin = _player.global_position
	_yaw = _player.rotation.y
	_visual_yaw = _visual.rotation.y
	_player.velocity.x = 0.0
	_player.velocity.z = 0.0
	_tree.set("parameters/landing_recoil/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_tree.set("parameters/basic_action/transition_request", String(kind))
	_tree.set("parameters/basic_action_seek/seek_request", 0.0)
	return true

func update(delta: float) -> void:
	if not is_active():
		return
	if not _player.is_on_floor() or _player.is_godmode or not _player.is_visible_in_tree() or GameInput.is_gameplay_input_blocked(_player.get_tree()) or _player.global_position.distance_to(_origin) > 0.05:
		cancel()
		return
	_player.rotation.y = _yaw
	_visual.rotation.y = _visual_yaw
	_elapsed = minf(_elapsed + delta, DURATIONS[_kind])
	_tree.set("parameters/basic_action_seek/seek_request", _elapsed)
	var weight := minf(_elapsed / BLEND, (DURATIONS[_kind] - _elapsed) / BLEND)
	_tree.set("parameters/basic_action_blend/blend_amount", clampf(weight, 0.0, 1.0))
	if not _committed and _elapsed >= CONTACT[_kind]:
		_committed = true
		var revision := _revision
		var is_valid: bool = not _valid.is_valid() or _valid.call()
		if _revision != revision:
			return
		if is_valid:
			_effect.call()
			if _revision != revision:
				return
	if _elapsed >= DURATIONS[_kind]:
		cancel()

func cancel() -> void:
	_revision += 1
	_kind = &""
	_effect = Callable()
	_valid = Callable()
	_committed = false
	if _tree != null and _tree.get("parameters/basic_action_blend/blend_amount") != null:
		_tree.set("parameters/basic_action_blend/blend_amount", 0.0)
