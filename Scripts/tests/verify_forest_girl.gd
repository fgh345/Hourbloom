extends SceneTree
## godot --headless --path . --script Scripts/tests/verify_forest_girl.gd

const REQUIRED = ["Idle", "Walk", "freehand_idle", "freehand_walk", "freehand_run", "freehand_fall", "jump_start", "landing_soft", "jump_move", "fall_move", "landing_recoil", "pose_lean_left", "pose_lean_right"]
const LOOPING = ["Idle", "Walk", "freehand_idle", "freehand_walk", "freehand_run"]
const GAIT_BONES = ["thigh.L", "thigh.R", "shin.L", "shin.R", "upper_arm.L", "upper_arm.R"]
const GAIT_SAMPLES = 32
const MIN_GAIT_ROTATION = 0.05
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _verify() -> void:
	var packed := load("res://Assets/Characters/ForestGirl/forest_girl.glb") as PackedScene
	_check(packed != null, "Forest girl GLB must load")
	if packed == null:
		quit(1)
		return
	var model := packed.instantiate()
	root.add_child(model)
	var animator := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	_check(animator != null and skeleton != null, "Model must have animator and skeleton")
	if animator == null or skeleton == null:
		model.queue_free()
		quit(1)
		return
	_check(skeleton.get_bone_count() == 16, "Source skeleton must retain 16 bones")
	for bone in ["root", "pelvis", "chest", "head", "hand.L", "hand.R", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R"]:
		_check(skeleton.find_bone(bone) >= 0, "Missing source bone: " + bone)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(model, meshes)
	_check(meshes.size() == 254, "Source mesh count changed: %d" % meshes.size())
	var triangles := 0
	var materials := {}
	var colors := {}
	var has_vertex_colors := false
	var bounds := AABB()
	var first := true
	for mesh in meshes:
		var world_bounds: AABB = _rest_bounds(mesh)
		bounds = world_bounds if first else bounds.merge(world_bounds)
		first = false
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			triangles += int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
			var material := mesh.get_active_material(surface) as StandardMaterial3D
			_check(material != null, "Source material must remain available")
			if material != null:
				materials[material.get_instance_id()] = true
				colors[material.albedo_color.to_html()] = true
				var vertex_colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
				if not vertex_colors.is_empty():
					_check(material.vertex_color_use_as_albedo, "Vertex colors must contribute to imported appearance")
					has_vertex_colors = true
	_check(triangles == 25122, "Source triangle count changed: %d" % triangles)
	_check(materials.size() == 29 and colors.size() > 10, "Source materials and color palette must be preserved: %d / %d" % [materials.size(), colors.size()])
	_check(has_vertex_colors, "Source painted head must retain vertex colors")
	_check(absf(bounds.size.y - 1.20) < 0.025 and absf(bounds.position.y) < 0.025, "Runtime character must stand on ground at 1.20 m: %s" % bounds)
	for name in REQUIRED:
		_check(animator.has_animation(name), "Missing gameplay animation: " + name)
		if not animator.has_animation(name):
			continue
		var clip := animator.get_animation(name)
		_check(clip.loop_mode == (Animation.LOOP_LINEAR if name in LOOPING else Animation.LOOP_NONE), "Incorrect animation loop: " + name)
		var animation_root := animator.get_node(animator.root_node)
		for track in clip.get_track_count():
			var path := clip.track_get_path(track)
			var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			_check(target != null, "Unresolved animation target: %s / %s" % [name, path])
			if target is Skeleton3D and path.get_subname_count() > 0:
				_check(target.find_bone(path.get_subname(0)) >= 0, "Unresolved animation bone: %s" % path)
		for fraction in [0.0, 0.25, 0.5, 0.75, 0.99]:
			_sample(animator, skeleton, name, clip.length * fraction)
	for name in ["Walk", "freehand_walk", "freehand_run"]:
		if animator.has_animation(name):
			_verify_gait_rotation(animator, skeleton, name)
	for name in ["freehand_walk", "freehand_run", "jump_start", "jump_move", "freehand_fall", "fall_move", "landing_soft", "landing_recoil"]:
		if animator.has_animation(name):
			var clip := animator.get_animation(name)
			var before := _sample(animator, skeleton, name, clip.length * 0.05)
			var after := _sample(animator, skeleton, name, clip.length * 0.40)
			var changes := 0
			for bone in before.size():
				if not before[bone].is_equal_approx(after[bone]):
					changes += 1
			_check(changes >= 2, "Animation must move articulated bones: %s (%d changes)" % [name, changes])
	_check(not animator.has_animation("landing_roll"), "Forest girl must not export the removed roll")
	for name in ["jump_start", "jump_move", "freehand_fall", "fall_move", "landing_soft"]:
		if animator.has_animation(name):
			_verify_gait_rotation(animator, skeleton, name)
	_verify_jump_clips(animator, skeleton)
	model.queue_free()
	await process_frame
	var player := (load("res://Scenes/Actors/Player.tscn") as PackedScene).instantiate()
	player.set_physics_process(false)
	root.add_child(player)
	player.set_physics_process(false)
	await process_frame
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	_check(player.get_node_or_null("CharacterVisual/Appearance") == null, "Old atlas expression driver must not modify source materials")
	var tree := player.get_node(player.character_animation_tree_path) as AnimationTree
	_check(tree != null and tree.active, "Player must activate AnimationTree")
	if tree != null:
		tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		_verify_landing_filter(tree, player.find_child("Skeleton3D", true, false) as Skeleton3D)
		for state in ["Idle", "Walk", "Run", "Fall", "LandSoft", "Jump"]:
			tree.set("parameters/movement/transition_request", state)
			tree.advance(0.3)
			_check(tree.get("parameters/movement/current_state") == state, "Cannot transition to " + state)
		var player_skeleton := player.find_child("Skeleton3D", true, false) as Skeleton3D
		var player_animator := player.find_child("AnimationPlayer", true, false) as AnimationPlayer
		_check(player_skeleton != null and player_animator != null, "Player must retain animated skeleton")
		if player_skeleton != null and player_animator != null and player_animator.has_animation("freehand_walk"):
			tree.set("parameters/walk_speed/scale", 1.0)
			tree.set("parameters/movement/transition_request", "Walk")
			# Step through the crossfade before recording a reference, so motion
			# inherited from the preceding Jump state cannot pass this check.
			for settle_step in 12:
				tree.advance(0.05)
			_check(tree.get("parameters/movement/current_state") == "Walk", "Player must play Walk during gait verification")
			var reference := _local_gait_rotations(player_skeleton)
			var excursions := _empty_gait_excursions()
			var cycle := player_animator.get_animation("freehand_walk").length
			for sample_index in range(1, GAIT_SAMPLES + 1):
				tree.advance(cycle / GAIT_SAMPLES)
				_check(tree.get("parameters/movement/current_state") == "Walk", "Player must remain in Walk while sampling gait")
				_measure_gait_excursions(player_skeleton, reference, excursions)
			_assert_gait_excursions(excursions, "Player AnimationTree Walk")
	for tool in player._tool_inventory._tools:
		tool.free()
	player._tool_inventory._tools.clear()
	player._movement_controller = null
	player._interaction_controller = null
	player.queue_free()
	await process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Forest girl verification: %s (%d failures; %d triangles, %d materials)" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size(), triangles, materials.size()])
	quit(0 if _failures.is_empty() else 1)

func _verify_jump_clips(animator: AnimationPlayer, skeleton: Skeleton3D) -> void:
	for pair in [["jump_start", "jump_move"], ["freehand_fall", "fall_move"]]:
		if not animator.has_animation(pair[0]) or not animator.has_animation(pair[1]):
			continue
		_sample(animator, skeleton, pair[0], animator.get_animation(pair[0]).length * 0.5)
		var standing := _local_gait_rotations(skeleton)
		_sample(animator, skeleton, pair[1], animator.get_animation(pair[1]).length * 0.5)
		var moving := _local_gait_rotations(skeleton)
		var difference := 0.0
		for bone in standing.size():
			difference = maxf(difference, standing[bone].angle_to(moving[bone]))
		_check(difference > 0.1, "Standing and moving air poses must visibly differ: %s / %s" % pair)
	if not animator.has_animation("landing_recoil"):
		return
	var recoil := animator.get_animation("landing_recoil")
	# Import sampling can extend the authored 0.20 s by one frame.
	_check(recoil.length <= 0.25, "Landing recoil must finish within a quarter second")
	_sample(animator, skeleton, "landing_recoil", 0.0)
	var reference := _local_gait_rotations(skeleton)
	var excursions := _empty_gait_excursions()
	for sample_index in range(1, GAIT_SAMPLES + 1):
		_sample(animator, skeleton, "landing_recoil", recoil.length * sample_index / GAIT_SAMPLES)
		_measure_gait_excursions(skeleton, reference, excursions)
	for bone in range(4):
		_check(excursions[bone] < 0.001, "Additive recoil must leave %s neutral (%.4f rad)" % [GAIT_BONES[bone], excursions[bone]])
	_check(excursions[4] > 0.02 and excursions[5] > 0.02, "Landing recoil must animate both arms")

func _verify_landing_filter(tree: AnimationTree, skeleton: Skeleton3D) -> void:
	var blend := tree.tree_root as AnimationNodeBlendTree
	var recoil := blend.get_node("landing_recoil") as AnimationNodeOneShot
	_check(recoil != null and recoil.filter_enabled, "Landing recoil must be a filtered OneShot")
	if recoil == null:
		return
	_check(recoil.mix_mode == AnimationNodeOneShot.MIX_MODE_ADD, "Landing recoil must add to locomotion")
	var bone_path := String(tree.get_path_to(skeleton))
	# Filter paths are relative to AnimationTree.root_node, not the tree itself.
	var animation_root := tree.get_node(tree.root_node)
	bone_path = String(animation_root.get_path_to(skeleton))
	for bone in ["chest", "head", "upper_arm.L", "upper_arm.R", "forearm.L", "forearm.R", "hand.L", "hand.R"]:
		_check(recoil.is_path_filtered(NodePath(bone_path + ":" + bone)), "Recoil filter must include upper-body bone " + bone)
	for bone in ["root", "pelvis", "thigh.L", "thigh.R", "shin.L", "shin.R", "foot.L", "foot.R"]:
		_check(not recoil.is_path_filtered(NodePath(bone_path + ":" + bone)), "Recoil filter must leave locomotion bone untouched: " + bone)

func _sample(animator: AnimationPlayer, skeleton: Skeleton3D, name: String, time: float) -> Array[Transform3D]:
	animator.play(name, 0.0)
	animator.seek(time, true)
	animator.advance(0.0)
	var poses: Array[Transform3D] = []
	for index in skeleton.get_bone_count():
		var pose := skeleton.get_bone_global_pose(index)
		_check(pose.is_finite(), "Non-finite bone pose: %s / %s" % [name, skeleton.get_bone_name(index)])
		poses.append(pose)
	return poses

func _verify_gait_rotation(animator: AnimationPlayer, skeleton: Skeleton3D, name: String) -> void:
	_sample(animator, skeleton, name, 0.0)
	var reference := _local_gait_rotations(skeleton)
	var excursions := _empty_gait_excursions()
	var cycle := animator.get_animation(name).length
	for sample_index in range(1, GAIT_SAMPLES + 1):
		_sample(animator, skeleton, name, cycle * sample_index / GAIT_SAMPLES)
		_measure_gait_excursions(skeleton, reference, excursions)
	_assert_gait_excursions(excursions, name)

func _local_gait_rotations(skeleton: Skeleton3D) -> Array[Quaternion]:
	var rotations: Array[Quaternion] = []
	for name in GAIT_BONES:
		var bone := skeleton.find_bone(name)
		_check(bone >= 0, "Missing gait bone: " + name)
		rotations.append(skeleton.get_bone_pose_rotation(bone) if bone >= 0 else Quaternion.IDENTITY)
	return rotations

func _empty_gait_excursions() -> Array[float]:
	var excursions: Array[float] = []
	excursions.resize(GAIT_BONES.size())
	excursions.fill(0.0)
	return excursions

func _measure_gait_excursions(skeleton: Skeleton3D, reference: Array[Quaternion], excursions: Array[float]) -> void:
	# Local rotations exclude inherited root/pelvis translation and parent motion.
	var rotations := _local_gait_rotations(skeleton)
	for bone in GAIT_BONES.size():
		excursions[bone] = maxf(excursions[bone], reference[bone].angle_to(rotations[bone]))

func _assert_gait_excursions(excursions: Array[float], label: String) -> void:
	for bone in GAIT_BONES.size():
		_check(excursions[bone] > MIN_GAIT_ROTATION, "%s must rotate %s locally through the cycle (%.4f rad)" % [label, GAIT_BONES[bone], excursions[bone]])

func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child, meshes)

func _rest_bounds(mesh: MeshInstance3D) -> AABB:
	# Imported skinned vertices are already transformed by inverse bind matrices;
	# the MeshInstance AABB ignores those binds and cannot measure the character.
	var skeleton := mesh.get_node_or_null(mesh.skeleton) as Skeleton3D
	if mesh.skin == null or skeleton == null:
		return mesh.global_transform * mesh.get_aabb()
	var result := AABB()
	var first := true
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var influences := int(weights.size() / vertices.size())
		for vertex in vertices.size():
			var position := Vector3.ZERO
			for influence in influences:
				var offset := vertex * influences + influence
				if weights[offset] <= 0.0:
					continue
				var bind := bones[offset]
				var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0:
					bone = mesh.skin.get_bind_bone(bind)
				position += (skeleton.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
			position = skeleton.global_transform * position
			result = AABB(position, Vector3.ZERO) if first else result.expand(position)
			first = false
	return result
