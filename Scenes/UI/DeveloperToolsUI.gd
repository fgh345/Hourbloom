extends VBoxContainer

@onready var rate_spinbox: SpinBox = %TimeRateSpinBox
@onready var summary_label: Label = %TimeRateSummary
@onready var status_label: Label = %TimeRateStatus
@onready var character_select: OptionButton = %CharacterSelect
@onready var character_status: Label = %CharacterStatus

func _ready() -> void:
	character_select.add_item("女角色")
	character_select.add_item("男角色")
	character_select.item_selected.connect(_on_character_selected)
	rate_spinbox.min_value = DeveloperSettings.MIN_MINUTES_PER_SECOND
	rate_spinbox.max_value = DeveloperSettings.MAX_MINUTES_PER_SECOND
	rate_spinbox.value_changed.connect(_on_rate_changed)
	%DefaultTimeRateButton.pressed.connect(func(): rate_spinbox.value = DeveloperSettings.DEFAULT_MINUTES_PER_SECOND)
	for rate: int in [1, 10, 30, 60]:
		get_node("Presets/Rate%dButton" % rate).pressed.connect(func(): rate_spinbox.value = float(rate))
	refresh()

func refresh() -> void:
	character_select.select(0 if GameManager.developer_settings.character_id == "female" else 1)
	character_status.text = "切换后立即生效，自动记住上次选择。"
	character_status.modulate = Color.WHITE
	rate_spinbox.set_value_no_signal(GameManager.developer_settings.minutes_per_second)
	_update_summary(rate_spinbox.value)
	status_label.text = "修改后立即生效，自动记住上次设置。"
	status_label.modulate = Color.WHITE

func _on_character_selected(index: int) -> void:
	var character_id := "female" if index == 0 else "male"
	var error := GameManager.set_character_id(character_id)
	if error == OK:
		character_status.text = "已切换并保存，下次启动自动恢复。"
		character_status.modulate = Color(0.65, 0.9, 0.65)
	elif error == ERR_CANT_CREATE:
		character_select.select(0 if GameManager.developer_settings.character_id == "female" else 1)
		character_status.text = "角色切换失败，请检查游戏日志。"
		character_status.modulate = Color(1.0, 0.55, 0.45)
	else:
		character_status.text = "已切换，但保存失败；下次启动可能需要重新设置。"
		character_status.modulate = Color(1.0, 0.55, 0.45)

func _on_rate_changed(rate: float) -> void:
	var error := GameManager.set_time_minutes_per_second(rate)
	_update_summary(GameManager.developer_settings.minutes_per_second)
	if error == OK:
		status_label.text = "已应用并保存，下次启动自动恢复。"
		status_label.modulate = Color(0.65, 0.9, 0.65)
	else:
		status_label.text = "已应用，但保存失败；下次启动可能需要重新设置。"
		status_label.modulate = Color(1.0, 0.55, 0.45)

func _update_summary(rate: float) -> void:
	summary_label.text = "一个游戏日约现实 %s 秒（%s 分钟）" % [String.num(1440.0 / rate, 1), String.num(24.0 / rate, 2)]
