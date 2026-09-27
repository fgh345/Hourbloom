extends SceneTree
## Real Player + physics + in-memory farm; never loads or saves a user world.
const STEP := 1.0 / 60.0
const Motion = preload("res://Assets/Tools/Hoe/HoeMotion.gd")
var failures: Array[String] = []
var player: CharacterBody3D
var world: Node3D
var farm
var updates := 0
var last_tile := Vector2i.ZERO

class Blocker extends Node:
	var open := true
	func is_console_open() -> bool:
		return open

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("verify")

func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)
		push_error(message)

func verify() -> void:
	root.get_node("GameManager").start_new_game()
	GameInput.ensure_default_bindings()
	farm = root.get_node("GameManager").session.farm
	farm.tile_updated.connect(func(tile: Vector2i, _state: int):
		updates += 1
		last_tile = tile)
	world = Node3D.new()
	root.add_child(world)
	var floor_body := StaticBody3D.new()
	floor_body.add_to_group("farmland_ground")
	var floor_shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	floor_shape.shape = box
	floor_body.add_child(floor_shape)
	floor_body.position.y = -.5
	world.add_child(floor_body)
	player = load("res://Scenes/Actors/Player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.Anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	await ticks(30)
	var animator := player.hero_mesh.get_node("AnimationPlayer") as AnimationPlayer
	for clip in ["freehand_walk", "freehand_run", "jump_start", "jump_move", "fall_move", "landing_soft", "landing_recoil", "Hoe"]:
		check(animator.has_animation(clip), "Runtime retains animation " + clip)
	check(player.is_on_floor(), "Player starts grounded")
	check(not animator.has_animation("HoeIdle"), "Runtime omits the removed tool idle clip")
	check(visible_count("Hoe_") == 0 and visible_count("GripHand_") == 0, "Selecting hoe leaves idle empty-handed")
	check(visible_count("OpenHand_") > 0, "Idle shows ordinary open hands")
	var tool: Tool = player._tool_inventory.get_active_tool()
	# The aiming point is intentionally far away; only the real blade's near-ground point may change.
	tool.use_tool(player, Vector3(0, 0, -30), Vector3.UP)
	check(player.is_hoe_action_active(), "Using equipped hoe starts action")
	var target: Vector3 = player.hero_mesh.to_global(Motion.CONTACT_LOCAL)
	var intended_tile: Vector2i = farm.world_to_grid(target)
	check(updates == 0, "Click must not plow before impact")
	var start_position := player.position
	var start_yaw := player.rotation.y
	Input.action_press("ui_up")
	Input.action_press("ui_accept")
	var switch_event := InputEventKey.new()
	switch_event.physical_keycode = KEY_2
	switch_event.pressed = true
	player._input(switch_event)
	tool.use_tool(player, Vector3(30, 0, 0), Vector3.UP)
	var before_impact := maxi(1, floori(Motion.IMPACT_TIME / STEP) - 1)
	var impact_tick := ceili(Motion.IMPACT_TIME / STEP) + 1
	await ticks(before_impact)
	check(visible_count("Hoe_") > 0 and visible_count("GripHand_") > 0 and visible_count("OpenHand_") == 0, "Only the active swing displays hoe and grip hands")
	Input.action_release("ui_accept")
	check(updates == 0, "No soil change before the authored impact time")
	check(player.position.distance_to(start_position) < .015, "Swing blocks movement and jumping")
	check(absf(player.rotation.y - start_yaw) < .001, "Repeated click cannot redirect swing")
	check(player._tool_inventory.get_active_tool() == tool, "Cannot switch tools during swing")
	await ticks(impact_tick - before_impact)
	check(updates == 1 and last_tile == intended_tile, "Exactly one near-blade tile changes at impact")
	check(not farm.has_tile(Vector2i(0, -30)), "Far crosshair point is never plowed")
	Input.action_release("ui_up")
	var finish_tick := ceili(Motion.DURATION / STEP)
	await ticks(finish_tick - 1 - impact_tick)
	check(player.is_hoe_action_active(), "Action remains active until its final frame")
	await ticks(1)
	check(not player.is_hoe_action_active() and updates == 1, "Recovery releases action at the authored end without duplicate effect")
	check(visible_count("Hoe_") == 0 and visible_count("GripHand_") == 0 and visible_count("OpenHand_") > 0, "Finished swing returns to empty-handed idle with hoe still selected")
	player._input(switch_event)
	await ticks(12)
	check(visible_count("Hoe_") == 0 and visible_count("GripHand_") == 0, "Switching away hides tool and grip meshes")
	check(visible_count("OpenHand_") > 0, "Normal hands restored")
	# Select hoe again, then cancel before impact via the actual input-block path.
	switch_event.physical_keycode = KEY_1
	player._input(switch_event)
	await ticks(12)
	check(visible_count("Hoe_") == 0, "Reselecting hoe does not reintroduce a held idle")
	tool.use_tool(player, Vector3(30, 0, 0), Vector3.UP)
	check(player.is_hoe_action_active(), "Can start a subsequent swing")
	await ticks(maxi(1, mini(12, floori(Motion.IMPACT_TIME / STEP / 2.0))))
	var blocker := Blocker.new()
	blocker.add_to_group("developer_console")
	world.add_child(blocker)
	await ticks(ceili(Motion.DURATION / STEP) + 8)
	check(not player.is_hoe_action_active() and updates == 1, "Input blocking cancels pending impact")
	check(visible_count("Hoe_") == 0 and visible_count("OpenHand_") > 0, "Cancellation restores normal hands")
	blocker.queue_free()
	await process_frame
	# Walking/jumping must retain locomotion and stow the held prop.
	Input.action_press("ui_up")
	await ticks(20)
	check(Vector2(player.velocity.x, player.velocity.z).length() > 1, "Movement resumes after cancellation")
	check(visible_count("Hoe_") == 0, "Moving stows hoe")
	Input.action_press("ui_accept")
	await tick()
	Input.action_release("ui_accept")
	check(not player.is_on_floor(), "Jump still works with hoe selected")
	tool.use_tool(player, Vector3(30, 0, 0), Vector3.UP)
	check(not player.is_hoe_action_active(), "Cannot hoe in the air")
	Input.action_release("ui_up")
	await ticks(90)
	player.toggle_godmode()
	tool.use_tool(player, Vector3(30, 0, 0), Vector3.UP)
	check(not player.is_hoe_action_active(), "Cannot hoe in godmode")
	player.toggle_godmode()
	await ticks(20)
	# Non-farmable ground must reject the action before it can mutate a tile.
	var mask = load("res://Scripts/world/MapRegionMask.gd").new()
	var mask_image := Image.create(2, 2, false, Image.FORMAT_L8)
	mask_image.fill(Color.WHITE)
	mask.mask_texture = ImageTexture.create_from_image(mask_image)
	mask.world_center_position = Vector2.ZERO
	mask.initialize()
	farm.set_active_region_mask(mask)
	tool.use_tool(player, player.position + Vector3(30, 0, 0), Vector3.UP)
	check(not player.is_hoe_action_active() and updates == 1, "Region restrictions reject hoe action")
	farm.set_active_region_mask(null)
	# A solid prop over the contact point must block the soil beneath it.
	player.rotation.y = -PI / 2
	var obstruction := StaticBody3D.new()
	var obstruction_shape := CollisionShape3D.new()
	var obstruction_box := BoxShape3D.new()
	obstruction_box.size = Vector3(.3, .1, .3)
	obstruction_shape.shape = obstruction_box
	obstruction.add_child(obstruction_shape)
	world.add_child(obstruction)
	obstruction.global_position = player.hero_mesh.to_global(Motion.CONTACT_LOCAL + Vector3.UP * .05)
	await ticks(2)
	tool.use_tool(player, player.position + Vector3(30, 0, 0), Vector3.UP)
	check(not player.is_hoe_action_active(), "Solid object blocks hoe from plowing through it")
	obstruction.queue_free()
	await process_frame
	# Exercise the production SoilLayerService branch as well as the earlier fallback.
	var soil_service := Node3D.new()
	soil_service.set_script(load("res://Scripts/farm/SoilLayerService.gd"))
	world.add_child(soil_service)
	check(soil_service.is_in_group("soil_layer_service"), "Production soil service is registered")
	await ticks(2)
	tool.use_tool(player, player.position + Vector3(30, 0, 0), Vector3.UP)
	check(player.is_hoe_action_active(), "Hoe starts with real soil service")
	await ticks(ceili(Motion.DURATION / STEP) + 8)
	check(updates == 2, "Real soil service commits exactly once at impact")
	await verify_facing(tool)
	for inventory_tool in player._tool_inventory._tools:
		inventory_tool.free()
	player._tool_inventory._tools.clear()
	world.queue_free()
	await process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("PLAYER_HOE_OK" if failures.is_empty() else "PLAYER_HOE_FAILED: " + str(failures))
	quit(0 if failures.is_empty() else 1)

func verify_facing(tool: Tool) -> void:
	# Keep the orbit camera pointing in one world direction while the character
	# faces all four cardinal directions. A fifth case keeps a visual turn offset.
	var headings := [0.0, PI / 2.0, PI, -PI / 2.0, 0.4]
	var original_pitch: float = player._camera_controller.pitch
	for index in headings.size():
		player.global_position = Vector3(-35 + index * 8, .02, 25)
		player.velocity = Vector3.ZERO
		await ticks(3)
		player.rotation.y = headings[index]
		player.hero_mesh.rotation.y = player._hero_base_yaw + (0.2 if index == 4 else 0.0)
		player._camera_controller.set_yaw_global(0.0)
		# Looking straight up guarantees there is no crosshair ground hit. Hoe
		# input must still work through the real interaction-controller path.
		player._camera_controller.pitch = PI / 2.0
		player.spring_arm.rotation.x = PI / 2.0
		player._camera_controller.update(0.0, true)
		# Put the camera above the floor as well: a vertical orbit would otherwise
		# move its usual boom offset below the floor and raycast upward through it.
		player.camera.global_position = player.global_position + Vector3.UP * 5.0
		check(player._interaction_controller._raycast_from_screen_center(player).is_empty(), "Sky-facing crosshair has no hit, case " + str(index))
		check(absf(wrapf(player.camera.global_rotation.y, -PI, PI)) < .001, "Camera world yaw stays fixed before swing, case " + str(index))
		var yaw_before := player.rotation.y
		var visual_yaw_before: float = player.hero_mesh.rotation.y
		var contact: Vector3 = player.hero_mesh.to_global(Motion.CONTACT_LOCAL)
		var expected_tile: Vector2i = farm.world_to_grid(contact)
		var opposite_tile: Vector2i = farm.world_to_grid(player.hero_mesh.to_global(Vector3(Motion.CONTACT_LOCAL.x, Motion.CONTACT_LOCAL.y, -Motion.CONTACT_LOCAL.z)))
		var forward: Vector3 = player.hero_mesh.global_basis.z.normalized()
		check((contact - player.global_position).dot(forward) > Motion.CONTACT_LOCAL.z - .02, "Expected impact is in front of visible character, case " + str(index))
		check(not farm.has_tile(expected_tile) and not farm.has_tile(opposite_tile), "Each facing test starts on fresh soil, case " + str(index))
		var previous_updates := updates
		check(player._interaction_controller.try_use_tool(player, tool), "Hoe input is accepted without a crosshair hit, case " + str(index))
		check(player.is_hoe_action_active(), "Facing swing starts, case " + str(index))
		check(absf(wrapf(player.rotation.y - yaw_before, -PI, PI)) < .001, "Click preserves body yaw, case " + str(index))
		check(absf(wrapf(player.hero_mesh.rotation.y - visual_yaw_before, -PI, PI)) < .001, "Click preserves visible character yaw, case " + str(index))
		var windup_ticks := maxi(1, mini(12, floori(Motion.IMPACT_TIME / STEP / 2.0)))
		await ticks(windup_ticks)
		# Orbit the camera during the windup; neither the character nor contact
		# point may follow the camera's new direction.
		player._camera_controller.set_yaw_global(1.1)
		player._camera_controller.pitch = -.4
		var impact_tick := ceili(Motion.IMPACT_TIME / STEP) + 1
		await ticks(impact_tick - windup_ticks)
		check(absf(wrapf(player.rotation.y - yaw_before, -PI, PI)) < .001, "Camera orbit cannot redirect active body, case " + str(index))
		check(absf(wrapf(player.hero_mesh.rotation.y - visual_yaw_before, -PI, PI)) < .001, "Active swing locks visual yaw, case " + str(index))
		check(updates == previous_updates + 1 and last_tile == expected_tile, "Impact plows facing tile exactly once, case " + str(index))
		check(not farm.has_tile(opposite_tile), "Swing never plows behind the character, case " + str(index))
		await ticks(ceili(Motion.DURATION / STEP) + 8 - impact_tick)
		check(not player.is_hoe_action_active() and updates == previous_updates + 1, "Facing swing completes without another impact, case " + str(index))
	player._camera_controller.pitch = original_pitch

func visible_count(prefix: String) -> int:
	var count := 0
	for mesh in player.hero_mesh.find_children(prefix + "*", "MeshInstance3D", true, false):
		if mesh.is_visible_in_tree():
			count += 1
	return count

func tick() -> void:
	await physics_frame
	player._physics_process(STEP)
	player.Anim_tree.advance(STEP)

func ticks(count: int) -> void:
	for frame in count:
		await tick()
