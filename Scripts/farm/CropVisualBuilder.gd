class_name CropVisualBuilder
extends RefCounted

# One combined mesh per material, rather than a node/draw call per leaf.
var _surfaces: Dictionary = {}
var _materials: Dictionary = {}
var ground_height: Callable

func build(crop: CropData, progress: float, detailed: bool = true) -> ArrayMesh:
	_surfaces.clear()
	_materials.clear()
	_mound()
	if progress >= 0.06:
		if crop.crop_type == &"watermelon":
			_watermelon(crop, progress, detailed)
		else:
			_sunflower(crop, progress, detailed)
	var result := ArrayMesh.new()
	for key: String in _surfaces:
		var surface: SurfaceTool = _surfaces[key]
		surface.generate_normals()
		surface.commit(result)
		result.surface_set_material(result.get_surface_count() - 1, _materials[key])
	return result

func _surface(key: String, color: Color) -> SurfaceTool:
	if not _surfaces.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_surfaces[key] = surface
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		_materials[key] = material
	return _surfaces[key]

func _primitive(mesh: PrimitiveMesh, center: Vector3, size: Vector3, key: String, color: Color, basis: Basis = Basis.IDENTITY) -> void:
	_surface(key, color).append_from(mesh, 0, Transform3D(basis.scaled(size), center))

func _ellipsoid(center: Vector3, size: Vector3, key: String, color: Color) -> void:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	_primitive(mesh, center, size, key, color)

func _stem(start: Vector3, end: Vector3, radius: float, key: String = "stem", color: Color = Color(0.27, 0.43, 0.12)) -> void:
	var difference := end - start
	if difference.length() < 0.001:
		return
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.78
	mesh.bottom_radius = radius
	mesh.height = difference.length()
	mesh.radial_segments = 6
	var basis := Basis(Quaternion(Vector3.UP, difference.normalized()))
	_primitive(mesh, (start + end) * 0.5, Vector3.ONE, key, color, basis)

func _triangle(key: String, color: Color, a: Vector3, b: Vector3, c: Vector3) -> void:
	var surface := _surface(key, color)
	surface.add_vertex(a)
	surface.add_vertex(b)
	surface.add_vertex(c)

# Folded broad sunflower leaves or five-lobed watermelon leaves.
func _leaf(root: Vector3, angle: float, length: float, lobed: bool = false) -> void:
	var forward := Vector3(cos(angle), 0.0, sin(angle))
	var sideways := Vector3(-forward.z, 0.0, forward.x)
	var outline: Array[Vector2] = []
	if lobed:
		outline = [Vector2(0, 0), Vector2(0.22, -0.22), Vector2(0.34, -0.46), Vector2(0.46, -0.21), Vector2(0.62, -0.42), Vector2(0.66, -0.15), Vector2(1.0, 0), Vector2(0.66, 0.15), Vector2(0.62, 0.42), Vector2(0.46, 0.21), Vector2(0.34, 0.46), Vector2(0.22, 0.22)]
	else:
		outline = [Vector2(0, 0), Vector2(0.18, -0.25), Vector2(0.46, -0.38), Vector2(0.73, -0.25), Vector2(1, 0), Vector2(0.73, 0.25), Vector2(0.46, 0.38), Vector2(0.18, 0.25)]
	var ridge := root + forward * length * 0.48 + Vector3.UP * length * 0.12
	for index in range(outline.size()):
		var left := outline[index]
		var right := outline[(index + 1) % outline.size()]
		var a := root + (forward * left.x + sideways * left.y) * length
		var b := root + (forward * right.x + sideways * right.y) * length
		_triangle("leaf_light" if left.y <= 0 else "leaf_dark", Color(0.32, 0.53, 0.14) if left.y <= 0 else Color(0.22, 0.39, 0.10), ridge, a, b)
	_stem(root, root + forward * length * 0.85 + Vector3.UP * length * 0.035, 0.006, "vein", Color(0.45, 0.61, 0.21))

func _mound() -> void:
	_ellipsoid(Vector3(0, 0.018, 0), Vector3(0.13, 0.025, 0.11), "soil", Color(0.30, 0.18, 0.09))

func _sunflower(crop: CropData, progress: float, detailed: bool) -> void:
	var growth := clampf((progress - 0.06) / 0.68, 0.0, 1.0)
	var height := lerpf(0.07, 1.65, growth)
	var angle := float(posmod(crop.shape_seed, 628)) / 100.0
	var top := Vector3(0.05 * growth, height, 0.025 * growth)
	_stem(Vector3.ZERO, top, lerpf(0.009, 0.026, growth))
	_leaf(Vector3(0, height * 0.22, 0), angle, 0.09 + 0.05 * growth)
	_leaf(Vector3(0, height * 0.22, 0), angle + PI, 0.09 + 0.05 * growth)
	var count := mini(8 if detailed else 4, int(growth * 9.0))
	for index in range(count):
		var root := top * (0.20 + index * 0.60 / maxi(1, count - 1))
		var leaf_angle := angle + index * 2.39996
		var leaf_size := (0.24 + 0.15 * sin(float(index) / 8.0 * PI)) * growth
		var leaf_root := root + Vector3(cos(leaf_angle), 0.28, sin(leaf_angle)) * 0.08
		_stem(root, leaf_root, 0.008)
		_leaf(leaf_root, leaf_angle, leaf_size)
	if progress < 0.55:
		return
	var bloom := clampf((progress - 0.68) / 0.20, 0.0, 1.0)
	var center := top + Vector3(0, 0.025, 0)
	if bloom <= 0.0:
		_ellipsoid(center, Vector3(0.065, 0.09, 0.065), "bud", Color(0.36, 0.48, 0.12))
		return
	# Flower faces diagonally upwards and remains legible from third-person view.
	var normal := Vector3(cos(angle) * 0.72, 0.69, sin(angle) * 0.72).normalized()
	var x_axis := Vector3(-sin(angle), 0, cos(angle))
	var y_axis := normal.cross(x_axis).normalized()
	var disc_radius := 0.13 * bloom
	var disc := SphereMesh.new()
	disc.radius = 1.0
	disc.height = 2.0
	disc.radial_segments = 24
	disc.rings = 6
	_primitive(disc, center, Vector3(disc_radius, disc_radius, 0.045 * bloom), "disc", Color(0.25, 0.14, 0.055), Basis(x_axis, y_axis, normal))
	for ring in range(2):
		var petals := 18 if ring == 0 else 16
		for index in range(petals):
			var theta := TAU * (index + ring * 0.5) / petals
			var outward := x_axis * cos(theta) + y_axis * sin(theta)
			var lateral := -x_axis * sin(theta) + y_axis * cos(theta)
			var root := center + outward * disc_radius * 0.75 + normal * (0.02 + ring * 0.008)
			var length := (0.19 if ring == 0 else 0.145) * bloom
			var mid := root + outward * length * 0.52 + normal * 0.025
			var tip := root + outward * length - normal * 0.02
			var width := length * 0.20
			_triangle("petal", Color(1.0, 0.66, 0.045), root, mid - lateral * width, tip)
			_triangle("petal_light", Color(1.0, 0.81, 0.13), root, tip, mid + lateral * width)
	if detailed:
		for index in range(32):
			var theta := index * 2.39996
			var radius := sqrt(float(index) / 32.0) * disc_radius * 0.85
			var point := center + x_axis * cos(theta) * radius + y_axis * sin(theta) * radius + normal * (0.047 * bloom)
			_ellipsoid(point, Vector3.ONE * 0.009, "seed", Color(0.39, 0.25, 0.10))

func _ground(point: Vector3) -> Vector3:
	var height := float(ground_height.call(point)) if ground_height.is_valid() else 0.0
	return Vector3(point.x, height + 0.025, point.z)

func _watermelon(crop: CropData, progress: float, detailed: bool) -> void:
	_stem(Vector3.ZERO, Vector3(0, 0.075, 0), 0.009)
	_leaf(Vector3(0, 0.075, 0), 0.0, 0.12)
	_leaf(Vector3(0, 0.075, 0), PI, 0.12)
	var paths := crop.vine_paths()
	for index in range(paths.size()):
		var path := paths[index]
		var extent := CropSpecies.path_growth(index, progress) * (path.size() - 1)
		if extent <= 0.0:
			continue
		for segment in range(1, ceili(extent) + 1):
			var start := _ground(path[segment - 1])
			var end := _ground(path[segment - 1].lerp(path[segment], minf(1.0, extent - segment + 1.0)))
			_stem(start, end, 0.011)
			if segment <= floori(extent) and (detailed or segment % 2 == 0):
				var direction := path[segment] - path[segment - 1]
				var angle := atan2(direction.z, direction.x) + (1.0 if segment % 2 == 0 else -1.0) * 1.05
				var petiole := end + Vector3(cos(angle), 0.06, sin(angle)) * 0.12
				_stem(end, petiole, 0.006)
				_leaf(petiole, angle, 0.36 if index < 4 else 0.28, true)
	for index in range(CropSpecies.FRUIT_COUNT):
		if crop.harvested_fruits.has(index):
			continue
		var growth := CropSpecies.fruit_progress(index, progress)
		var offset := CropSpecies.fruit_offset(paths, index)
		var ground := _ground(offset)
		if growth <= 0.0:
			if progress >= 0.47 + index * 0.035:
				_flower(ground + Vector3.UP * 0.045)
			continue
		var radius := lerpf(0.025, 0.21, growth)
		var center := ground + Vector3.UP * radius * 0.84
		_melon(center, radius, detailed)
		_stem(_ground(paths[index][7 + index % 3]), ground + Vector3.UP * 0.045, 0.007)

func _flower(center: Vector3) -> void:
	for index in range(5):
		var angle := TAU * index / 5.0
		var direction := Vector3(cos(angle), 0, sin(angle))
		var side := Vector3(-direction.z, 0, direction.x) * 0.018
		_triangle("flower", Color(1.0, 0.79, 0.12), center, center + direction * 0.05 - side, center + direction * 0.05 + side)

# Stripes are actual coloured mesh sectors, with no external texture dependency.
func _melon(center: Vector3, radius: float, detailed: bool) -> void:
	var segments := 24 if detailed else 12
	var rings := 8 if detailed else 4
	for ring in range(rings):
		for segment in range(segments):
			var a := _melon_vertex(center, radius, float(ring) / rings, float(segment) / segments)
			var b := _melon_vertex(center, radius, float(ring + 1) / rings, float(segment) / segments)
			var c := _melon_vertex(center, radius, float(ring + 1) / rings, float(segment + 1) / segments)
			var d := _melon_vertex(center, radius, float(ring) / rings, float(segment + 1) / segments)
			var stripe := segment % (segments / 6) == 0
			var key := "melon_stripe" if stripe else "melon_skin"
			var color := Color(0.10, 0.27, 0.085) if stripe else Color(0.38, 0.57, 0.14)
			_triangle(key, color, a, b, c)
			_triangle(key, color, a, c, d)

func _melon_vertex(center: Vector3, radius: float, latitude: float, longitude: float) -> Vector3:
	var theta := latitude * PI
	var phi := longitude * TAU + 0.035 * sin(theta * 5.0)
	return center + Vector3(sin(theta) * cos(phi) * 1.2, cos(theta) * 0.84, sin(theta) * sin(phi)) * radius
