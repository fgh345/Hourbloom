extends SceneTree
## Captures the actual Player controller and in-memory farm, without loading saves.
const Motion = preload("res://Assets/Tools/Hoe/HoeMotion.gd")
const OUTPUT := "res://Art/Tools/Hoe/Review/hoe_gameplay.png"
const STEP := 1.0 / 60.0
var player: CharacterBody3D
var world: Node3D

func _initialize() -> void:
	root.size = Vector2i(1152, 648)
	Engine.physics_ticks_per_second = 60
	call_deferred("capture")

func material(color: Color) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 1.0
	return result

func capture() -> void:
	root.get_node("GameManager").start_new_game()
	GameInput.ensure_default_bindings()
	world = Node3D.new()
	root.add_child(world)
	var ground := StaticBody3D.new()
	ground.add_to_group("farmland_ground")
	world.add_child(ground)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	shape.position.y = -.5
	ground.add_child(shape)
	var plane := MeshInstance3D.new()
	var plane_mesh := PlaneMesh.new()
	plane_mesh.size = Vector2(200, 200)
	plane.mesh = plane_mesh
	plane.material_override = material(Color("889775"))
	ground.add_child(plane)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("c9d6dc")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = .7
	world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -35, 0)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	world.add_child(sun)
	player = load("res://Scenes/Actors/Player.tscn").instantiate()
	world.add_child(player)
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	player.Anim_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	var camera := Camera3D.new()
	world.add_child(camera)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.9
	camera.position = Vector3(-2.8, 2.1, -3.5)
	camera.look_at(Vector3(0, .55, -.25))
	camera.make_current()
	var canvas := CanvasLayer.new()
	world.add_child(canvas)
	var label := Label.new()
	label.position = Vector2(28, 24)
	label.add_theme_color_override("font_color", Color("243022"))
	label.add_theme_font_size_override("font_size", 25)
	canvas.add_child(label)
	root.get_node("GameManager").session.farm.tile_updated.connect(func(tile: Vector2i, _state: int):
		var soil := MeshInstance3D.new()
		var patch := PlaneMesh.new()
		patch.size = Vector2(.95, .95)
		soil.mesh = patch
		soil.material_override = material(Color("735139"))
		soil.position = Vector3(tile.x, .006, tile.y)
		world.add_child(soil))
	var second_swing := 50 + ceili(Motion.DURATION * 60) + 35
	var walk_frame := second_swing + ceili(Motion.DURATION * 60) + 20
	for frame in walk_frame + 165:
		if frame == second_swing - 10:
			player.rotation.y = -PI / 2
		if frame == 50 or frame == second_swing:
			var tool: Tool = player._tool_inventory.get_active_tool()
			player._interaction_controller.try_use_tool(player, tool)
		if frame == walk_frame:
			Input.action_press("ui_up")
		if frame == walk_frame + 10:
			Input.action_press("ui_accept")
		if frame == walk_frame + 11:
			Input.action_release("ui_accept")
		if frame == walk_frame + 20:
			Input.action_release("ui_up")
		label.text = "实际玩家 · 锄头已接入\n" + ("挥锄触地 → 翻耕" if player.is_hoe_action_active() else "移动 / 跳跃 / 待机")
		await physics_frame
		player._physics_process(STEP)
		player.Anim_tree.advance(STEP)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame == 50 + ceili(Motion.IMPACT_TIME * 60):
			root.get_texture().get_image().save_png(OUTPUT)
	for tool in player._tool_inventory._tools:
		tool.free()
	player._tool_inventory._tools.clear()
	world.queue_free()
	await process_frame
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("HOE_GAMEPLAY_CAPTURE_OK")
	quit()
