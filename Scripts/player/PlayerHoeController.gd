extends RefCounted

# The animation and the soil impact share this clock; no delayed callbacks survive cancellation.
const Motion = preload("res://Assets/Tools/Hoe/HoeMotion.gd")
const DURATION := Motion.DURATION
const IMPACT_TIME := Motion.IMPACT_TIME
const BLEND_TIME := Motion.BLEND_TIME
const CONTACT_LOCAL := Motion.CONTACT_LOCAL
const MAX_GROUND_HEIGHT_DIFFERENCE := 0.12
const MIN_GROUND_UP := 0.9396926 # 20 degrees

var _player: CharacterBody3D
var _visual: Node3D
var _tree: AnimationTree
var _locked_visual_yaw := 0.0
var _active := false
var _elapsed := 0.0
var _impacted := false
var _locked_yaw := 0.0
var _origin := Vector3.ZERO
var _target := Vector3.ZERO
var _target_collider_id := 0
var _tool: HoeTool
var _tool_meshes: Array[MeshInstance3D] = []
var _grip_meshes: Array[MeshInstance3D] = []
var _open_meshes: Array[MeshInstance3D] = []

func _init(player: CharacterBody3D, visual: Node3D, tree: AnimationTree) -> void:
	_player = player
	_visual = visual
	_tree = tree
	if _visual != null:
		_collect_meshes(_visual)
	_set_tool_visible(false)

func is_active() -> bool:
	return _active

func start(tool: HoeTool) -> bool:
	if _active or tool == null or _visual == null:
		return false
	if not _can_act():
		return false
	# Use the character's current facing, independently of the orbit camera.
	var hit := _contact_ground()
	if hit.is_empty() or not _can_plow(hit["position"]):
		return false
	_target = hit["position"]
	_target_collider_id = (hit["collider"] as Object).get_instance_id()
	_origin = _player.global_position
	_locked_yaw = _player.rotation.y
	_locked_visual_yaw = _visual.rotation.y
	_tool = tool
	_elapsed = 0.0
	_impacted = false
	_active = true
	_player.velocity.x = 0.0
	_player.velocity.z = 0.0
	if _has_animation_contract():
		_set_parameter_if_present("parameters/landing_recoil/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		_set_parameter_if_present("parameters/hoe_action_seek/seek_request", 0.0)
	return true

func update(delta: float, equipped: bool, blocked: bool = false) -> void:
	if _active:
		if blocked or not equipped or not _can_act() or _player.global_position.distance_to(_origin) > 0.05:
			cancel()
		else:
			_player.rotation.y = _locked_yaw
			_visual.rotation.y = _locked_visual_yaw
			_elapsed = minf(_elapsed + delta, DURATION)
			var has_animation := _has_animation_contract()
			if has_animation:
				_set_parameter_if_present("parameters/hoe_action_seek/seek_request", _elapsed)
				var weight := minf(_elapsed / BLEND_TIME, (DURATION - _elapsed) / BLEND_TIME)
				_set_parameter_if_present("parameters/hoe_action_blend/blend_amount", clampf(weight, 0.0, 1.0))
			if not _impacted and _elapsed >= IMPACT_TIME:
				_impacted = true
				var hit := _contact_ground()
				if not hit.is_empty() and (hit["collider"] as Object).get_instance_id() == _target_collider_id and (hit["position"] as Vector3).distance_to(_target) < 0.025 and _can_plow(_target):
					_tool.apply_impact(_player, _target)
			if _elapsed >= DURATION:
				_active = false
				_tool = null
	# Show the bound tool only at the authored grip pose, not while blending
	# between the freehand pose and the swing (which would separate the hands).
	var action_weight := 0.0
	if _has_animation_contract():
		action_weight = float(_tree.get("parameters/hoe_action_blend/blend_amount"))
	_set_tool_visible(_active and action_weight > 0.99)

func cancel() -> void:
	_active = false
	_impacted = false
	_tool = null
	if _has_animation_contract():
		_set_parameter_if_present("parameters/hoe_action_blend/blend_amount", 0.0)
	_set_tool_visible(false)

func _can_act() -> bool:
	return _player.is_inside_tree() and _player.is_on_floor() and not _player.is_godmode and _player.is_visible_in_tree() and _player.can_process() and not GameInput.is_gameplay_input_blocked(_player.get_tree())

func _has_animation_contract() -> bool:
	return _tree != null and _tree.get("parameters/hoe_action_blend/blend_amount") != null

func _set_parameter_if_present(parameter_path: String, value: Variant) -> void:
	if _tree != null and _tree.get(parameter_path) != null:
		_tree.set(parameter_path, value)

func _can_plow(position: Vector3) -> bool:
	return GameManager.session != null and GameManager.session.farm != null and GameManager.session.farm.can_plow_at(position)

func _contact_ground() -> Dictionary:
	var contact := _visual.to_global(CONTACT_LOCAL)
	var query := PhysicsRayQueryParameters3D.create(contact + Vector3.UP * 0.2, contact - Vector3.UP * 0.2)
	query.exclude = [_player.get_rid()]
	query.collide_with_areas = true
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	var collider: Object = hit.get("collider")
	if not _is_ground(collider):
		return {}
	var position: Vector3 = hit["position"]
	var normal: Vector3 = hit["normal"]
	if absf(position.y - contact.y) > MAX_GROUND_HEIGHT_DIFFERENCE or normal.dot(Vector3.UP) < MIN_GROUND_UP:
		return {}
	return hit

func _is_ground(collider: Object) -> bool:
	if not collider is Node or collider is EntityView3D or collider is CharacterBody3D or collider is RigidBody3D:
		return false
	var node := collider as Node
	while node != null:
		if node is EntityView3D or node.has_method("interact"):
			return false
		if node.is_in_group("terrain_node") or node.is_in_group("farmland_ground") or node.is_class("Terrain3D"):
			return true
		node = node.get_parent()
	return false

func _collect_meshes(node: Node) -> void:
	if node is MeshInstance3D:
		if String(node.name).begins_with("Hoe_"):
			_tool_meshes.append(node)
		elif String(node.name).begins_with("GripHand_"):
			_grip_meshes.append(node)
		elif String(node.name).begins_with("OpenHand_"):
			_open_meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child)

func _set_tool_visible(show_tool: bool) -> void:
	for mesh in _tool_meshes:
		mesh.visible = show_tool
	for mesh in _grip_meshes:
		mesh.visible = show_tool
	for mesh in _open_meshes:
		mesh.visible = not show_tool
