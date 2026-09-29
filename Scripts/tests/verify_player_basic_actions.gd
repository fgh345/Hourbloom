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
	floor.name = "Floor"
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
	check(farm.get_seeded_tile_count() == 1 and farm.get_tile_data(tile).state == PLOWED, "Seed creates a crop without consuming the soil tile")
	var adjacent_target := target + Vector3.RIGHT
	var adjacent_tile: Vector2i = farm.world_to_grid(adjacent_target)
	farm.set_tile_state(adjacent_tile, PLOWED, 0.0)
	check(player.start_basic_action(&"Seed", func(): seed.use_tool(player, adjacent_target, Vector3.UP)), "Seed adjacent tile")
	await ticks(45)
	check(farm.get_seeded_tile_count() == 2, "Adjacent crops coexist")
	var second_in_tile := target + Vector3(0.25, 0, 0.25)
	check(farm.plant_crop_at(second_in_tile) > 0 and farm.get_seeded_tile_count() == 3, "Two crops share one soil tile")
	check(farm.plant_crop_at(second_in_tile) == 0, "Physical seeds cannot overlap")
	var first: CropData = farm.get_crop_near(target, 0.05)
	check(first != null and first.position == target, "Crop retains its exact world position")
	root.get_node("GameManager").session.time.set_total_minutes(farm.get_current_total_minutes() + farm.DEFAULT_CROP_GROWTH_MINUTES)
	var harvest: Tool = player._tool_inventory._tools[2]
	check(player.start_basic_action(&"Harvest", func(): harvest.use_tool(player, target, Vector3.UP)), "Harvest through action clock")
	await ticks(12)
	check(farm.get_crop(first.id) != null, "Crop remains during harvest windup")
	await ticks(45)
	check(farm.get_crop(first.id) == null and farm.get_seeded_tile_count() == 2, "Harvest removes only the targeted crop")
	var front_hit: Dictionary = player._interaction_controller._front_ground(player)
	check(not front_hit.is_empty() and absf((front_hit.get("position", Vector3.ZERO) as Vector3).z + 0.75) < 0.05, "Farm action targets ground at the player's front foot")
	if not front_hit.is_empty():
		var front_position: Vector3 = front_hit["position"]
		check(player._interaction_controller.try_use_tool(player, seed), "Seed action starts at the front foot without camera targeting")
		await ticks(45)
		check(farm.get_crop_near(front_position, 0.01) != null, "Front-foot action plants at its exact contact position")
	var grid_manager = load("res://Scripts/farm/GridManager.gd").new()
	grid_manager.enable_chunk_streaming = false
	world.add_child(grid_manager)
	var crop_chunk: Vector2i = farm.world_to_chunk(second_in_tile)
	grid_manager._currently_loaded_chunks[crop_chunk] = true
	grid_manager._spawn_crop_nodes_for_chunk(crop_chunk)
	check(grid_manager._crop_nodes_by_grid.size() == farm.get_chunk_crop_ids(crop_chunk).size(), "Every crop in a chunk gets its own visual node")
	var second_crop: CropData = farm.get_crop_near(second_in_tile, 0.01)
	check(second_crop != null and grid_manager._crop_nodes_by_grid[second_crop.id].global_position == second_in_tile, "Visual node keeps the crop's exact position")
	var mask = load("res://Scripts/world/MapRegionMask.gd").new()
	mask.world_size_meters = 64.0
	mask.world_center_position = Vector2.ZERO
	mask.mask_texture = ImageTexture.create_from_image(Image.create(64, 64, false, Image.FORMAT_L8))
	farm.set_active_region_mask(mask)
	var layers: Dictionary = farm.export_heatmap_layers({})
	var serialized: Variant = JSON.parse_string(JSON.stringify(farm.export_crops()))
	var restored = load("res://Scripts/farm/FarmData.gd").new()
	restored.set_active_region_mask(mask)
	restored.import_heatmap_layers(layers["soil_state"], layers["crop_type"], layers["planted_time"], {})
	restored.import_crops(serialized)
	check(restored.get_seeded_tile_count() == farm.get_seeded_tile_count() and restored.get_crop_near(second_in_tile, 0.01) != null, "Crop save roundtrip retains every position")
	check(restored.get_tile_data(tile).state == PLOWED, "Soil and crops restore independently")
	var legacy_crop_image: Image = layers["crop_type"]
	var legacy_pixel: Vector2i = farm._grid_to_heatmap_pixel(tile, 64, 64)
	legacy_crop_image.set_pixelv(legacy_pixel, Color(1.0 / 255.0, 0, 0, 1))
	var migrated = load("res://Scripts/farm/FarmData.gd").new()
	migrated.set_active_region_mask(mask)
	migrated.import_heatmap_layers(layers["soil_state"], legacy_crop_image, layers["planted_time"], {"1": "generic"})
	check(migrated.get_seeded_tile_count() == 1 and migrated.get_crop_near(Vector3(0.5, 0, -0.5), 0.01) != null, "Legacy crop heatmap migrates to independent crop")
	var melon_position := Vector3(3.5, 0, -0.5)
	farm.set_tile_state(farm.world_to_grid(melon_position), PLOWED, 0.0)
	var melon_id: int = farm.plant_crop_at(melon_position, &"watermelon", 1, 0.05, 2.0)
	check(melon_id > 0 and farm.get_crop_covered_tiles(melon_id).size() == 1, "Young plant occupies only its seed footprint")
	check(farm.get_crop_covered_tiles(melon_id, farm.get_current_total_minutes() + 1).size() > 4, "Growing vine footprint crosses multiple soil tiles")
	farm.simulate_chunk_passage_of_time(farm.world_to_chunk(melon_position), 60, true)
	check(farm.get_crop(melon_id).is_harvestable(farm.get_current_total_minutes()), "Chunk catch-up advances each crop independently")
	var save_slot := 99991
	check(root.get_node("SaveManager").save_slot(save_slot), "SaveManager writes independent crop instances")
	var expected_count: int = farm.get_seeded_tile_count()
	farm.clear_runtime_state()
	check(await root.get_node("SaveManager").load_slot(save_slot), "SaveManager reloads crop instances")
	check(farm.get_seeded_tile_count() == expected_count and farm.get_crop(melon_id) != null, "Real save roundtrip retains every crop ID")
	root.get_node("SaveManager")._delete_dir_recursive(root.get_node("SaveManager")._slot_dir(save_slot))
	for tool in player._tool_inventory._tools:
		tool.free()
	player._tool_inventory._tools.clear()
	world.queue_free()
	await process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("PLAYER_BASIC_ACTIONS_OK" if failures.is_empty() else "PLAYER_BASIC_ACTIONS_FAILED: " + str(failures))
	quit(0 if failures.is_empty() else 1)
