class_name CropSpecies
extends RefCounted

# World-space dimensions, deliberately independent of the one-metre soil grid.
const MAX_SPREAD := 4.8
const FRUIT_COUNT := 4

static func display_name(species: StringName) -> String:
	return "西瓜" if species == &"watermelon" else "向日葵"

static func seed_radius(species: StringName) -> float:
	return 0.45 if species == &"watermelon" else 0.12

static func mature_radius(species: StringName) -> float:
	return MAX_SPREAD if species == &"watermelon" else 0.42

static func growth_minutes(species: StringName) -> int:
	return 5 * 24 * 60 if species == &"watermelon" else 3 * 24 * 60

static func item_id(species: StringName) -> StringName:
	return &"item.watermelon" if species == &"watermelon" else &"item.sunflower"

# Seeded paths are immutable: extending growth reveals more of the same vine.
# Four main runners and two lateral branches per runner, with bounded geometry.
static func vine_paths(shape_seed: int) -> Array[PackedVector3Array]:
	var rng := RandomNumberGenerator.new()
	rng.seed = shape_seed
	var paths: Array[PackedVector3Array] = []
	var orientation := rng.randf_range(0.0, TAU)
	for runner in range(4):
		var angle := orientation + runner * TAU / 4.0 + rng.randf_range(-0.25, 0.25)
		var path := PackedVector3Array([Vector3.ZERO])
		var point := Vector3.ZERO
		for segment in range(12):
			angle += rng.randf_range(-0.19, 0.19)
			point += Vector3(cos(angle), 0.0, sin(angle)) * rng.randf_range(0.24, 0.32)
			path.append(point)
		paths.append(path)
	for runner in range(4):
		for branch in range(2):
			var source := paths[runner]
			var junction := 4 + branch * 3
			var point := source[junction]
			var direction := source[junction] - source[junction - 1]
			var angle := atan2(direction.z, direction.x) + (1.0 if branch == 0 else -1.0) * 0.85
			var path := PackedVector3Array([point])
			for segment in range(5):
				angle += rng.randf_range(-0.22, 0.22)
				point += Vector3(cos(angle), 0.0, sin(angle)) * 0.23
				path.append(point)
			paths.append(path)
	return paths

static func path_growth(path_index: int, progress: float) -> float:
	var start := 0.13 if path_index < 4 else (0.32 if path_index % 2 == 0 else 0.48)
	return clampf((progress - start) / (0.82 - start), 0.0, 1.0)

static func fruit_offset(paths: Array[PackedVector3Array], index: int) -> Vector3:
	var path := paths[index]
	var node := 7 + index % 3
	var tangent := (path[node] - path[node - 1]).normalized()
	return path[node] + Vector3(-tangent.z, 0.0, tangent.x) * 0.19

static func fruit_progress(index: int, progress: float) -> float:
	var start := 0.56 + index * 0.035
	var ripe := 0.85 + index * 0.05
	return clampf((progress - start) / (ripe - start), 0.0, 1.0)
