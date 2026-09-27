extends SceneTree
## Godot --path . --resolution 1152x648 --fixed-fps 60 --write-movie /tmp/jump_motion.avi --script Art/Characters/ForestGirl/capture_jump_motion.gd
## Uses the real player/controller on an isolated stage, without loading a save.
const STEP := 1.0 / 60.0
const OUTPUT := "res://Art/Characters/ForestGirl/Review/"
var player: CharacterBody3D
var tree: AnimationTree
var camera: Camera3D
var label: Label

func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("capture")

func capture() -> void:
	root.size = Vector2i(1152, 648)
	root.msaa_3d = Viewport.MSAA_4X
	root.get_node("GameManager").start_new_game()
	GameInput.ensure_default_bindings()
	var stage := Node3D.new()
	root.add_child(stage)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("dedbcc")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff5df")
	environment.ambient_light_energy = 0.55
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -30, 0)
	light.light_energy = 1.1
	light.shadow_enabled = true
	stage.add_child(light)
	var floor_body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 1, 200)
	shape.shape = box
	floor_body.add_child(shape)
	floor_body.position.y = -0.5
	stage.add_child(floor_body)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("9f9d8e")
	ground.material_override = material
	stage.add_child(ground)
	# Meter markers make movement during landing visible in the tracking view.
	var marker_material := StandardMaterial3D.new()
	marker_material.albedo_color = Color("858676")
	for z in range(-80, 81):
		var marker := MeshInstance3D.new()
		var strip := BoxMesh.new()
		strip.size = Vector3(200, .002, .018)
		marker.mesh = strip
		marker.position = Vector3(0, .002, z)
		marker.material_override = marker_material
		stage.add_child(marker)
	player = load("res://Scenes/Actors/Player.tscn").instantiate()
	stage.add_child(player)
	player.rotation.y = PI
	player.set_physics_process(false)
	player.set_process_input(false)
	player.set_process_unhandled_input(false)
	tree = player.Anim_tree
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 3.2
	camera.current = true
	stage.add_child(camera)
	var layer := CanvasLayer.new()
	stage.add_child(layer)
	label = Label.new()
	label.position = Vector2(24, 20)
	label.add_theme_font_size_override("font_size", 22)
	label.add_theme_color_override("font_color", Color("343830"))
	layer.add_child(label)
	await process_frame
	var repeated := false
	for frame in 600:
		if frame == 75 or frame == 230 or frame == 420:
			Input.action_press("ui_accept")
		if frame == 76 or frame == 231 or frame == 421:
			Input.action_release("ui_accept")
		if frame == 175 or frame == 370:
			Input.action_press("ui_down")
		if frame == 310 or frame == 530:
			Input.action_release("ui_down")
		if frame == 370:
			set_sprint(true)
		if frame == 530:
			set_sprint(false)
		var was_grounded := player.is_on_floor()
		player._physics_process(STEP)
		tree.advance(STEP)
		if frame > 420 and frame < 500 and not was_grounded and player.is_on_floor() and not repeated:
			Input.action_press("ui_accept")
			repeated = true
		elif repeated and not player.is_on_floor():
			Input.action_release("ui_accept")
		var phase := "STANDING HOP" if frame < 175 else ("MOVING HOP" if frame < 370 else "SPRINT + IMMEDIATE RE-JUMP")
		label.text = "%s\nState: %s" % [phase, tree.get("parameters/movement/current_state")]
		var target := Vector3(player.position.x, .95, player.position.z)
		camera.position = target + Vector3(3.5, 1.2, 4.0)
		camera.look_at(target)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame in [78, 91, 110, 234, 246, 268]:
			root.get_texture().get_image().save_png(OUTPUT+"motion_%03d.png" % frame)
	Input.action_release("ui_down")
	Input.action_release("ui_accept")
	set_sprint(false)
	for tool in player._tool_inventory._tools:
		tool.free()
	player._tool_inventory._tools.clear()
	player._movement_controller = null
	player._interaction_controller = null
	stage.queue_free()
	await process_frame
	print("JUMP_MOTION_CAPTURE_OK")
	quit()

func set_sprint(pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_SHIFT
	event.physical_keycode = KEY_SHIFT
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()
