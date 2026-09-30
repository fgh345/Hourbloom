class_name FarmData
extends RefCounted

# The valid soil states
enum SoilState {
	GRASS = 0,
	PLOWED = 1,
	SEEDED = 2,
	HARVESTABLE = 3
}

const DEFAULT_CROP_GROWTH_MINUTES := 3 * 24 * 60
var simulation_chunk_size_tiles: int = 32

# The abstract grid dictionary: Vector2i -> FarmTileData
var _grid: Dictionary = {}
var _tiles_by_chunk: Dictionary = {}
var _crops: Dictionary = {} # int -> CropData; independent of soil tiles
var _crops_by_chunk: Dictionary = {} # Vector2i -> {int: true}
var _next_crop_id: int = 1
var _chunk_unloaded_at_minute: Dictionary = {}
var _loaded_chunks: Dictionary = {}
var _last_processed_minute: int = -1

var active_region_mask: MapRegionMask = null

var map_fields: Array[FieldPolygon] = []

# Emitted when a specific tile changes state
signal tile_updated(grid_pos: Vector2i, new_state: int)
signal crop_updated(crop_id: int, exists: bool)
signal chunk_loaded(chunk_pos: Vector2i, catch_up_seconds: int)
signal chunk_unloaded(chunk_pos: Vector2i, unloaded_at_minute: int)

func _init() -> void:
	pass

func tick(_delta: float) -> void:
	pass

func world_to_grid(world_pos: Vector3) -> Vector2i:
	# A tile covers [x, x + 1) by [z, z + 1); visuals use its +0.5 center.
	return Vector2i(floori(world_pos.x), floori(world_pos.z))

func grid_to_world_center(grid_pos: Vector2i) -> Vector2:
	# Currently 1 tile = 1 meter, so the center is +0.5
	return Vector2(float(grid_pos.x) + 0.5, float(grid_pos.y) + 0.5)

func grid_to_chunk(grid_pos: Vector2i) -> Vector2i:
	var chunk_size := maxi(simulation_chunk_size_tiles, 1)
	return Vector2i(
		int(floor(float(grid_pos.x) / float(chunk_size))),
		int(floor(float(grid_pos.y) / float(chunk_size)))
	)

func world_to_chunk(world_pos: Vector3) -> Vector2i:
	return grid_to_chunk(world_to_grid(world_pos))

# Retrieves data for a specific tile. If it doesn't exist, returns a default tile struct.
func get_tile_data(grid_pos: Vector2i) -> FarmTileData:
	if _grid.has(grid_pos):
		return _grid[grid_pos]

	return FarmTileData.new()

func has_tile(grid_pos: Vector2i) -> bool:
	return _grid.has(grid_pos)

func get_total_tile_count() -> int:
	return _grid.size()

func get_total_chunk_count() -> int:
	return _tiles_by_chunk.size()

func get_seeded_tile_count() -> int:
	return _crops.size()

func get_loaded_chunk_count() -> int:
	return _loaded_chunks.size()

func get_unloaded_chunk_count() -> int:
	return _chunk_unloaded_at_minute.size()

func get_chunk_unloaded_minute(chunk_pos: Vector2i) -> int:
	if not _chunk_unloaded_at_minute.has(chunk_pos):
		return -1
	return int(_chunk_unloaded_at_minute[chunk_pos])

func get_chunk_tiles(chunk_pos: Vector2i) -> Array[Vector2i]:
	if not _tiles_by_chunk.has(chunk_pos):
		return []

	var tiles: Array[Vector2i] = []
	var chunk_tiles: Dictionary = _tiles_by_chunk[chunk_pos]
	for grid_pos_any: Variant in chunk_tiles.keys():
		if grid_pos_any is Vector2i:
			tiles.append(grid_pos_any)
	return tiles

func get_crop(crop_id: int) -> CropData:
	return _crops.get(crop_id, null) as CropData

func get_chunk_crop_ids(chunk_pos: Vector2i) -> Array[int]:
	var result: Array[int] = []
	var ids: Dictionary = _crops_by_chunk.get(chunk_pos, {})
	for id_any: Variant in ids:
		result.append(int(id_any))
	return result

func can_plant_at(position: Vector3, seed_radius: float = 0.05) -> bool:
	if get_tile_data(world_to_grid(position)).state != SoilState.PLOWED:
		return false
	# Only physical seed footprints block placement; adult canopies may compete.
	var reach := maxi(1, ceili(seed_radius + 1.0))
	var chunk := world_to_chunk(position)
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for id: int in get_chunk_crop_ids(chunk + Vector2i(dx, dz)):
				var other := get_crop(id)
				if other != null and Vector2(position.x, position.z).distance_to(Vector2(other.position.x, other.position.z)) < seed_radius + other.seed_radius:
					return false
	return true

func plant_crop_at(position: Vector3, crop_type: StringName = &"generic", growth_minutes_required: int = DEFAULT_CROP_GROWTH_MINUTES, seed_radius: float = 0.05, mature_radius: float = 0.25) -> int:
	if not can_plant_at(position, seed_radius):
		return 0
	var crop := CropData.new()
	crop.id = _next_crop_id
	_next_crop_id += 1
	crop.position = position
	crop.shape_seed = crop.id * 7919 + roundi(position.x * 101.0) + roundi(position.z * 307.0)
	crop.growth_rate = CropSpecies.growth_rate_for_seed(crop.shape_seed)
	crop.crop_type = crop_type
	crop.planted_at_minute = get_current_total_minutes()
	crop.simulated_until_minute = crop.planted_at_minute
	crop.growth_minutes_required = maxi(1, growth_minutes_required)
	crop.seed_radius = maxf(0.001, seed_radius)
	crop.mature_radius = maxf(crop.seed_radius, mature_radius)
	_register_crop(crop)
	return crop.id

func _register_crop(crop: CropData) -> void:
	_crops[crop.id] = crop
	var chunk := world_to_chunk(crop.position)
	if not _crops_by_chunk.has(chunk):
		_crops_by_chunk[chunk] = {}
	(_crops_by_chunk[chunk] as Dictionary)[crop.id] = true
	_next_crop_id = maxi(_next_crop_id, crop.id + 1)
	crop_updated.emit(crop.id, true)

# Harvest queries measure distance to fruit, not the watermelon root.
func get_crop_near(position: Vector3, radius: float = 0.6, harvestable_only: bool = false) -> CropData:
	var closest: CropData = null
	var best := radius * radius
	var chunk := world_to_chunk(position)
	var reach := maxi(1, ceili((CropSpecies.MAX_SPREAD + radius) / simulation_chunk_size_tiles))
	var minute := get_current_total_minutes()
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			for id: int in get_chunk_crop_ids(chunk + Vector2i(dx, dz)):
				var crop := get_crop(id)
				if crop == null:
					continue
				if crop.crop_type == &"watermelon":
					for index in range(CropSpecies.FRUIT_COUNT):
						if crop.harvested_fruits.has(index) or CropSpecies.fruit_progress(index, crop.progress(minute)) <= 0.0:
							continue
						if harvestable_only and not crop.fruit_is_harvestable(index, minute):
							continue
						var fruit := crop.fruit_position(index)
						var distance := Vector2(position.x, position.z).distance_squared_to(Vector2(fruit.x, fruit.z))
						if distance <= best:
							closest = crop
							best = distance
				else:
					if harvestable_only and not crop.is_harvestable(minute):
						continue
					var distance := Vector2(position.x, position.z).distance_squared_to(Vector2(crop.position.x, crop.position.z))
					if distance <= best:
						closest = crop
						best = distance
	return closest

func harvest_at(position: Vector3, radius: float = 0.6) -> Dictionary:
	var crop := get_crop_near(position, radius, true)
	if crop == null:
		return {}
	if crop.crop_type != &"watermelon":
		return harvest_crop_id(crop.id)
	var selected := -1
	var best := radius * radius
	for index in range(CropSpecies.FRUIT_COUNT):
		if not crop.fruit_is_harvestable(index, get_current_total_minutes()):
			continue
		var fruit := crop.fruit_position(index)
		var distance := Vector2(position.x, position.z).distance_squared_to(Vector2(fruit.x, fruit.z))
		if distance <= best:
			selected = index
			best = distance
	if selected < 0:
		return {}
	return _harvest_fruit(crop, selected)

func _harvest_fruit(crop: CropData, index: int) -> Dictionary:
	crop.harvested_fruits.append(index)
	crop_updated.emit(crop.id, true)
	return {"crop_type": crop.crop_type, "yield": 1, "fruit_index": index}

func get_crop_covered_tiles(crop_id: int, at_minute: int = -1) -> Array[Vector2i]:
	var crop := get_crop(crop_id)
	var tiles: Array[Vector2i] = []
	if crop == null:
		return tiles
	var minute := get_current_total_minutes() if at_minute < 0 else at_minute
	if crop.crop_type == &"watermelon":
		var covered: Dictionary = {world_to_grid(crop.position): true}
		var paths := crop.vine_paths()
		for index in range(paths.size()):
			var path := paths[index]
			var extent := CropSpecies.path_growth(index, crop.progress(minute)) * (path.size() - 1)
			if extent <= 0.0:
				continue
			for node in range(ceili(extent) + 1):
				var segment := mini(node, floori(extent))
				var point := crop.position + path[segment]
				if node > segment and segment + 1 < path.size():
					point = crop.position + path[segment].lerp(path[segment + 1], extent - segment)
				for z in range(floori(point.z - 0.25), floori(point.z + 0.25) + 1):
					for x in range(floori(point.x - 0.25), floori(point.x + 0.25) + 1):
						covered[Vector2i(x, z)] = true
		for tile: Vector2i in covered:
			tiles.append(tile)
		return tiles
	var radius := lerpf(crop.seed_radius, crop.mature_radius, crop.progress(minute))
	for z in range(floori(crop.position.z - radius), floori(crop.position.z + radius) + 1):
		for x in range(floori(crop.position.x - radius), floori(crop.position.x + radius) + 1):
			var closest := Vector2(clampf(crop.position.x, float(x), float(x + 1)), clampf(crop.position.z, float(z), float(z + 1)))
			if closest.distance_squared_to(Vector2(crop.position.x, crop.position.z)) <= radius * radius:
				tiles.append(Vector2i(x, z))
	return tiles

func harvest_crop_id(crop_id: int) -> Dictionary:
	var crop := get_crop(crop_id)
	if crop == null or not crop.is_harvestable(get_current_total_minutes()):
		return {}
	if crop.crop_type == &"watermelon":
		# ID-only callers harvest one ripe fruit too; never erase the whole vine.
		for index in range(CropSpecies.FRUIT_COUNT):
			if crop.fruit_is_harvestable(index, get_current_total_minutes()):
				return _harvest_fruit(crop, index)
		return {}
	_remove_crop(crop_id)
	return {"crop_type": crop.crop_type, "yield": 1}

func _remove_crop(crop_id: int) -> void:
	var crop := get_crop(crop_id)
	if crop == null:
		return
	var chunk := world_to_chunk(crop.position)
	(_crops_by_chunk[chunk] as Dictionary).erase(crop_id)
	if (_crops_by_chunk[chunk] as Dictionary).is_empty():
		_crops_by_chunk.erase(chunk)
	_crops.erase(crop_id)
	crop_updated.emit(crop_id, false)

func export_crops() -> Array:
	var result: Array = []
	for crop_any: Variant in _crops.values():
		result.append((crop_any as CropData).to_dict())
	return result

func import_crops(entries: Array) -> void:
	_crops.clear()
	_crops_by_chunk.clear()
	_next_crop_id = 1
	for entry_any: Variant in entries:
		if entry_any is not Dictionary:
			continue
		var crop := CropData.from_dict(entry_any)
		if crop != null and crop.id > 0 and not _crops.has(crop.id):
			_register_crop(crop)

func is_chunk_loaded(chunk_pos: Vector2i) -> bool:
	return not _chunk_unloaded_at_minute.has(chunk_pos)

func get_current_total_minutes() -> int:
	if GameManager.session != null and GameManager.session.time != null:
		return GameManager.session.time.get_total_minutes()
	return 0

func get_tile_growth_progress(grid_pos: Vector2i, at_total_minutes: int = -1) -> float:
	var center := grid_to_world_center(grid_pos)
	var crop := get_crop_near(Vector3(center.x, 0, center.y), 0.71)
	return crop.progress(get_current_total_minutes() if at_total_minutes < 0 else at_total_minutes) if crop != null else 0.0

# Sets the state of a tile and alerts listeners (like GridManager)
func set_tile_state(grid_pos: Vector2i, new_state: int, world_height: float = NAN, should_emit: bool = true) -> void:
	var had_existing := _grid.has(grid_pos)
	if had_existing:
		_remove_tile_from_indices(grid_pos)

	var data: FarmTileData = get_tile_data(grid_pos)
	data.state = new_state

	if new_state == SoilState.GRASS:
		for id: int in get_chunk_crop_ids(grid_to_chunk(grid_pos)):
			var crop := get_crop(id)
			if crop != null and world_to_grid(crop.position) == grid_pos:
				_remove_crop(id)

	# Height should be captured when creating/refreshing soil patches, not during later state swaps.
	if not is_nan(world_height) and (new_state == SoilState.PLOWED or not had_existing):
		data.height = world_height

	if new_state == SoilState.GRASS:
		if had_existing:
			_grid.erase(grid_pos)
			if should_emit:
				self.emit_signal("tile_updated", grid_pos, SoilState.GRASS)
		return

	_grid[grid_pos] = data
	_register_tile_in_indices(grid_pos, data)
	if should_emit:
		self.emit_signal("tile_updated", grid_pos, new_state)

func set_active_region_mask(mask: MapRegionMask) -> void:
	active_region_mask = mask

func get_raw_region_value(world_pos: Vector3) -> int:
	if active_region_mask != null:
		return active_region_mask.get_raw_pixel_value(world_pos)
	return -1

func can_plow_at(world_pos: Vector3) -> bool:
	if active_region_mask != null:
		return active_region_mask.get_region_at(world_pos) == MapRegionMask.RegionType.FARMABLE
	return true # Default to true if no mask is provided for backwards compatibility/testing

func plant_crop(
	grid_pos: Vector2i,
	crop_type: StringName = &"generic",
	growth_minutes_required: int = DEFAULT_CROP_GROWTH_MINUTES,
	world_height: float = NAN
) -> bool:
	var center := grid_to_world_center(grid_pos)
	var height := get_tile_data(grid_pos).height if is_nan(world_height) else world_height
	return plant_crop_at(Vector3(center.x, height, center.y), crop_type, growth_minutes_required) > 0

func harvest_crop(grid_pos: Vector2i) -> Dictionary:
	var center := grid_to_world_center(grid_pos)
	var crop := get_crop_near(Vector3(center.x, 0, center.y), 0.71, true)
	return harvest_crop_id(crop.id) if crop != null else {}

func mark_chunk_unloaded(chunk_pos: Vector2i) -> void:
	if _chunk_unloaded_at_minute.has(chunk_pos):
		return

	var unloaded_at: int = get_current_total_minutes()
	_chunk_unloaded_at_minute[chunk_pos] = unloaded_at
	_loaded_chunks.erase(chunk_pos)
	emit_signal("chunk_unloaded", chunk_pos, unloaded_at)

func mark_chunk_loaded(chunk_pos: Vector2i, emit_tile_updates: bool = true) -> void:
	var now_minutes := get_current_total_minutes()
	var catch_up_seconds := 0
	if _chunk_unloaded_at_minute.has(chunk_pos):
		var unloaded_at: int = _chunk_unloaded_at_minute[chunk_pos]
		_chunk_unloaded_at_minute.erase(chunk_pos)
		if now_minutes > unloaded_at:
			_simulate_chunk_to_minute(chunk_pos, now_minutes, emit_tile_updates)
		catch_up_seconds = maxi(0, (now_minutes - unloaded_at) * 60)

	_loaded_chunks[chunk_pos] = true
	emit_signal("chunk_loaded", chunk_pos, catch_up_seconds)

func simulate_chunk_passage_of_time(chunk_pos: Vector2i, delta_seconds: int, emit_tile_updates: bool = false) -> void:
	if delta_seconds <= 0:
		return

	var delta_minutes := int(floor(float(delta_seconds) / 60.0))
	if delta_minutes <= 0:
		return

	var target_minute := get_current_total_minutes() + delta_minutes
	_simulate_chunk_to_minute(chunk_pos, target_minute, emit_tile_updates)

func simulate_passage_of_time(delta_seconds: int, emit_tile_updates: bool = false, target_chunks: Array = []) -> void:
	if delta_seconds <= 0:
		return

	var delta_minutes := int(floor(float(delta_seconds) / 60.0))
	if delta_minutes <= 0:
		return

	var target_minute := get_current_total_minutes() + delta_minutes
	var chunks_to_simulate: Array = target_chunks
	if chunks_to_simulate.is_empty():
		chunks_to_simulate = _crops_by_chunk.keys()

	for chunk_any: Variant in chunks_to_simulate:
		if chunk_any is Vector2i:
			_simulate_chunk_to_minute(chunk_any, target_minute, emit_tile_updates)

# Completely clears a tile back to default grass
func reset_tile(grid_pos: Vector2i) -> void:
	if _grid.has(grid_pos):
		for id: int in get_chunk_crop_ids(grid_to_chunk(grid_pos)):
			var crop := get_crop(id)
			if crop != null and world_to_grid(crop.position) == grid_pos:
				_remove_crop(id)
		_remove_tile_from_indices(grid_pos)
		_grid.erase(grid_pos)
		emit_signal("tile_updated", grid_pos, SoilState.GRASS)

func _on_minute_passed() -> void:
	var now_minutes := get_current_total_minutes()
	if now_minutes == _last_processed_minute:
		return

	_last_processed_minute = now_minutes
	var chunks_to_simulate: Array[Vector2i] = _get_chunks_to_simulate_on_tick()
	for chunk_pos: Vector2i in chunks_to_simulate:
		_simulate_chunk_to_minute(chunk_pos, now_minutes, true)

func _get_chunks_to_simulate_on_tick() -> Array[Vector2i]:
	var chunks: Array[Vector2i] = []

	# DESIGN NOTE: If no GridManager has registered any chunks as loaded/unloaded,
	# we fall back to simulating ALL seeded chunks. This ensures crop growth
	# continues even if chunk streaming is disabled or the GridManager is absent.
	# The chunk system is purely a 3D rendering optimisation — simulation must
	# never stall because of it.
	if _loaded_chunks.is_empty() and _chunk_unloaded_at_minute.is_empty():
		for chunk_pos_any: Variant in _crops_by_chunk.keys():
			if chunk_pos_any is Vector2i:
				chunks.append(chunk_pos_any)
		return chunks

	for chunk_pos_any: Variant in _loaded_chunks.keys():
		if chunk_pos_any is Vector2i and _crops_by_chunk.has(chunk_pos_any):
			chunks.append(chunk_pos_any)

	return chunks

func _simulate_chunk_to_minute(chunk_pos: Vector2i, target_minute: int, _emit_tile_updates: bool) -> void:
	if not _crops_by_chunk.has(chunk_pos):
		return
	for id: int in get_chunk_crop_ids(chunk_pos):
		var crop := get_crop(id)
		if crop != null and target_minute > crop.simulated_until_minute:
			crop.simulated_until_minute = target_minute
	# Growth is continuous data state. GridManager polls visible crops with a frame budget;
	# crop_updated is reserved for discrete events such as planting, fruit harvest, and removal.

func _register_tile_in_indices(grid_pos: Vector2i, _tile_data: FarmTileData) -> void:
	var chunk_pos := grid_to_chunk(grid_pos)
	if not _tiles_by_chunk.has(chunk_pos):
		_tiles_by_chunk[chunk_pos] = {}
	var chunk_tiles: Dictionary = _tiles_by_chunk[chunk_pos]
	chunk_tiles[grid_pos] = true

func _remove_tile_from_indices(grid_pos: Vector2i) -> void:
	var chunk_pos := grid_to_chunk(grid_pos)

	if _tiles_by_chunk.has(chunk_pos):
		var chunk_tiles: Dictionary = _tiles_by_chunk[chunk_pos]
		chunk_tiles.erase(grid_pos)
		if chunk_tiles.is_empty():
			_tiles_by_chunk.erase(chunk_pos)

func load_map_fields_from_json(file_path: String, offset: Vector2 = Vector2.ZERO) -> void:
	if file_path.is_empty() or not FileAccess.file_exists(file_path):
		GameLog.warn("No field data JSON found at: " + file_path)
		return
		
	var file_string := FileAccess.get_file_as_string(file_path)
	var json_data: Variant = JSON.parse_string(file_string)
	
	if json_data == null or not typeof(json_data) == TYPE_DICTIONARY:
		GameLog.error("Failed to parse field data JSON or invalid format: " + file_path)
		return
	
	map_fields.clear()
	var dict_data: Dictionary = json_data
	for field_key_any: Variant in dict_data.keys():
		var field_key: String = str(field_key_any)
		var field_obj: Variant = dict_data[field_key_any]
		if typeof(field_obj) == TYPE_ARRAY:
			var points_array: Array = field_obj
			if points_array.is_empty():
				continue
			var polygon := FieldPolygon.new()
			polygon.id = StringName(field_key)
			for p_dict_any: Variant in points_array:
				if typeof(p_dict_any) == TYPE_DICTIONARY:
					var p_dict: Dictionary = p_dict_any
					if p_dict.has("x") and p_dict.has("z"):
						polygon.points.append(Vector2(float(p_dict["x"]), float(p_dict["z"])) + offset)
			
			if not polygon.points.is_empty():
				polygon.calculate_bounds()
				map_fields.append(polygon)

func generate_initial_plowed_fields() -> void:
	for field in map_fields:
		var bounds: Rect2i = field.bounds
		for x in range(bounds.position.x, bounds.end.x):
			for y in range(bounds.position.y, bounds.end.y):
				var grid_pos := Vector2i(x, y)
				var center_point := grid_to_world_center(grid_pos)
				if Geometry2D.is_point_in_polygon(center_point, field.points):
					# Intentionally pass false to emit_signal so we batch updates and avoid a signal storm
					set_tile_state(grid_pos, SoilState.PLOWED, NAN, false)

func clear_runtime_state(keep_region_mask: bool = true) -> void:
	_grid.clear()
	_tiles_by_chunk.clear()
	_crops.clear()
	_crops_by_chunk.clear()
	_next_crop_id = 1
	_chunk_unloaded_at_minute.clear()
	_loaded_chunks.clear()
	_last_processed_minute = -1
	if not keep_region_mask:
		active_region_mask = null

func rebuild_active_growth_chunk_index() -> void:
	_tiles_by_chunk.clear()

	for grid_pos_any: Variant in _grid.keys():
		if grid_pos_any is not Vector2i:
			continue
		var grid_pos: Vector2i = grid_pos_any
		var tile_data: FarmTileData = _grid[grid_pos]
		_register_tile_in_indices(grid_pos, tile_data)

func get_heatmap_resolution() -> Vector2i:
	if active_region_mask != null and active_region_mask.mask_texture != null:
		var width := maxi(1, active_region_mask.mask_texture.get_width())
		var height := maxi(1, active_region_mask.mask_texture.get_height())
		return Vector2i(width, height)
	return Vector2i(1024, 1024)

func _grid_to_heatmap_pixel(grid_pos: Vector2i, width: int, height: int) -> Vector2i:
	var safe_width := maxi(width, 1)
	var safe_height := maxi(height, 1)
	var world_size := 2048.0
	var world_center := Vector2.ZERO
	if active_region_mask != null:
		world_size = maxf(active_region_mask.world_size_meters, 1.0)
		world_center = active_region_mask.world_center_position

	var tile_center: Vector2 = grid_to_world_center(grid_pos)
	var half_size := world_size * 0.5
	var percent_x: float = (tile_center.x - world_center.x + half_size) / world_size
	var percent_y: float = (tile_center.y - world_center.y + half_size) / world_size

	var pixel_x: int = int(floor(percent_x * float(safe_width)))
	var pixel_y: int = int(floor(percent_y * float(safe_height)))

	if pixel_x < 0 or pixel_x >= safe_width or pixel_y < 0 or pixel_y >= safe_height:
		return Vector2i(-1, -1)

	return Vector2i(pixel_x, pixel_y)

func _heatmap_pixel_to_grid(pixel: Vector2i, width: int, height: int) -> Vector2i:
	var safe_width := maxi(width, 1)
	var safe_height := maxi(height, 1)
	var world_size := 2048.0
	var world_center := Vector2.ZERO
	if active_region_mask != null:
		world_size = maxf(active_region_mask.world_size_meters, 1.0)
		world_center = active_region_mask.world_center_position

	var half_size := world_size * 0.5
	var world_x: float = world_center.x - half_size + ((float(pixel.x) + 0.5) / float(safe_width)) * world_size
	var world_z: float = world_center.y - half_size + ((float(pixel.y) + 0.5) / float(safe_height)) * world_size

	return world_to_grid(Vector3(world_x, 0.0, world_z))

func export_heatmap_layers(crop_to_id: Dictionary) -> Dictionary:
	var resolution: Vector2i = get_heatmap_resolution()
	var width := maxi(resolution.x, 1)
	var height := maxi(resolution.y, 1)

	var soil_image := Image.create(width, height, false, Image.FORMAT_L8)
	soil_image.fill(Color(0, 0, 0, 1))

	var crop_image := Image.create(width, height, false, Image.FORMAT_L8)
	crop_image.fill(Color(0, 0, 0, 1))

	var planted_time_image := Image.create(width, height, false, Image.FORMAT_RF)
	planted_time_image.fill(Color(-1.0, 0, 0, 1))

	for grid_pos_any: Variant in _grid.keys():
		if grid_pos_any is not Vector2i:
			continue
		var grid_pos: Vector2i = grid_pos_any
		var tile_data: FarmTileData = _grid[grid_pos]
		var pixel: Vector2i = _grid_to_heatmap_pixel(grid_pos, width, height)
		if pixel.x < 0 or pixel.y < 0:
			continue

		soil_image.set_pixelv(pixel, Color(float(SoilState.PLOWED if tile_data.state != SoilState.GRASS else SoilState.GRASS) / 255.0, 0, 0, 1))

	return {
		"soil_state": soil_image,
		"crop_type": crop_image,
		"planted_time": planted_time_image
	}

func import_heatmap_layers(soil_image: Image, crop_image: Image, planted_time_image: Image, id_to_crop: Dictionary) -> void:
	if soil_image == null or crop_image == null:
		return

	clear_runtime_state(true)

	var width := mini(soil_image.get_width(), crop_image.get_width())
	var height := mini(soil_image.get_height(), crop_image.get_height())
	if planted_time_image != null:
		width = mini(width, planted_time_image.get_width())
		height = mini(height, planted_time_image.get_height())

	if width <= 0 or height <= 0:
		return

	for y: int in range(height):
		for x: int in range(width):
			var soil_value: int = int(round(soil_image.get_pixel(x, y).r * 255.0))
			var crop_value: int = int(round(crop_image.get_pixel(x, y).r * 255.0))
			if soil_value == SoilState.GRASS and crop_value == 0:
				continue

			var grid_pos := _heatmap_pixel_to_grid(Vector2i(x, y), width, height)
			var tile := FarmTileData.new()
			tile.state = SoilState.PLOWED if soil_value != SoilState.GRASS or crop_value > 0 else SoilState.GRASS

			if crop_value > 0 and id_to_crop.has(str(crop_value)):
				var planted := get_current_total_minutes()
				if planted_time_image != null:
					planted = maxi(0, int(round(planted_time_image.get_pixel(x, y).r)))
				var center := grid_to_world_center(grid_pos)
				var crop := CropData.new()
				crop.id = _next_crop_id
				crop.crop_type = StringName(String(id_to_crop[str(crop_value)]))
				crop.position = Vector3(center.x, tile.height, center.y)
				crop.planted_at_minute = planted
				crop.simulated_until_minute = get_current_total_minutes()
				_register_crop(crop)

			_grid[grid_pos] = tile

	rebuild_active_growth_chunk_index()
