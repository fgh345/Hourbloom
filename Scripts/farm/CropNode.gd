extends Node3D

var crop_id: int

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
var _harvest_material: StandardMaterial3D

func _ready() -> void:
	add_to_group("crop_node")
	if GameManager.session != null and GameManager.session.farm != null:
		var farm := GameManager.session.farm
		if not farm.crop_updated.is_connected(_on_crop_updated):
			farm.crop_updated.connect(_on_crop_updated)
	scale = Vector3.ONE * 0.2
	refresh_from_data()

func _exit_tree() -> void:
	if GameManager.session != null and GameManager.session.farm != null:
		var farm := GameManager.session.farm
		if farm.crop_updated.is_connected(_on_crop_updated):
			farm.crop_updated.disconnect(_on_crop_updated)

func refresh_from_data() -> void:
	var farm := GameManager.session.farm
	var crop := farm.get_crop(crop_id)
	if crop == null:
		queue_free()
		return
	var size := lerpf(0.2, 1.0, crop.progress(farm.get_current_total_minutes()))
	# Crowded plants stay smaller so their placeholder meshes do not overlap.
	var chunk := farm.world_to_chunk(crop.position)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			for other_id: int in farm.get_chunk_crop_ids(chunk + Vector2i(dx, dz)):
				if other_id == crop_id:
					continue
				var other := farm.get_crop(other_id)
				var distance := Vector2(crop.position.x, crop.position.z).distance_to(Vector2(other.position.x, other.position.z))
				size = minf(size, distance / (crop.mature_radius + other.mature_radius))
	scale = Vector3.ONE * maxf(0.01, size)
	set_harvestable_visual(crop.is_harvestable(farm.get_current_total_minutes()))

func set_harvestable_visual(is_harvestable: bool) -> void:
	if not is_harvestable:
		mesh_instance.set_surface_override_material(0, null)
		return

	if _harvest_material == null:
		_harvest_material = StandardMaterial3D.new()
		_harvest_material.albedo_color = Color(0.8, 0.8, 0.1)

	mesh_instance.set_surface_override_material(0, _harvest_material)

func _on_crop_updated(updated_id: int, exists: bool) -> void:
	if updated_id != crop_id:
		return
	if exists:
		refresh_from_data()
		return
	queue_free()
