extends Node3D

# Reproducible render of the same meshes used in-game.
@export var species: StringName = &"sunflower"

func _ready() -> void:
	GameManager.set_process(false)
	var args := OS.get_cmdline_user_args()
	if args.has("watermelon"):
		species = &"watermelon"
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.16, 0.21, 0.19)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.9, 0.95, 1.0)
	environment.ambient_light_energy = 0.45
	world.environment = environment
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 0.8
	light.shadow_enabled = true
	add_child(light)
	var floor_view := MeshInstance3D.new()
	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(30, 30)
	floor_view.mesh = floor_mesh
	floor_view.position = Vector3(4, -0.02, 4)
	var soil := StandardMaterial3D.new()
	soil.albedo_color = Color(0.29, 0.22, 0.15)
	soil.roughness = 1.0
	floor_view.material_override = soil
	add_child(floor_view)
	var stages: Array[float] = [0.10, 0.35, 0.65, 1.0]
	for index in range(stages.size()):
		var crop := CropData.new()
		crop.crop_type = species
		crop.shape_seed = 42 + index * 17
		var view := Node3D.new()
		if species == &"watermelon":
			view.position = Vector3((index % 2) * 8.0, 0, floori(float(index) / 2.0) * 8.0)
		else:
			view.position = Vector3(index * 1.8, 0, 0)
		add_child(view)
		var rig := CropVisualRig.new()
		rig.initialize(view, crop, true, func(_point: Vector3): return 0.0)
		rig.update(crop, stages[index])
		rig.pose(0.65, stages[index], Basis.IDENTITY)
		var label := Label3D.new()
		label.text = "%d%%" % int(stages[index] * 100)
		label.font_size = 48
		label.pixel_size = 0.008 if species == &"watermelon" else 0.003
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position = view.position + Vector3(0, 0.2, 2.8 if species == &"watermelon" else 0.5)
		add_child(label)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 16.0 if species == &"watermelon" else 4.7
	camera.position = Vector3(13, 17, 20) if species == &"watermelon" else Vector3(4.0, 3.4, 9.5)
	add_child(camera)
	camera.look_at(Vector3(4.0, 0, 4.0) if species == &"watermelon" else Vector3(2.7, 0.85, 0))
	camera.current = true
	if args.has("capture"):
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var destination := "res://Art/Crops/Review/%s.png" % species
		DirAccess.make_dir_recursive_absolute("res://Art/Crops/Review")
		var error := get_viewport().get_texture().get_image().save_png(destination)
		print("Crop render saved: ", destination, " (", error, ")")
		get_tree().quit(error)
