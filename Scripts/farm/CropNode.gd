extends Node3D

var crop_id: int
var _rig: CropVisualRig
var _height_cache: Dictionary = {}
var _lod_timer: float = 0.0
var _progress: float = 0.0
var _day_controller: DayNightController
var _last_detail: bool = true
var _visual_root: Node3D
var _harvested: Array = []

func _ready() -> void:
	add_to_group("crop_node")
	_day_controller = get_tree().get_first_node_in_group("day_night_controller") as DayNightController
	refresh_from_data()

func _process(delta: float) -> void:
	_lod_timer += delta
	if _lod_timer >= 1.0:
		_lod_timer = 0.0
		if not is_instance_valid(_day_controller):
			_day_controller = get_tree().get_first_node_in_group("day_night_controller") as DayNightController
		refresh_from_data()
	if _rig != null and not _rig.is_melon and _progress >= 0.55:
		var day := float(posmod(GameManager.session.farm.get_current_total_minutes(), 1440)) / 1440.0
		var frame := Basis.IDENTITY
		if is_instance_valid(_day_controller):
			day = _day_controller.current_day_progress
			if is_instance_valid(_day_controller.sun_light):
				var light := _day_controller.sun_light
				frame = light.get_parent_node_3d().global_basis * Basis.from_euler(Vector3(0.0, light.rotation.y, light.rotation.z))
		_rig.pose(day, _progress, global_basis.inverse() * frame)

func refresh_from_data() -> void:
	var farm := GameManager.session.farm
	var crop := farm.get_crop(crop_id)
	if crop == null:
		queue_free()
		return
	global_position = crop.position
	var camera := get_viewport().get_camera_3d()
	var detailed := camera == null or camera.global_position.distance_squared_to(crop.position) < 24.0 * 24.0
	if _rig == null or detailed != _last_detail:
		if _visual_root != null:
			remove_child(_visual_root)
			_visual_root.queue_free()
		_visual_root = Node3D.new()
		add_child(_visual_root)
		_rig = CropVisualRig.new()
		_rig.initialize(_visual_root, crop, detailed, _local_ground_height)
		_last_detail = detailed
		_progress = -1.0
	var next_progress := crop.progress(farm.get_current_total_minutes())
	if not is_equal_approx(next_progress, _progress) or _harvested != crop.harvested_fruits or _rig.stems.visible_instance_count == 0:
		_progress = next_progress
		_harvested = crop.harvested_fruits.duplicate()
		_rig.update(crop, _progress)

func _local_ground_height(point: Vector3) -> float:
	var key := Vector2(point.x, point.z)
	if _height_cache.has(key):
		return _height_cache[key]
	var world_point := global_position + point
	var query := PhysicsRayQueryParameters3D.create(world_point + Vector3.UP * 3.0, world_point - Vector3.UP * 3.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	var height := 0.0
	if not hit.is_empty() and (hit["normal"] as Vector3).dot(Vector3.UP) > 0.5:
		height = (hit["position"] as Vector3).y - global_position.y
	_height_cache[key] = height
	return height
