extends PanelContainer

@onready var help_text: Label = %HelpText

func _ready() -> void:
	hide()
	_refresh_controls_text()

func _input(event: InputEvent) -> void:
	if GameInput.is_help_toggle_event(event):
		visible = not visible
		get_viewport().set_input_as_handled()

func _refresh_controls_text() -> void:
	var interact := GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)
	var help_toggle := GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_HELP)
	var ui_toggle := GameInput.get_action_binding_text(GameInput.ACTION_TOGGLE_UI)
	var camera_up := GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_UP)
	var camera_down := GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_DOWN)
	var zoom_in := GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_ZOOM_IN)
	var zoom_out := GameInput.get_action_binding_text(GameInput.ACTION_CAMERA_ZOOM_OUT)

	var rows: Array[String] = [
		"操作说明",
		"",
		"移动",
		"WASD        移动",
		"Shift       奔跑",
		"Space       跳跃",
		"",
		"工具",
		"1           装备锄头",
		"2           向日葵种子",
		"3           采收（西瓜逐个摘取）",
		"4           西瓜种子",
		"左键        使用工具",
		"%s           交互" % interact,
		"",
		"镜头",
		"%s / %s   上移 / 下移" % [camera_up, camera_down],
		"%s / %s   拉近 / 拉远" % [zoom_in, zoom_out],
		"",
		"%s          显示/隐藏帮助" % help_toggle,
		"%s          显示/隐藏界面" % ui_toggle
	]

	help_text.text = "\n".join(rows)
