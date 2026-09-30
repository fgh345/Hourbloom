extends VBoxContainer

@onready var rate_spinbox: SpinBox = %TimeRateSpinBox
@onready var summary_label: Label = %TimeRateSummary
@onready var status_label: Label = %TimeRateStatus
@onready var character_select: OptionButton = %CharacterSelect
@onready var character_status: Label = %CharacterStatus
@onready var perf_animation_toggle: CheckButton = %PerfAnimationToggle
@onready var perf_player_physics_toggle: CheckButton = %PerfPlayerPhysicsToggle
@onready var perf_grid_process_toggle: CheckButton = %PerfGridProcessToggle
@onready var perf_status: Label = %PerfStatus

func _ready() -> void:
	character_select.add_item("女角色")
	character_select.add_item("男角色")
	character_select.item_selected.connect(_on_character_selected)
	rate_spinbox.min_value = DeveloperSettings.MIN_MINUTES_PER_SECOND
	rate_spinbox.max_value = DeveloperSettings.MAX_MINUTES_PER_SECOND
	rate_spinbox.value_changed.connect(_on_rate_changed)
	%DefaultTimeRateButton.pressed.connect(func(): rate_spinbox.value = DeveloperSettings.DEFAULT_MINUTES_PER_SECOND)
	perf_animation_toggle.toggled.connect(_on_perf_animation_toggled)
	perf_player_physics_toggle.toggled.connect(_on_perf_player_physics_toggled)
	perf_grid_process_toggle.toggled.connect(_on_perf_grid_process_toggled)
	%PerfResetButton.pressed.connect(_reset_perf_isolation)
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
	_refresh_perf_controls()

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


func _get_player_node() -> Node:
	return get_tree().get_first_node_in_group("player")

func _get_player_animation_tree(player: Node) -> AnimationTree:
	if player == null:
		return null
	return player.get_node_or_null("CharacterVisual/AnimationTree") as AnimationTree

func _get_grid_manager() -> Node:
	return get_tree().get_first_node_in_group("grid_manager")

func _refresh_perf_controls() -> void:
	var player := _get_player_node()
	var animation_tree := _get_player_animation_tree(player)
	perf_animation_toggle.disabled = animation_tree == null
	perf_animation_toggle.set_pressed_no_signal(animation_tree.active if animation_tree != null else false)

	perf_player_physics_toggle.disabled = player == null
	perf_player_physics_toggle.set_pressed_no_signal(player.is_physics_processing() if player != null else false)

	var grid_manager := _get_grid_manager()
	perf_grid_process_toggle.disabled = grid_manager == null
	perf_grid_process_toggle.set_pressed_no_signal(grid_manager.is_processing() if grid_manager != null else false)

	if player == null or grid_manager == null:
		perf_status.text = "性能隔离对象尚未就绪；进入游戏后重新打开设置即可。"
	else:
		perf_status.text = "仅用于本次运行的 A/B 测试，不会保存。关闭一个项目后观察 FPS / CPU 变化。"
	perf_status.modulate = Color.WHITE

func _on_perf_animation_toggled(enabled: bool) -> void:
	var animation_tree := _get_player_animation_tree(_get_player_node())
	if animation_tree == null:
		_refresh_perf_controls()
		return
	animation_tree.active = enabled
	perf_status.text = "角色 AnimationTree：%s" % ("运行" if enabled else "已暂停")
	perf_status.modulate = Color(0.8, 0.9, 1.0)

func _on_perf_player_physics_toggled(enabled: bool) -> void:
	var player := _get_player_node()
	if player == null:
		_refresh_perf_controls()
		return
	player.set_physics_process(enabled)
	perf_status.text = "Player _physics_process：%s" % ("运行" if enabled else "已暂停")
	perf_status.modulate = Color(0.8, 0.9, 1.0)

func _on_perf_grid_process_toggled(enabled: bool) -> void:
	var grid_manager := _get_grid_manager()
	if grid_manager == null:
		_refresh_perf_controls()
		return
	grid_manager.set_process(enabled)
	perf_status.text = "GridManager _process：%s" % ("运行" if enabled else "已暂停")
	perf_status.modulate = Color(0.8, 0.9, 1.0)

func _reset_perf_isolation() -> void:
	var player := _get_player_node()
	if player != null:
		player.set_physics_process(true)
		var animation_tree := _get_player_animation_tree(player)
		if animation_tree != null:
			animation_tree.active = true
	var grid_manager := _get_grid_manager()
	if grid_manager != null:
		grid_manager.set_process(true)
	_refresh_perf_controls()
	perf_status.text = "性能隔离项已全部恢复。"
	perf_status.modulate = Color(0.65, 0.9, 0.65)
