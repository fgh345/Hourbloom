extends SceneTree
## Run: godot --headless --path . --script Scripts/tests/verify_farmer_girl.gd

const ANIMATIONS = ["Idle", "Walk", "Run", "Pickup", "Carry", "Watering", "Hoe", "Plant", "Wave", "freehand_idle", "freehand_walk", "freehand_run", "freehand_fall", "jump_start", "landing_soft", "landing_roll", "pose_lean_left", "pose_lean_right", "wave", "carry_harvest", "watering", "thinking"]
const LOOPING = ["Idle", "Walk", "Run", "Watering", "Hoe", "freehand_idle", "freehand_walk", "freehand_run", "freehand_fall", "carry_harvest", "watering", "thinking"]
const MESHES = ["CHR_Body", "CHR_Head", "CHR_Hair", "CHR_Hat", "CHR_Scarf", "CHR_Clothes", "CHR_Boots", "CHR_Backpack", "CHR_Eyes"]
const APPEARANCE = preload("res://Scripts/player/CharacterAppearance.gd")
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _verify() -> void:
	var packed := load("res://Assets/Characters/FarmerGirl/farmer_girl.glb") as PackedScene
	_check(packed != null, "Character GLB must load")
	if packed == null:
		quit(1)
		return
	var model := packed.instantiate()
	root.add_child(model)
	var animator := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_check(animator != null and skeleton != null, "Character must have animator and skeleton")
	if animator == null or skeleton == null:
		model.queue_free()
		quit(1)
		return
	for mesh_name in MESHES:
		_check(model.find_child(mesh_name, true, false) is MeshInstance3D, "Missing character mesh: %s" % mesh_name)
	for bone in ["root", "pelvis", "spine_01", "spine_02", "neck", "head", "socket_hand_R", "socket_back", "socket_head"]:
		_check(skeleton.find_bone(bone) >= 0, "Missing bone: %s" % bone)
	var mesh_nodes: Array[MeshInstance3D] = []
	_collect_meshes(model, mesh_nodes)
	var triangles := 0
	for mesh_node in mesh_nodes:
		for surface in mesh_node.mesh.get_surface_count():
			var arrays := mesh_node.mesh.surface_get_arrays(surface)
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			triangles += (indices.size() if not indices.is_empty() else vertices.size()) / 3
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			for weight in weights:
				_check(is_finite(weight) and weight >= 0.0 and weight <= 1.0001, "Invalid skin weight: %s" % mesh_node.name)
			var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			_check(uv.size() == vertices.size(), "Missing UVs: %s" % mesh_node.name)
			for point in uv:
				_check(point.is_finite() and point.x >= 0.0 and point.x <= 1.0 and point.y >= 0.0 and point.y <= 1.0, "UV outside atlas: %s" % mesh_node.name)
			if not weights.is_empty():
				var influences := int(weights.size() / vertices.size())
				for vertex in vertices.size():
					var total := 0.0
					var active := 0
					for influence in influences:
						var weight := weights[vertex * influences + influence]
						total += weight
						if weight > 0.00001:
							active += 1
					_check(active <= 4 and absf(total - 1.0) < 0.001, "Invalid weight normalization/influence limit: %s" % mesh_node.name)
	_check(triangles <= 5000 and triangles > 0, "Triangle budget exceeded: %d" % triangles)
	for name in ANIMATIONS:
		_check(animator.has_animation(name), "Missing animation: %s" % name)
		if not animator.has_animation(name):
			continue
		var clip := animator.get_animation(name)
		var expected_loop := Animation.LOOP_LINEAR if name in LOOPING else Animation.LOOP_NONE
		_check(clip.loop_mode == expected_loop, "Incorrect loop mode: %s" % name)
		var animation_root := animator.get_node(animator.root_node)
		for index in clip.get_track_count():
			var path := clip.track_get_path(index)
			var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			_check(target != null, "Missing track target: %s / %s" % [name, path])
			if target is Skeleton3D and path.get_subname_count() > 0:
				_check(target.find_bone(path.get_subname(0)) >= 0, "Missing bone: %s / %s" % [name, path])
		animator.play(name)
		for fraction in [0.0, 0.25, 0.5, 0.75, 0.99]:
			animator.seek(clip.length * fraction, true)
			_check_bones(skeleton, name)
	# Validate useful action positions, rather than only finite matrices.
	for clip_name in ["Carry", "Plant", "Watering"]:
		animator.play(clip_name, 0.0)
		animator.seek(0.5, true)
		animator.advance(0.0)
		var hand := skeleton.get_bone_global_pose(skeleton.find_bone("hand_R")).origin
		if clip_name == "Plant":
			_check(hand.y < 0.20 and hand.z > 0.15, "Plant must reach toward the ground")
		else:
			_check(hand.y > 0.50 and hand.z > 0.15, "%s must hold the hand in front of the body" % clip_name)
	model.queue_free()
	await process_frame
	var player := (load("res://Scenes/Actors/Player.tscn") as PackedScene).instantiate()
	player.set_physics_process(false)
	root.add_child(player)
	player.set_physics_process(false)
	await process_frame
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	var tree := player.get_node(player.character_animation_tree_path) as AnimationTree
	_check(tree != null and tree.active, "Player ready must activate AnimationTree")
	if tree != null:
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		var player_animator := player.find_child("AnimationPlayer", true, false) as AnimationPlayer
		for clip_name in ["jump_move", "fall_move", "landing_recoil"]:
			_check(player_animator.has_animation(clip_name), "Active player must have motion clip " + clip_name)
		for state in ["Idle", "Walk", "Run", "Fall", "LandSoft", "Jump"]:
			tree.set("parameters/movement/transition_request", state)
			tree.advance(0.3)
			_check(tree.get("parameters/movement/current_state") == state, "Cannot transition to %s" % state)
			_check_bones(player.find_child("Skeleton3D", true, false), state)
	var appearance_model := packed.instantiate()
	root.add_child(appearance_model)
	var appearance := APPEARANCE.new()
	appearance_model.add_child(appearance)
	_check(appearance._face_material != null, "Appearance must discover character atlas")
	appearance.set_process(false)
	var other_model := packed.instantiate()
	root.add_child(other_model)
	var other_appearance := APPEARANCE.new()
	other_model.add_child(other_appearance)
	other_appearance.set_process(false)
	_check(appearance._face_material != other_appearance._face_material, "Expression material must be instance-local")
	for expression in APPEARANCE.EXPRESSIONS:
		appearance.set_expression(expression)
		_check(appearance._face_material.get_shader_parameter("face_row") == APPEARANCE.EXPRESSIONS.find(expression), "Expression atlas row: %s" % expression)
		_check(other_appearance._face_material.get_shader_parameter("face_row") == 0, "Expression leaked to second character")
	appearance.set_expression(&"Neutral")
	appearance._blink_wait = 0.0
	appearance._process(0.016)
	_check(appearance._face_material.get_shader_parameter("blink") == true, "Automatic blink must close eyes")
	appearance._process(appearance.blink_duration)
	_check(appearance._face_material.get_shader_parameter("blink") == false, "Automatic blink must reopen eyes")
	other_model.queue_free()
	appearance_model.queue_free()
	# Player tools are unparented Nodes; explicitly release this test fixture.
	for tool in player._tool_inventory._tools:
		tool.free()
	player._tool_inventory._tools.clear()
	player._movement_controller = null
	player._interaction_controller = null
	player.queue_free()
	await process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Farmer girl verification: %s (%d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _check_bones(skeleton: Skeleton3D, context: String) -> void:
	for index in skeleton.get_bone_count():
		_check(skeleton.get_bone_global_pose(index).is_finite(), "Non-finite bone pose: %s / %s" % [context, skeleton.get_bone_name(index)])

func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("CHR_"):
		meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child, meshes)
