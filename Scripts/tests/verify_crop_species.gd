extends Node

var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	GameManager.set_process(false)
	GameManager.start_new_game()
	var farm: FarmData = GameManager.session.farm
	farm.set_tile_state(Vector2i(31, 0), FarmData.SoilState.PLOWED)
	var id := farm.plant_crop_at(Vector3(31.8, 0, 0.5), &"watermelon", 100, CropSpecies.seed_radius(&"watermelon"), CropSpecies.MAX_SPREAD)
	check(id > 0, "Plant watermelon at arbitrary sub-grid coordinates")
	var crop := farm.get_crop(id)
	check(crop.growth_rate >= CropSpecies.GROWTH_RATE_MIN and crop.growth_rate <= CropSpecies.GROWTH_RATE_MAX, "New crops receive bounded growth variation")
	check(is_equal_approx(crop.growth_rate, CropSpecies.growth_rate_for_seed(crop.shape_seed)), "Growth variation is deterministic from shape seed")
	crop.simulated_until_minute = crop.planted_at_minute + 200
	var paths := crop.vine_paths()
	check(paths.size() == 12, "Four runners and eight side branches")
	check(paths == CropSpecies.vine_paths(crop.shape_seed), "Stable paths from persisted shape seed")
	check(paths != CropSpecies.vine_paths(crop.shape_seed + 1), "Plants have different shapes")
	for path in paths:
		for point in path:
			check(point.length() < CropSpecies.MAX_SPREAD, "Bounded vine extent")
	var tiles := farm.get_crop_covered_tiles(id)
	check(tiles.size() > 8, "One watermelon covers many soil tiles")
	var crossed := false
	for tile in tiles:
		if farm.grid_to_chunk(tile) != farm.world_to_chunk(crop.position):
			crossed = true
	check(crossed, "Coverage crosses a chunk boundary")
	var fruit := crop.fruit_position(0)
	check(farm.get_crop_near(fruit, 0.01, true) == crop, "Harvest query finds fruit away from root")
	check(farm.get_crop_near(crop.position, 0.05, true) == null, "Aiming at root cannot harvest distant fruit")
	check(farm.harvest_at(fruit, 0.01).get("crop_type") == &"watermelon", "Harvest correct species")
	check(farm.get_crop(id) == crop and crop.harvested_fruits == [0], "Picking fruit leaves vine intact")
	check(farm.harvest_at(fruit, 0.01).is_empty(), "Picked fruit cannot be picked twice")
	var restored := CropData.from_dict(crop.to_dict())
	check(restored.harvested_fruits == [0] and restored.vine_paths() == paths, "Save roundtrip retains fruit and vine shape")
	check(is_equal_approx(restored.growth_rate, crop.growth_rate), "Save roundtrip retains growth variation")
	farm.import_crops(farm.export_crops())
	crop = farm.get_crop(id)
	check(crop.harvested_fruits == [0], "Farm import retains harvest state")
	for index in range(1, CropSpecies.FRUIT_COUNT):
		check(not farm.harvest_at(crop.fruit_position(index), 0.01).is_empty(), "Harvest remaining fruit individually")
	check(farm.get_crop(id) != null and not crop.is_harvestable(farm.get_current_total_minutes()), "Exhausted vine remains without infinite fruit")
	var staggered := CropData.new()
	staggered.crop_type = &"watermelon"
	staggered.growth_minutes_required = 1000
	check(staggered.fruit_is_harvestable(0, 850) and not staggered.fruit_is_harvestable(3, 850), "Fruit ripens at distinct times")
	farm.set_tile_state(Vector2i(0, 0), FarmData.SoilState.PLOWED)
	var sun_id := farm.plant_crop_at(Vector3(0.3, 0, 0.4), &"sunflower", 100)
	var sun := farm.get_crop(sun_id)
	sun.simulated_until_minute = sun.planted_at_minute + 200
	check(farm.harvest_at(sun.position, 0.01).get("crop_type") == &"sunflower" and farm.get_crop(sun_id) == null, "Sunflower harvest removes single plant")
	var legacy := CropData.from_dict({"id": 9, "position": [1, 0, 1]})
	check(legacy != null and legacy.crop_type == &"generic" and legacy.harvested_fruits.is_empty(), "Legacy saves remain readable")
	check(is_equal_approx(legacy.growth_rate, 1.0), "Legacy saves keep neutral growth rate")
	for species: StringName in [&"sunflower", &"watermelon"]:
		var visual_crop := CropData.new()
		visual_crop.crop_type = species
		visual_crop.shape_seed = 42
		for progress: float in [0.0, 0.10, 0.3, 0.6, 0.8, 1.0]:
			for detailed: bool in [true, false]:
				var builder := CropVisualBuilder.new()
				var mesh := builder.build(visual_crop, progress, detailed)
				check(mesh.get_surface_count() > 0 and mesh.get_aabb().size.length() > 0, "Build every visual stage and LOD")
		var entity: EntityData = EntityRegistry.create_entity(CropSpecies.item_id(species))
		check(entity != null, "Harvest item registered")
		var definition: ItemDefinition = ItemRegistry.get_item(CropSpecies.item_id(species))
		check(definition != null and definition.world_scene != null, "Harvest item has dropped world view")
		var item := definition.world_scene.instantiate()
		get_tree().root.add_child(item)
		item.free()
	# Real streamed CropNodes use the same mesh and survive picking one fruit.
	var stream_crop := CropData.new()
	stream_crop.id = 100
	stream_crop.crop_type = &"watermelon"
	stream_crop.position = Vector3(31.8, 0, 0.5)
	stream_crop.shape_seed = 71
	stream_crop.simulated_until_minute = stream_crop.growth_minutes_required
	farm.import_crops([stream_crop.to_dict()])
	var player_target := Node3D.new()
	player_target.add_to_group("player")
	player_target.position = Vector3(32.2, 0, 0.5)
	get_tree().root.add_child(player_target)
	var grid := Node3D.new()
	grid.set_script(load("res://Scripts/farm/GridManager.gd"))
	grid.set("streamed_chunk_radius", 0)
	get_tree().root.add_child(grid)
	var crop_nodes := get_tree().get_nodes_in_group("crop_node").filter(func(node: Node): return not node.is_queued_for_deletion())
	check(crop_nodes.size() == 1, "Root in neighboring chunk is streamed for visible vine")
	if not crop_nodes.is_empty():
		var crop_node: Node3D = crop_nodes[0]
		var mesh_view := crop_node.get_child(0) as MeshInstance3D
		check(mesh_view != null and mesh_view.mesh != null and mesh_view.mesh.get_aabb().size.x > 1.0, "Live CropNode renders spread geometry")
		var vertices_before := mesh_view.mesh.get_surface_count()
		farm.harvest_at(farm.get_crop(100).fruit_position(0), 0.01)
		check(is_instance_valid(crop_node) and not crop_node.is_queued_for_deletion() and vertices_before > 0, "Fruit signal keeps live vine node")
	grid.free()
	player_target.free()
	await get_tree().process_frame
	# Compile/invoke modified integration scripts, not just the data layer.
	for path: String in ["res://Scripts/farm/tools/SeedTool.gd", "res://Scripts/farm/tools/HarvestTool.gd", "res://Scripts/player/PlayerInteractionController.gd", "res://Scripts/farm/GridManager.gd", "res://Scripts/player/Player.gd"]:
		var script: GDScript = load(path)
		check(script != null and script.can_instantiate(), "Integration script compiles: " + path)
	print("Crop species verification: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	get_tree().quit(0 if failures == 0 else 1)
