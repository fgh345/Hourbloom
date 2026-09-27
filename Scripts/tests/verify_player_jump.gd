extends SceneTree
## godot --headless --path . --script Scripts/tests/verify_player_jump.gd
## Uses the real player on an isolated floor and a fresh in-memory session.

const STEP := 1.0 / 60.0
var _failures: Array[String] = []
var _player: CharacterBody3D
var _animation_tree: AnimationTree
var _world: Node3D

func _initialize() -> void:
	# move_and_slide integrates Engine physics time; match the manual delta.
	Engine.physics_ticks_per_second = 60
	call_deferred("_verify")

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
		push_error(message)

func _verify() -> void:
	# Neither the main world nor SaveManager's save/load methods are invoked.
	root.get_node("GameManager").start_new_game()
	GameInput.ensure_default_bindings()
	_world = Node3D.new()
	root.add_child(_world)
	var floor_body := StaticBody3D.new()
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 1.0, 200.0)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -0.5
	_world.add_child(floor_body)
	_player = (load("res://Scenes/Actors/Player.tscn") as PackedScene).instantiate() as CharacterBody3D
	_world.add_child(_player)
	_player.set_physics_process(false)
	_player.set_process_input(false)
	_player.set_process_unhandled_input(false)
	_animation_tree = _player.Anim_tree
	_animation_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	await _ticks(5)
	_check(_player.is_on_floor(), "Player must start on isolated flat ground")

	await _verify_stationary_jump()
	await _verify_air_style_lock()
	await _verify_moving_jump(false)
	await _verify_moving_jump(true)

	Input.action_release("ui_up")
	Input.action_release("ui_accept")
	_set_sprint(false)
	for tool in _player._tool_inventory._tools:
		tool.free()
	_player._tool_inventory._tools.clear()
	_player._movement_controller = null
	_player._interaction_controller = null
	_world.queue_free()
	await process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Player jump verification: %s (%d failures)" % ["PASS" if _failures.is_empty() else "FAIL", _failures.size()])
	quit(0 if _failures.is_empty() else 1)

func _verify_stationary_jump() -> void:
	Input.action_release("ui_up")
	_set_sprint(false)
	await _ticks(90)
	_check(_horizontal_speed() < 0.05, "Stationary jump must start at rest")
	await _begin_jump("Stationary", 0.0)
	await _wait_for_landing("Stationary", &"LandSoft")
	_check(_horizontal_speed() < 0.05, "Stationary jump must not introduce horizontal drift")
	await _ticks(3)
	_check(_state() == &"LandSoft", "Stationary landing must retain a brief knee compression")
	Input.action_press("ui_up")
	await _tick()
	_check(_state() == &"Walk", "Moving input must immediately interrupt the stationary landing hold")
	Input.action_release("ui_up")
	await _ticks(90)
	await _begin_jump("Stationary repeat", 0.0)
	await _wait_for_landing("Stationary repeat", &"LandSoft")
	await _begin_jump("Stationary immediate re-jump", 0.0)
	_check(not _animation_tree.get("parameters/landing_recoil/active"), "Re-jump must abort the landing recoil immediately")
	await _wait_for_landing("Stationary immediate re-jump", &"LandSoft")
	await _ticks(14)
	_check(_state() == &"Idle", "Stationary landing must recover within a quarter second")

func _verify_air_style_lock() -> void:
	Input.action_press("ui_up")
	await _ticks(50)
	await _begin_jump("Movement-input release", 1.0)
	Input.action_release("ui_up")
	var initial_speed := _horizontal_speed()
	for frame in 12:
		await _tick()
		_check(absf(float(_animation_tree.get("parameters/jump_style/blend_amount")) - 1.0) < 0.001, "Releasing movement in flight must retain the moving takeoff pose")
		_check(absf(float(_animation_tree.get("parameters/fall_style/blend_amount")) - 1.0) < 0.001, "Releasing movement in flight must retain the matching descent pose")
	_check(_horizontal_speed() < initial_speed * 0.95, "Style-lock fixture must actually change airborne speed")
	Input.action_press("ui_up")
	for frame in 90:
		await _tick()
		if _player.is_on_floor():
			break
	_check(_player.is_on_floor() and _state() == &"Walk", "Flight with released and restored movement must land into Walk")

func _verify_moving_jump(sprinting: bool) -> void:
	var label := "Sprint" if sprinting else "Walk"
	_set_sprint(sprinting)
	_check(Input.is_physical_key_pressed(KEY_SHIFT) == sprinting, label + " must use the physical Shift input")
	Input.action_press("ui_up")
	await _ticks(50)
	var expected_speed: float = _player.sprint_speed if sprinting else _player.walk_speed
	var locomotion: StringName = &"Run" if sprinting else &"Walk"
	_check(_horizontal_speed() > expected_speed * 0.95, label + " must reach normal movement speed before jumping")
	await _begin_jump(label, 1.0)
	await _wait_for_landing(label, locomotion)
	_check(_horizontal_speed() > expected_speed * 0.95, label + " landing must preserve normal movement speed")
	_check(_animation_tree.get("parameters/landing_recoil/active"), label + " landing must trigger the short upper-body recoil")

	# Re-jump on the very first grounded frame while the recoil is still active.
	await _begin_jump(label + " immediate re-jump", 1.0)
	_check(not _animation_tree.get("parameters/landing_recoil/active"), label + " re-jump must abort recoil immediately")
	await _wait_for_landing(label + " immediate re-jump", locomotion)
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var leg := skeleton.find_bone("thigh.L")
	var reference := skeleton.get_bone_pose_rotation(leg)
	var leg_motion := 0.0
	var recoil_frames := 0
	for frame in 16:
		await _tick()
		_check(_state() == locomotion, label + " landing recovery must keep the locomotion state")
		_check(_horizontal_speed() > expected_speed * 0.95, label + " landing recovery must not slow sustained movement")
		if _animation_tree.get("parameters/landing_recoil/active"):
			recoil_frames += 1
			leg_motion = maxf(leg_motion, reference.angle_to(skeleton.get_bone_pose_rotation(leg)))
	_check(recoil_frames > 0 and leg_motion > 0.05, "%s legs must keep stepping during landing recoil (%.3f rad over %d frames)" % [label, leg_motion, recoil_frames])
	_check(not _animation_tree.get("parameters/landing_recoil/active"), label + " recoil must finish within a quarter second")
	print("%s landing: %s; stepping thigh %.3f rad; speed %.3f" % [label, locomotion, leg_motion, _horizontal_speed()])

func _begin_jump(label: String, expected_style: float) -> void:
	Input.action_press("ui_accept")
	await _tick()
	Input.action_release("ui_accept")
	_check(_state() == &"Jump" and not _player.is_on_floor() and _player.velocity.y > 0.0, label + " must jump immediately")
	_check(absf(float(_animation_tree.get("parameters/jump_style/blend_amount")) - expected_style) < 0.01, label + " must select its takeoff-speed jump style")

func _wait_for_landing(label: String, expected_landing: StringName) -> void:
	var initial_style := float(_animation_tree.get("parameters/jump_style/blend_amount"))
	var start_height := _player.position.y
	var max_height := start_height
	var states: Array[StringName] = [&"Jump"]
	var skeleton := _player.find_child("Skeleton3D", true, false) as Skeleton3D
	var arm := skeleton.find_bone("upper_arm.L")
	var leg := skeleton.find_bone("thigh.L")
	var arm_reference := skeleton.get_bone_pose_rotation(arm)
	var leg_reference := skeleton.get_bone_pose_rotation(leg)
	var arm_motion := 0.0
	var leg_motion := 0.0
	var airborne_frames := 0
	var landed := false
	for frame in 120:
		await _tick()
		airborne_frames += 1
		var state := _state()
		_check(state != &"LandRolling", label + " must never enter a landing roll")
		if states.back() != state:
			states.append(state)
		max_height = maxf(max_height, _player.position.y)
		arm_motion = maxf(arm_motion, arm_reference.angle_to(skeleton.get_bone_pose_rotation(arm)))
		leg_motion = maxf(leg_motion, leg_reference.angle_to(skeleton.get_bone_pose_rotation(leg)))
		if _player.is_on_floor():
			landed = true
			break
		_check(absf(float(_animation_tree.get("parameters/jump_style/blend_amount")) - initial_style) < 0.001, label + " takeoff style must stay fixed throughout the flight")
		_check(absf(float(_animation_tree.get("parameters/fall_style/blend_amount")) - initial_style) < 0.001, label + " descent style must match its takeoff")
	_check(landed, label + " must land within two seconds")
	_check(states == [&"Jump", &"Fall", expected_landing], "%s state chain must be Jump -> Fall -> %s: %s" % [label, expected_landing, states])
	_check(arm_motion > 0.05 and leg_motion > 0.05, "%s jump must articulate arm and thigh locally (%.3f / %.3f rad)" % [label, arm_motion, leg_motion])
	_check(max_height - start_height > 0.55 and max_height - start_height < 0.85, "%s jump must stay a short hop (%.3f m)" % [label, max_height - start_height])
	_check(airborne_frames * STEP > 0.45 and airborne_frames * STEP < 0.8, "%s flight must be short (%.3f s)" % [label, airborne_frames * STEP])
	print("%s jump: %s; height %.3f m; flight %.3f s" % [label, states, max_height - start_height, airborne_frames * STEP])

func _tick() -> void:
	await physics_frame
	_player._physics_process(STEP)
	_animation_tree.advance(STEP)

func _ticks(count: int) -> void:
	for frame in count:
		await _tick()

func _state() -> StringName:
	var requested: StringName = _player._movement_controller._movement_anim_state
	_check(StringName(_animation_tree.get("parameters/movement/current_state")) == requested, "AnimationTree must consume the controller's state in the same physics frame")
	return requested

func _horizontal_speed() -> float:
	return Vector2(_player.velocity.x, _player.velocity.z).length()

func _set_sprint(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
