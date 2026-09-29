extends SceneTree
## Real player and imported animation, isolated flat ground and no save access.
const STEP := 1.0 / 60.0
const PLOWED := 1
const SEEDED := 2
const HARVESTABLE := 3
const DURATIONS := {&"Seed": .72, &"Harvest": .72, &"Pickup": .64, &"Drop": .64, &"Interact": .55}
const CONTACT := {&"Seed": .40, &"Harvest": .43, &"Pickup": .38, &"Drop": .38, &"Interact": .30}
var failures: Array[String] = []
var player: CharacterBody3D
var calls := 0

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("verify")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func tick() -> void:
	await physics_frame
	player._physics_process(STEP)
	player.Anim_tree.advance(STEP)

func ticks(count: int) -> void:
	for i in count:
		await tick()

func cancel_in_validation() -> bool:
	player.cancel_basic_action()
	return true

func hide_player_on_effect() -> void:
	calls += 1
	player.visible = false

func verify() -> void:
	root.get_node("GameManager").start_new_game()
	GameInput.ensure_default_bindings()
	var world := Node3D.new()
	root.add_child(world)
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(20, 1, 20)
	shape.shape = box
	floor.add_child(shape)
	floor.position.y = -.5
	world.add_child(floor)
	player = load("res://Scenes/Actors/Player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.Anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	await ticks(12)
	check(player.is_on_floor(), "Player grounded")
	var animator := player.hero_mesh.get_node("AnimationPlayer") as AnimationPlayer
	for kind in DURATIONS:
		check(animator.has_animation(kind), "Imported action clip " + String(kind))
		var clip := animator.get_animation(kind)
		check(absf(clip.length - DURATIONS[kind]) < .02, "Action duration " + String(kind))
		var before := calls
		check(player.start_basic_action(kind, func(): calls += 1), "Start " + String(kind))
		check(not player.start_basic_action(kind, func(): calls += 1), "No overlapping " + String(kind))
		await ticks(maxi(1, floori(CONTACT[kind] / STEP) - 2))
		check(calls == before, "No early effect " + String(kind))
		await ticks(3)
		check(calls == before + 1, "Exactly one effect at contact " + String(kind))
		await ticks(ceili(DURATIONS[kind] / STEP) + 3)
		check(not player.is_action_active() and calls == before + 1, "Action releases " + String(kind))
	var before_cancel := calls
	check(player.start_basic_action(&"Seed", func(): calls += 1), "Start cancellable action")
	await ticks(8)
	player.cancel_basic_action()
	await ticks(40)
	check(calls == before_cancel and not player.is_action_active(), "Cancellation cannot execute effect")
	var before_validation_cancel := calls
	check(player.start_basic_action(&"Interact", func(): calls += 1, cancel_in_validation), "Start action cancelled by validation")
	await ticks(ceili(CONTACT[&"Interact"] / STEP) + 2)
	check(calls == before_validation_cancel and not player.is_action_active(), "Validation cancellation skips effect")
	var before_effect_cancel := calls
	check(player.start_basic_action(&"Interact", hide_player_on_effect), "Start action cancelled by effect")
	await ticks(ceili(CONTACT[&"Interact"] / STEP) + 2)
	check(calls == before_effect_cancel + 1 and not player.is_action_active(), "Visibility cancellation during effect releases action")
	player.visible = true
	var farm = root.get_node("GameManager").session.farm
	check(farm.world_to_grid(Vector3(0.75, 0, -0.25)) == Vector2i(0, -1), "Tile lookup matches the visible tile center")
	var target := Vector3(0, 0, -1)
	var tile: Vector2i = farm.world_to_grid(target)
	farm.set_tile_state(tile, PLOWED, 0.0)
	var seed: Tool = player._tool_inventory._tools[1]
	check(player.start_basic_action(&"Seed", func(): seed.use_tool(player, target, Vector3.UP)), "Seed through action clock")
	await ticks(12)
	check(farm.get_tile_data(tile).state == PLOWED, "Soil unchanged during seed windup")
	await ticks(45)
	check(farm.get_tile_data(tile).state == SEEDED, "Seed commits at contact")
	var adjacent_target := target + Vector3.RIGHT
	var adjacent_tile: Vector2i = farm.world_to_grid(adjacent_target)
	farm.set_tile_state(adjacent_tile, PLOWED, 0.0)
	check(player.start_basic_action(&"Seed", func(): seed.use_tool(player, adjacent_target, Vector3.UP)), "Seed adjacent tile")
	await ticks(45)
	check(farm.get_tile_data(adjacent_tile).state == SEEDED and farm.get_tile_data(tile).state == SEEDED, "Adjacent crops coexist")
	root.get_node("GameManager").session.time.set_total_minutes(maxi(farm.get_current_total_minutes(), 1))
	farm.get_tile_data(tile).state = HARVESTABLE
	farm.get_tile_data(tile).growth_minutes_required = 1
	farm.get_tile_data(tile).planted_at_minute = farm.get_current_total_minutes() - 1
	var harvest: Tool = player._tool_inventory._tools[2]
	check(player.start_basic_action(&"Harvest", func(): harvest.use_tool(player, target, Vector3.UP)), "Harvest through action clock")
	await ticks(12)
	check(farm.get_tile_data(tile).state == HARVESTABLE, "Crop remains during harvest windup")
	await ticks(45)
	check(farm.get_tile_data(tile).state == PLOWED, "Harvest commits at contact")
	for tool in player._tool_inventory._tools:
		tool.free()
	player._tool_inventory._tools.clear()
	world.queue_free()
	await process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("PLAYER_BASIC_ACTIONS_OK" if failures.is_empty() else "PLAYER_BASIC_ACTIONS_FAILED: " + str(failures))
	quit(0 if failures.is_empty() else 1)
