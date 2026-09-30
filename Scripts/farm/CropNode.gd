extends Node3D

var crop_id: int
var _mesh_instance: MeshInstance3D
var _last_signature: String = ""
var _height_cache: Dictionary = {}
var _lod_timer: float = 0.0

func _ready() -> void:
	add_to_group("crop_node")
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	var farm := GameManager.session.farm
	farm.crop_updated.connect(_on_crop_updated)
	refresh_from_data()

func _exit_tree() -> void:
	if GameManager.session != null and GameManager.session.farm != null:
		var farm := GameManager.session.farm
		if farm.crop_updated.is_connected(_on_crop_updated):
			farm.crop_updated.disconnect(_on_crop_updated)

func _process(delta: float) -> void:
	_lod_timer += delta
	if _lod_timer >= 1.0:
		_lod_timer = 0.0
		refresh_from_data()

func refresh_from_data() -> void:
	if _mesh_instance == null:
		return
	var farm := GameManager.session.farm
	var crop := farm.get_crop(crop_id)
	if crop == null:
		queue_free()
		return
	global_position = crop.position
	var camera := get_viewport().get_camera_3d()
	var detailed := camera == null or camera.global_position.distance_squared_to(crop.position) < 24.0 * 24.0
	# Quantize to avoid rebuilding every simulated minute; mature geometry is cached.
	var step := floori(crop.progress(farm.get_current_total_minutes()) * 100.0)
	var signature := "%d:%s:%s" % [step, str(crop.harvested_fruits), str(detailed)]
	if signature == _last_signature:
		return
	_last_signature = signature
	var builder := CropVisualBuilder.new()
	builder.ground_height = _local_ground_height
	_mesh_instance.mesh = builder.build(crop, float(step) / 100.0, detailed)

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

func _on_crop_updated(updated_id: int, exists: bool) -> void:
	if updated_id != crop_id:
		return
	if exists:
		refresh_from_data()
	else:
		queue_free()
