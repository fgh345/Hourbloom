extends Node3D
## Standalone art review; deliberately independent from gameplay and persistence.

const MODEL = preload("res://Assets/Characters/ForestGirl/forest_girl.glb")
const ANIMATIONS = ["Idle", "Walk", "freehand_run", "jump_start", "jump_move", "freehand_fall", "fall_move", "landing_soft", "landing_recoil", "pose_lean_left", "pose_lean_right"]
const ANIMATION_LABELS = ["待机", "行走", "奔跑", "原地起跳", "移动起跳", "原地下落", "移动下落", "原地落地", "移动落地缓冲", "左倾", "右倾"]

var _camera: Camera3D
var _animator: AnimationPlayer
var _angle: float = atan2(3.0, 6.0)
var _dragging := false

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	get_viewport().msaa_3d = Viewport.MSAA_4X
	get_viewport().use_taa = true
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e5dfd1")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("fff3df")
	environment.ambient_light_energy = 0.32
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var world := WorldEnvironment.new()
	world.environment = environment
	add_child(world)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12.0, 12.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("96938b")
	material.roughness = 0.95
	ground.material_override = material
	add_child(ground)
	_add_light(Vector3(3.0, 5.0, 4.0), Color("fff7ea"), 0.65, true)
	_add_light(Vector3(-4.0, 3.0, 2.0), Color("e7edff"), 0.20, false)
	_add_light(Vector3(1.0, 4.0, -4.0), Color("fff8ec"), 0.25, false)
	var character := MODEL.instantiate()
	add_child(character)
	_animator = character.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_animator.play(ANIMATIONS[0])
	_camera = Camera3D.new()
	_camera.current = true
	_camera.fov = 30.0
	_camera.near = 0.03
	add_child(_camera)
	_update_camera()
	_build_ui()

func _add_light(position_value: Vector3, color: Color, energy: float, shadows: bool) -> void:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.shadow_enabled = shadows
	light.light_angular_distance = 2.0
	light.directional_shadow_max_distance = 5.0
	light.shadow_bias = 0.3
	light.shadow_normal_bias = 2.0
	add_child(light)
	light.position = position_value
	light.look_at(Vector3(0.0, 1.0, 0.0))

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24.0, 24.0)
	layer.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	var title := Label.new()
	title.text = "森林女孩 · 角色预览"
	title.add_theme_font_size_override("font_size", 22)
	content.add_child(title)
	_add_select(content, "动作", ANIMATION_LABELS, _select_animation)
	var views := HBoxContainer.new()
	content.add_child(views)
	var angles := [0.0, PI / 4.0, PI / 2.0, PI]
	var labels := ["正面", "45°", "侧面", "背面"]
	for index in labels.size():
		var button := Button.new()
		button.text = labels[index]
		button.pressed.connect(_set_angle.bind(angles[index]))
		views.add_child(button)
	var turn := HBoxContainer.new()
	content.add_child(turn)
	for direction in [-1.0, 1.0]:
		var button := Button.new()
		button.text = "向左转" if direction < 0.0 else "向右转"
		button.pressed.connect(_turn.bind(direction * PI / 12.0))
		turn.add_child(button)
	var hint := Label.new()
	hint.text = "拖动空白区域旋转视角"
	content.add_child(hint)

func _add_select(parent: Node, text: String, labels: Array, callback: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Label.new()
	label.text = text
	row.add_child(label)
	var select := OptionButton.new()
	select.custom_minimum_size.x = 180.0
	for item in labels:
		select.add_item(item)
	select.item_selected.connect(callback)
	row.add_child(select)

func _select_animation(index: int) -> void:
	_animator.play(ANIMATIONS[index], 0.2)

func _set_angle(value: float) -> void:
	_angle = value
	_update_camera()

func _turn(delta: float) -> void:
	_set_angle(_angle + delta)

func _update_camera() -> void:
	_camera.position = Vector3(sin(_angle) * 3.6, 1.25, cos(_angle) * 3.6)
	_camera.look_at(Vector3(0.0, 0.6, 0.0))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_turn(-event.relative.x * 0.008)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_dragging = false
