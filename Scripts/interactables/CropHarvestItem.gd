extends InteractableItem3D

@export var species: StringName = &"watermelon"

func _ready() -> void:
	super._ready()
	var builder := CropVisualBuilder.new()
	if species == &"watermelon":
		builder._melon(Vector3.ZERO, 0.21, true)
	else:
		# A small seed sack for the harvested sunflower seeds.
		builder._ellipsoid(Vector3.ZERO, Vector3(0.10, 0.13, 0.08), "sack", Color(0.67, 0.49, 0.28))
		builder._stem(Vector3(-0.075, 0.10, 0), Vector3(0.075, 0.10, 0), 0.012, "tie", Color(0.33, 0.24, 0.12))
	var mesh := ArrayMesh.new()
	for key: String in builder._surfaces:
		var surface: SurfaceTool = builder._surfaces[key]
		surface.generate_normals()
		surface.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, builder._materials[key])
	var view := MeshInstance3D.new()
	view.mesh = mesh
	add_child(view)
