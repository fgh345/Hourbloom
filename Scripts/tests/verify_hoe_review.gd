extends SceneTree
## Validate the exported animation in the actual Godot importer.
const Motion = preload("res://Assets/Tools/Hoe/HoeMotion.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("verify")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func verify() -> void:
	var resource_path := "res://Assets/Tools/Hoe/forest_girl_tools.glb" if "--runtime" in OS.get_cmdline_user_args() else "res://Assets/Tools/Hoe/character_with_hoe.glb"
	var packed := load(resource_path) as PackedScene
	check(packed != null, "Combined preview must load")
	if packed == null:
		quit(1)
		return
	var model := packed.instantiate()
	root.add_child(model)
	var animator := model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	var skeleton := model.find_child("Skeleton3D", true, false) as Skeleton3D
	check(animator != null and skeleton != null, "Preview requires animator and skeleton")
	if animator == null or skeleton == null:
		model.free()
		quit(1)
		return
	check(animator.has_animation("Hoe"), "Hoe animation must be present")
	if not animator.has_animation("Hoe"):
		model.free()
		quit(1)
		return
	var duration := animator.get_animation("Hoe").length
	check(absf(duration - Motion.DURATION) < .002, "Hoe must retain authored timing: %.5f" % duration)
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	animator.play("Hoe")
	var grips: Array[MeshInstance3D] = []
	for side in ["L", "R"]:
		var grip := model.find_child("Hoe_ClothGrip_" + side, true, false) as MeshInstance3D
		check(grip != null, "Export requires visible grip wrap " + side)
		grips.append(grip)
	var blade := model.find_child("Hoe_ForgedBlade", true, false) as MeshInstance3D
	check(blade != null, "Export requires visible blade")
	var edge := model.find_child("Hoe_SharpenedEdge", true, false) as MeshInstance3D
	var socket := model.find_child("Hoe_IronSocket", true, false) as MeshInstance3D
	check(edge != null and socket != null, "Hoe requires separate cutting edge and socket")
	var boots := model.find_children("Boot*", "MeshInstance3D", true, false)
	check(not boots.is_empty(), "Find boots for ground clearance validation")
	var arms: Array[MeshInstance3D] = []
	for side in ["L", "R"]:
		var arm := model.find_child("HoeArm_" + side + "_Continuous", true, false) as MeshInstance3D
		check(arm != null, "Use connected sleeve/elbow/wrist geometry for " + side)
		arms.append(arm)
	var maximum_grip_error := 0.0
	var limb_lengths: Dictionary = {}
	var first: Dictionary = {}
	var movement: Dictionary = {}
	var knee_low := INF
	var knee_high := -INF
	var chest_motion := 0.0
	var first_chest := Quaternion.IDENTITY
	var contact_runs := 0
	var was_contact := false
	var recovery_socket_high := -INF
	# Sample the whole clip, then seek each authored phase exactly below.
	for sample in 121:
		var time := duration * sample / 120.0
		animator.seek(time, true)
		skeleton.force_update_all_bone_transforms()
		if sample in [0, 30, 60, 90, 120]:
			for arm in arms:
				if arm != null:
					verify_continuous_arm(arm, skeleton)
		for bone in skeleton.get_bone_count():
			var pose := skeleton.get_bone_global_pose(bone)
			check(pose.is_finite(), "Exported bone transforms must remain finite")
			var name := skeleton.get_bone_name(bone)
			if sample == 0:
				first[name] = pose
				movement[name] = 0.0
			movement[name] = maxf(movement[name], pose.origin.distance_to(first[name].origin))
		for index in grips.size():
			if grips[index] == null:
				continue
			var center := vertex_center(grips[index], skeleton)
			var wrist := bone_position(skeleton, "hand.L" if index == 0 else "hand.R")
			# Authored wrist offset from wrap center: 41 mm lateral, 6 mm axial.
			var error := absf(wrist.distance_to(center) - Vector2(.041, .006).length())
			maximum_grip_error = maxf(maximum_grip_error, error)
			check(error < .008, "Visible wrap must stay inside fist (%.4f m error at %.3f s)" % [error, time])
		for side in ["L", "R"]:
			for chain in [["upper_arm.", "forearm.", "hand."], ["thigh.", "shin.", "foot."]]:
				var start := bone_position(skeleton, chain[0] + side)
				var joint := bone_position(skeleton, chain[1] + side)
				var end := bone_position(skeleton, chain[2] + side)
				var lengths := Vector2(start.distance_to(joint), joint.distance_to(end))
				var key: String = chain[0] + side
				if sample == 0:
					limb_lengths[key] = lengths
				check(lengths.distance_to(limb_lengths[key]) < .002, "Arm and leg segments must not stretch: %s at %.3f s, lengths %s vs %s (%.6f m)" % [key, time, lengths, limb_lengths[key], lengths.distance_to(limb_lengths[key])])
				if chain[0] == "thigh.":
					var knee_angle := (start - joint).angle_to(end - joint)
					knee_low = minf(knee_low, knee_angle)
					knee_high = maxf(knee_high, knee_angle)
		var chest := skeleton.get_bone_global_pose(skeleton.find_bone("chest")).basis.orthonormalized().get_rotation_quaternion()
		if sample == 0:
			first_chest = chest
		chest_motion = maxf(chest_motion, first_chest.angle_to(chest))
		if blade != null:
			var low := lowest_vertex(blade, skeleton)
			check(low > -.015, "Blade must not penetrate stage: %.4f at %.3f s" % [low, time])
			var contact := low < .012
			if contact and not was_contact:
				contact_runs += 1
			was_contact = contact
		if time >= Motion.IMPACT_TIME and socket != null:
			recovery_socket_high = maxf(recovery_socket_high, vertex_center(socket, skeleton).y)
		for boot in boots:
			check(lowest_vertex(boot as MeshInstance3D, skeleton) > -.015, "Boot sole must not penetrate stage")
	check(contact_runs == 1, "Swing has one continuous ground-contact phase, got " + str(contact_runs))
	check(chest_motion > .12, "Torso participates in the strike: %.3f radians" % chest_motion)
	check(knee_high - knee_low > .08, "Knees bend and recover through the strike: %.3f radians" % (knee_high - knee_low))
	check(maxf(movement.get("foot.L", 0.0), movement.get("foot.R", 0.0)) > .025, "Weight transfer includes foot movement")
	print("Maximum imported grip error: %.6f m" % maximum_grip_error)
	# Check the illustrated five phases using exact authored times; the contact
	# assertion must not depend on a sample index or the previous clip duration.
	var phase_points: Dictionary = {}
	var phase_times := {"ready": Motion.READY_TIME, "raised": Motion.RAISED_TIME, "swing": Motion.SWING_TIME, "impact": Motion.IMPACT_TIME, "follow": Motion.FOLLOW_TIME}
	for phase in phase_times:
		var phase_time: float = phase_times[phase]
		animator.seek(phase_time, true)
		skeleton.force_update_all_bone_transforms()
		if edge == null or socket == null or blade == null:
			continue
		phase_points[phase] = {"socket": vertex_center(socket, skeleton), "edge": vertex_center(edge, skeleton), "low": lowest_vertex(blade, skeleton)}
		check(vertex_center(grips[0], skeleton).distance_to(vertex_center(grips[1], skeleton)) > .12, "Keep two-hand grip spacing at " + phase)
	if phase_points.size() == 5:
		check(phase_points.raised.socket.y > phase_points.ready.socket.y + .25, "Anticipation visibly raises the tool from ready")
		check(phase_points.swing.socket.y < phase_points.raised.socket.y - .05, "Downswing descends from anticipation")
		check(absf(phase_points.impact.low) < .012, "Blade actually touches ground at the authored impact")
		check(phase_points.follow.low > phase_points.impact.low + .025, "Short recovery clears the blade from the soil")
		check(recovery_socket_high < phase_points.ready.socket.y + .06, "Recovery stays low without a second high lift")
		var actual_contact: Vector3 = phase_points.impact.edge
		check(Vector2(actual_contact.x, actual_contact.z).distance_to(Vector2(Motion.CONTACT_LOCAL.x, Motion.CONTACT_LOCAL.z)) < .015, "Visual sharp edge lands at the gameplay contact point")
		var cutting_direction: Vector3 = phase_points.impact.edge - phase_points.impact.socket
		check(cutting_direction.y < -.10, "Sharp edge leads below the socket")
		check(-cutting_direction.normalized().y > .70, "Blade enters soil steeply, edge first")
	# Sample between baked keys too, so interpolation cannot hide a recovery twist.
	var maximum_roll := 0.0
	for sample in 301:
		animator.seek(duration * sample / 300.0, true)
		skeleton.force_update_all_bone_transforms()
		var tool_pose := skeleton.get_bone_global_pose(skeleton.find_bone("hoe_tool"))
		var palm_normal := (tool_pose.basis * Vector3.UP).normalized()
		for side in ["L", "R"]:
			var forearm := skeleton.find_bone("forearm." + side)
			var hand := skeleton.find_bone("hand." + side)
			var rest := skeleton.get_bone_global_rest(forearm)
			var pose := skeleton.get_bone_global_pose(forearm)
			var rest_axis := (skeleton.get_bone_global_rest(hand).origin - rest.origin).normalized()
			var axis := (skeleton.get_bone_global_pose(hand).origin - pose.origin).normalized()
			var radial := (pose.basis * rest.basis.inverse() * rest_axis.cross(Vector3.FORWARD)).normalized()
			var target := palm_normal.cross(axis)
			check(target.length() > .25, "Palm reference must remain stable throughout swing")
			target = target.normalized()
			var roll := absf(atan2(axis.dot(radial.cross(target)), radial.dot(target)))
			maximum_roll = maxf(maximum_roll, rad_to_deg(roll))
	check(maximum_roll < .5, "Forearm must follow grip without inward wrist twist: %.4f degrees" % maximum_roll)
	print("Maximum swing wrist roll: %.4f degrees" % maximum_roll)
	for name in ["hand.L", "hand.R", "hoe_tool"]:
		check(skeleton.find_bone(name) >= 0, "Missing animated bone: " + name)
		check(movement.get(name, 0.0) > .10, "Export must animate " + name)
	var tool := load("res://Assets/Tools/Hoe/hoe.glb") as PackedScene
	check(tool != null, "Standalone reusable hoe must load")
	model.free()
	var stage = load("res://Scenes/Tools/HoeReview.tscn").instantiate()
	root.add_child(stage)
	stage.capture_mode = true
	stage.set_view(PI / 2)
	for sample in 240:
		stage.advance_preview(1.0 / 60.0)
	stage.free()
	print("HOE_REVIEW_OK" if failures.is_empty() else "HOE_REVIEW_FAILED: %s" % str(failures))
	quit(0 if failures.is_empty() else 1)

func deformed_vertices(mesh: MeshInstance3D, skeleton: Skeleton3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var stride := bones.size() / vertices.size()
		for index in vertices.size():
			var point := Vector3.ZERO
			for offset in int(stride):
				var weight := weights[index * int(stride) + offset]
				if weight == 0:
					continue
				var bind := bones[index * int(stride) + offset]
				var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0:
					bone = mesh.skin.get_bind_bone(bind)
				point += skeleton.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[index] * weight
			result.append(skeleton.global_transform * point)
	return result

func vertex_center(mesh: MeshInstance3D, skeleton: Skeleton3D) -> Vector3:
	var points := deformed_vertices(mesh, skeleton)
	var center := Vector3.ZERO
	for point in points:
		center += point
	return center / points.size()

func bone_position(skeleton: Skeleton3D, name: String) -> Vector3:
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name)).origin

func verify_continuous_arm(mesh: MeshInstance3D, skeleton: Skeleton3D) -> void:
	# glTF splits material/normal boundaries; weld coincident posed positions
	# before checking the visible surface remains one closed component.
	var points := deformed_vertices(mesh, skeleton)
	var offset := 0
	var incidence := {}
	var neighbors := {}
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var vertex_count: int = arrays[Mesh.ARRAY_VERTEX].size()
		for triangle in range(0, indices.size(), 3):
			var keys: Array[String] = []
			for corner in 3:
				var v := points[offset + indices[triangle + corner]] * 100000
				keys.append("%d,%d,%d" % [roundi(v.x), roundi(v.y), roundi(v.z)])
			for edge in 3:
				var a := keys[edge]
				var b := keys[(edge + 1) % 3]
				var key := a + "|" + b if a < b else b + "|" + a
				incidence[key] = incidence.get(key, 0) + 1
				if not neighbors.has(a):
					neighbors[a] = []
				neighbors[a].append(b)
		offset += vertex_count
	var closed := not incidence.is_empty()
	for count in incidence.values():
		closed = closed and count == 2
	check(closed, "Arm sleeve/cuff/wrist surface must have no open seam: " + mesh.name)
	var visited := {}
	var pending: Array = [neighbors.keys()[0]] if not neighbors.is_empty() else []
	while not pending.is_empty():
		var key = pending.pop_back()
		if visited.has(key):
			continue
		visited[key] = true
		pending.append_array(neighbors[key])
	check(visited.size() == neighbors.size() and not visited.is_empty(), "Arm must be one connected surface")

func lowest_vertex(mesh: MeshInstance3D, skeleton: Skeleton3D) -> float:
	var low := INF
	for point in deformed_vertices(mesh, skeleton):
		low = minf(low, point.y)
	return low
