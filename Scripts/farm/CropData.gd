class_name CropData
extends RefCounted

var id: int
var crop_type: StringName = &"generic"
var position: Vector3
var planted_at_minute: int
var simulated_until_minute: int = 0
var growth_minutes_required: int = 3 * 24 * 60
# Physical footprint at planting and potential adult canopy. Species can override these.
var seed_radius: float = 0.05
var mature_radius: float = 0.25
var shape_seed: int = 0
var harvested_fruits: Array[int] = []
var _vine_paths: Array[PackedVector3Array] = []

func progress(at_minute: int) -> float:
	return clampf(float(maxi(0, maxi(at_minute, simulated_until_minute) - planted_at_minute)) / float(maxi(1, growth_minutes_required)), 0.0, 1.0)

func is_harvestable(at_minute: int) -> bool:
	if crop_type == &"watermelon":
		for index in range(CropSpecies.FRUIT_COUNT):
			if fruit_is_harvestable(index, at_minute):
				return true
		return false
	return progress(at_minute) >= 1.0

func vine_paths() -> Array[PackedVector3Array]:
	if _vine_paths.is_empty():
		_vine_paths = CropSpecies.vine_paths(shape_seed if shape_seed != 0 else id)
	return _vine_paths

func fruit_is_harvestable(index: int, at_minute: int) -> bool:
	return index >= 0 and index < CropSpecies.FRUIT_COUNT and not harvested_fruits.has(index) and CropSpecies.fruit_progress(index, progress(at_minute)) >= 1.0

func fruit_position(index: int) -> Vector3:
	return position + CropSpecies.fruit_offset(vine_paths(), index)

func to_dict() -> Dictionary:
	return {"id": id, "type": String(crop_type), "position": [position.x, position.y, position.z],
		"planted_at": planted_at_minute, "simulated_until": simulated_until_minute, "growth_minutes": growth_minutes_required,
		"seed_radius": seed_radius, "mature_radius": mature_radius,
		"shape_seed": shape_seed, "harvested_fruits": harvested_fruits.duplicate()}

static func from_dict(value: Dictionary) -> CropData:
	var coordinates: Array = value.get("position", [])
	if coordinates.size() != 3:
		return null
	var crop := CropData.new()
	crop.id = int(value.get("id", 0))
	crop.crop_type = StringName(str(value.get("type", "generic")))
	crop.position = Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
	crop.planted_at_minute = maxi(0, int(value.get("planted_at", 0)))
	crop.simulated_until_minute = maxi(crop.planted_at_minute, int(value.get("simulated_until", crop.planted_at_minute)))
	crop.growth_minutes_required = maxi(1, int(value.get("growth_minutes", 3 * 24 * 60)))
	crop.seed_radius = maxf(0.001, float(value.get("seed_radius", 0.05)))
	crop.mature_radius = maxf(crop.seed_radius, float(value.get("mature_radius", 0.25)))
	crop.shape_seed = int(value.get("shape_seed", crop.id))
	for index: Variant in value.get("harvested_fruits", []):
		if int(index) >= 0 and int(index) < CropSpecies.FRUIT_COUNT and not crop.harvested_fruits.has(int(index)):
			crop.harvested_fruits.append(int(index))
	# Legacy generic plants retain their timing and become sunflowers visually.
	if crop.crop_type == &"watermelon":
		crop.mature_radius = CropSpecies.MAX_SPREAD
	return crop
