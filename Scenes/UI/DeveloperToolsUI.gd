extends VBoxContainer

@onready var rate_spinbox: SpinBox = %TimeRateSpinBox
@onready var summary_label: Label = %TimeRateSummary
@onready var status_label: Label = %TimeRateStatus

func _ready() -> void:
	rate_spinbox.min_value = DeveloperSettings.MIN_MINUTES_PER_SECOND
	rate_spinbox.max_value = DeveloperSettings.MAX_MINUTES_PER_SECOND
	rate_spinbox.value_changed.connect(_on_rate_changed)
	%DefaultTimeRateButton.pressed.connect(func(): rate_spinbox.value = DeveloperSettings.DEFAULT_MINUTES_PER_SECOND)
	for rate: int in [1, 10, 30, 60]:
		get_node("Presets/Rate%dButton" % rate).pressed.connect(func(): rate_spinbox.value = float(rate))
	refresh()

func refresh() -> void:
	rate_spinbox.set_value_no_signal(GameManager.developer_settings.minutes_per_second)
	_update_summary(rate_spinbox.value)
	status_label.text = "修改后立即生效，自动记住上次设置。"
	status_label.modulate = Color.WHITE

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
