class_name CropVisualRig
extends RefCounted

# Mesh resources are shared across plants. Growth only changes instance transforms.
static var _meshes: Dictionary = {}
var root: Node3D
var stems: MultiMesh
var leaves: MultiMesh
var head: MeshInstance3D
var bud: MeshInstance3D
var fruits: Array[MeshInstance3D] = []
var flowers: Array[MeshInstance3D] = []
var paths: Array[PackedVector3Array] = []
var fruit_ground: Array[Vector3] = []
var detailed: bool
var is_melon: bool
var _stem_count := 0
var _leaf_count := 0
var _angle := 0.0
var _neck := Vector3.ZERO
var _neck_length := 0.0

static func mesh(kind: String, detail: bool = true) -> ArrayMesh:
	var key := "%s:%s" % [kind, detail]
	if not _meshes.has(key):
		_meshes[key] = CropVisualBuilder.new().reusable_part(kind, detail)
	return _meshes[key]

func initialize(parent: Node3D, crop: CropData, detail: bool, ground: Callable) -> void:
	root = parent
	detailed = detail
	is_melon = crop.crop_type == &"watermelon"
	_angle = float(posmod(crop.shape_seed, 628)) / 100.0
	_instance("soil")
	stems = _pool("stem", 210 if is_melon else 20)
	leaves = _pool("lobed" if is_melon else "leaf", 110 if is_melon else 10)
	if is_melon:
		var source := crop.vine_paths()
		for path in source:
			var sampled := PackedVector3Array()
			for point in path:
				sampled.append(Vector3(point.x, float(ground.call(point)) + 0.025, point.z))
			paths.append(sampled)
		for index in range(4):
			var point := CropSpecies.fruit_offset(source, index)
			fruit_ground.append(Vector3(point.x, float(ground.call(point)) + 0.025, point.z))
			fruits.append(_instance("melon"))
			flowers.append(_instance("flower"))
	else:
		head = _instance("head")
		bud = _instance("bud")

func _instance(kind: String) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh(kind, detailed)
	root.add_child(node)
	return node

func _pool(kind: String, count: int) -> MultiMesh:
	var pool := MultiMesh.new()
	pool.transform_format = MultiMesh.TRANSFORM_3D
	pool.mesh = mesh(kind, detailed)
	pool.instance_count = count
	pool.visible_instance_count = 0
	var node := MultiMeshInstance3D.new()
	node.multimesh = pool
	root.add_child(node)
	return pool

func _stem(a: Vector3, b: Vector3, radius: float) -> void:
	var vector := b - a
	if vector.length_squared() < 0.000001:
		return
	var basis := Basis(Quaternion(Vector3.UP, vector.normalized())).scaled(Vector3(radius, vector.length(), radius))
	stems.set_instance_transform(_stem_count, Transform3D(basis, a + vector * 0.5))
	_stem_count += 1

func _leaf(point: Vector3, angle: float, size: float) -> void:
	leaves.set_instance_transform(_leaf_count, Transform3D(Basis(Vector3.UP, -angle).scaled(Vector3.ONE * size), point))
	_leaf_count += 1

func update(crop: CropData, progress: float) -> void:
	_stem_count = 0
	_leaf_count = 0
	if is_melon:
		_watermelon(crop, progress)
	else:
		_sunflower(progress)
	stems.visible_instance_count = _stem_count
	leaves.visible_instance_count = _leaf_count

func _sunflower(progress: float) -> void:
	head.visible = progress > 0.68
	bud.visible = progress >= 0.55 and progress <= 0.68
	if progress < 0.06:
		return
	var growth := clampf((progress - 0.06) / 0.68, 0.0, 1.0)
	var height := lerpf(0.07, 1.65, growth)
	var top := Vector3(0.05 * growth, height, 0.025 * growth)
	_neck = top * 0.88
	_neck_length = top.length() * 0.12
	_stem(Vector3.ZERO, _neck, lerpf(0.009, 0.026, growth))
	_stem(_neck, top, lerpf(0.009, 0.022, growth))
	_leaf(Vector3(0, height * 0.22, 0), _angle, 0.09 + 0.05 * growth)
	_leaf(Vector3(0, height * 0.22, 0), _angle + PI, 0.09 + 0.05 * growth)
	for index in range(8 if detailed else 4):
		var leaf_growth := clampf(growth * 9.0 - index, 0.0, 1.0)
		if leaf_growth <= 0.0:
			continue
		var point := top * (0.20 + index * 0.60 / 7.0)
		var angle := _angle + index * 2.39996
		var leaf_root := point + Vector3(cos(angle), 0.28, sin(angle)) * 0.08 * leaf_growth
		_stem(point, leaf_root, 0.008 * leaf_growth)
		_leaf(leaf_root, angle, (0.24 + 0.15 * sin(float(index) / 8.0 * PI)) * growth * leaf_growth)
	head.position = top + Vector3.UP * 0.025
	bud.position = head.position
	head.scale = Vector3.ONE * maxf(0.001, clampf((progress - 0.68) / 0.20, 0.0, 1.0))

func _watermelon(crop: CropData, progress: float) -> void:
	if progress >= 0.06:
		_stem(Vector3.ZERO, Vector3.UP * 0.075, 0.009)
		_leaf(Vector3.UP * 0.075, 0.0, 0.12)
		_leaf(Vector3.UP * 0.075, PI, 0.12)
	for index in range(paths.size()):
		var path := paths[index]
		var extent := CropSpecies.path_growth(index, progress) * (path.size() - 1)
		for segment in range(1, ceili(extent) + 1):
			var fraction := minf(1.0, extent - segment + 1.0)
			var start := path[segment - 1]
			var end := start.lerp(path[segment], fraction)
			_stem(start, end, 0.011)
			if detailed or segment % 2 == 0:
				var direction := path[segment] - start
				var angle := atan2(direction.z, direction.x) + (1.0 if segment % 2 == 0 else -1.0) * 1.05
				var petiole := end + Vector3(cos(angle), 0.06, sin(angle)) * 0.12 * fraction
				_stem(end, petiole, 0.006 * fraction)
				_leaf(petiole, angle, (0.36 if index < 4 else 0.28) * fraction)
	for index in range(4):
		var growth := CropSpecies.fruit_progress(index, progress)
		var present := not crop.harvested_fruits.has(index)
		fruits[index].visible = present and growth > 0.0
		flowers[index].visible = present and growth <= 0.0 and progress >= 0.47 + index * 0.035
		flowers[index].position = fruit_ground[index] + Vector3.UP * 0.045
		if fruits[index].visible:
			var radius := lerpf(0.025, 0.21, growth)
			fruits[index].position = fruit_ground[index] + Vector3.UP * radius * 0.84
			fruits[index].scale = Vector3.ONE * radius
			_stem(paths[index][7 + index % 3], fruit_ground[index] + Vector3.UP * 0.045, 0.007)

# Buds follow the daylight arc, then return east overnight. Open flowers
# progressively stop tracking; the mature face points east at a modest elevation.
static func heading(day: float, progress: float) -> Vector3:
	day = wrapf(day, 0.0, 1.0)
	var angle: float
	if day >= 0.25 and day <= 0.75:
		angle = (day - 0.25) * TAU
	else:
		var night := wrapf(day - 0.75, 0.0, 1.0) * 2.0
		angle = PI * (1.0 - smoothstep(0.0, 1.0, night))
	var tracking := 1.0 - smoothstep(0.68, 0.88, progress)
	angle *= tracking
	return Vector3(0.0, 0.42 + sin(angle) * 0.55, cos(angle)).normalized()

func pose(day: float, progress: float, east_frame: Basis) -> void:
	if is_melon or progress < 0.55:
		return
	var direction := east_frame * heading(day, progress)
	# Reusable flower was built with a diagonal +Z normal.
	var tip := _neck + direction * _neck_length
	var neck_basis := Basis(Quaternion(Vector3.UP, direction)).scaled(Vector3(0.022, _neck_length, 0.022))
	stems.set_instance_transform(1, Transform3D(neck_basis, (_neck + tip) * 0.5))
	head.position = tip + direction * 0.025
	bud.position = head.position
	var original := Vector3(0.0, 0.69, 0.72).normalized()
	var rotation := Basis(Quaternion(original, direction))
	head.basis = rotation.scaled(head.scale)
	bud.basis = Basis(Quaternion(Vector3.UP, direction))
