extends Node
## Atlas expressions use one local material per character, never shared resource mutation.

@export_range(1.0, 10.0, 0.1) var blink_interval_min: float = 2.5
@export_range(1.0, 10.0, 0.1) var blink_interval_max: float = 5.5
@export_range(0.08, 0.4, 0.01) var blink_duration: float = 0.16

const EXPRESSIONS = [&"Neutral", &"Happy", &"Surprised", &"Angry", &"Sad", &"Blink", &"Sleepy", &"Thinking"]
const FACE_SHADER = preload("res://Scripts/player/character_face.gdshader")
var _random := RandomNumberGenerator.new()
var _face_material: ShaderMaterial
var _expression: StringName = &"Neutral"
var _blink_wait: float = 0.0
var _blink_elapsed: float = -1.0

func _ready() -> void:
	_random.randomize()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(get_parent(), meshes)
	for candidate in meshes:
		if candidate.mesh == null or candidate.mesh.get_surface_count() == 0:
			continue
		var source := candidate.get_active_material(0) as StandardMaterial3D
		if source == null or source.albedo_texture == null:
			continue
		if _face_material == null:
			_face_material = ShaderMaterial.new()
			_face_material.shader = FACE_SHADER
			_face_material.set_shader_parameter("base_color", source.albedo_texture)
			_face_material.set_shader_parameter("tint", source.albedo_color)
		candidate.material_override = _face_material
		if String(candidate.name) in ["CHR_Eyes", "CHR_Mouth"]:
			candidate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_schedule_blink()
	_apply_expression(false)
	set_process(_face_material != null)

func _collect_meshes(node: Node, meshes: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and String(node.name).begins_with("CHR_"):
		meshes.append(node)
	for child in node.get_children():
		_collect_meshes(child, meshes)

func set_expression(expression_name: StringName) -> void:
	if expression_name in EXPRESSIONS:
		_expression = expression_name
		_apply_expression(false)

func _apply_expression(blink: bool) -> void:
	if _face_material == null:
		return
	_face_material.set_shader_parameter("face_row", EXPRESSIONS.find(_expression))
	_face_material.set_shader_parameter("blink", blink)

func _schedule_blink() -> void:
	_blink_wait = _random.randf_range(minf(blink_interval_min, blink_interval_max), maxf(blink_interval_min, blink_interval_max))

func _process(delta: float) -> void:
	if _face_material == null:
		return
	if _blink_elapsed < 0.0:
		_blink_wait -= delta
		if _blink_wait <= 0.0:
			_blink_elapsed = 0.0
	else:
		_blink_elapsed += delta
		if _blink_elapsed >= blink_duration:
			_blink_elapsed = -1.0
			_schedule_blink()
	_apply_expression(_blink_elapsed >= 0.0 and _expression not in [&"Happy", &"Blink", &"Sleepy"])
