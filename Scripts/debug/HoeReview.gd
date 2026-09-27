extends Node3D
## Standalone art review. No player, farming services or save data are changed.
const Motion = preload("res://Assets/Tools/Hoe/HoeMotion.gd")
const MODEL_PATH := "res://Assets/Tools/Hoe/character_with_hoe.glb"
var animator: AnimationPlayer
var camera: Camera3D
var phase_label: Label
var scrubber: HSlider
var playing := true
var elapsed := 0.0
var clip_length := Motion.DURATION
var impact_time := Motion.IMPACT_TIME
var impact_position := Motion.CONTACT_LOCAL + Vector3.UP * .02
var angle := 0.70
var particles: Array[MeshInstance3D] = []
var particle_age := 10.0
var capture_mode := false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("e9e2d5")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("fff5e3")
	env.ambient_light_energy = .55
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)
	for setting in [[Vector3(-38, -30, 0), 1.0], [Vector3(-25, 135, 0), .35]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = setting[0]
		light.light_energy = setting[1]
		light.shadow_enabled = setting[1] == 1.0
		add_child(light)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200, 200)
	ground.mesh = plane
	ground.material_override = material("b8b39d")
	add_child(ground)
	var bed := MeshInstance3D.new()
	var bed_mesh := CylinderMesh.new()
	bed_mesh.top_radius = .39
	bed_mesh.bottom_radius = .41
	bed_mesh.height = .016
	bed_mesh.radial_segments = 12
	bed.mesh = bed_mesh
	bed.material_override = material("806448")
	bed.position = Motion.CONTACT_LOCAL + Vector3.DOWN * .003
	add_child(bed)
	var model: Node3D = load(MODEL_PATH).instantiate()
	add_child(model)
	animator = model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	assert(animator != null and animator.has_animation("Hoe"), "Preview requires Hoe animation")
	animator.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	clip_length = animator.get_animation("Hoe").length
	animator.play("Hoe")
	animator.advance(0)
	camera = Camera3D.new()
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 2.05
	camera.near = .02
	add_child(camera)
	set_view(angle)
	for i in 12:
		var chunk := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3.ONE * (.014 + (i % 3) * .006)
		chunk.mesh = mesh
		chunk.material_override = material("99714d" if i % 2 else "624b37")
		chunk.visible = false
		particles.append(chunk)
		add_child(chunk)
	build_ui()

func material(hex: String) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = Color(hex)
	result.roughness = .88
	return result

func set_view(value: float) -> void:
	angle = value
	var target := Vector3(0, .63, .12)
	camera.position = target + Vector3(sin(angle) * 3.6, 1.05, cos(angle) * 3.6)
	camera.look_at(target)

func _process(delta: float) -> void:
	if not capture_mode:
		advance_preview(delta)

func advance_preview(delta: float) -> void:
	if not playing:
		return
	var previous := elapsed
	elapsed += delta
	var cycle := clip_length + .45
	if elapsed >= cycle:
		elapsed = fmod(elapsed, cycle)
		previous = 0
		animator.play("Hoe")
	animator.seek(minf(elapsed, clip_length), true)
	if previous < impact_time and elapsed >= impact_time:
		particle_age = 0
	particle_age += delta
	for i in particles.size():
		var chunk := particles[i]
		chunk.visible = particle_age < .48
		var theta := i * 2.39996
		var velocity := Vector3(cos(theta) * .32, .55 + (i % 4) * .12, sin(theta) * .30)
		chunk.position = impact_position + velocity * particle_age + Vector3.DOWN * 1.9 * particle_age * particle_age
		chunk.rotation = Vector3(i, i * .7, i * .3) + Vector3(3, 2, 4) * particle_age
		if chunk.position.y < .005:
			chunk.visible = false
	if scrubber != null:
		scrubber.set_value_no_signal(minf(elapsed, clip_length))
	if elapsed < Motion.READY_END:
		phase_label.text = "1 准备 · 低位握锄"
	elif elapsed < Motion.RAISED_END:
		phase_label.text = "2 蓄力 · 举锄后移"
	elif elapsed < impact_time:
		phase_label.text = "3 下挥 · 全身发力"
	elif elapsed < Motion.CONTACT_END:
		phase_label.text = "4 触地 · 屈膝下压"
	elif elapsed < clip_length:
		phase_label.text = "5 收回 · 拔锄收手"
	else:
		phase_label.text = "动作结束"


func build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(28, 24)
	box.add_theme_constant_override("separation", 10)
	layer.add_child(box)
	var title := Label.new()
	title.text = "森林农具 / 01 锄头"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("343d30"))
	box.add_child(title)
	phase_label = Label.new()
	phase_label.add_theme_color_override("font_color", Color("5c654f"))
	box.add_child(phase_label)
	var controls := HBoxContainer.new()
	box.add_child(controls)
	for view in [["正面", 0.0], ["45°", .70], ["侧面", PI / 2]]:
		var button := Button.new()
		button.text = view[0]
		button.pressed.connect(set_view.bind(view[1]))
		controls.add_child(button)
	var pause := Button.new()
	pause.text = "暂停 / 继续"
	pause.pressed.connect(func(): playing = not playing)
	controls.add_child(pause)
	var speed := Button.new()
	speed.text = "慢放 / 常速"
	speed.pressed.connect(func(): Engine.time_scale = .4 if Engine.time_scale == 1.0 else 1.0)
	controls.add_child(speed)
	scrubber = HSlider.new()
	scrubber.min_value = 0
	scrubber.max_value = clip_length
	scrubber.step = .001
	scrubber.custom_minimum_size.x = 320
	scrubber.value_changed.connect(func(value: float):
		playing = false
		elapsed = value
		animator.seek(value, true)
		for chunk in particles:
			chunk.visible = false
		phase_label.text = "逐帧查看 · %.2f 秒" % value
	)
	box.add_child(scrubber)

func _exit_tree() -> void:
	Engine.time_scale = 1.0
