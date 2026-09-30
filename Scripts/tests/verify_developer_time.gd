extends Node

const TEST_CONFIG := "user://verify_developer_time.cfg"
var failures: int = 0

func _ready() -> void:
	call_deferred("_run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		push_error(message)

func _run() -> void:
	GameManager.set_process(false)
	var args := OS.get_cmdline_user_args()
	if args.has("startup-write"):
		check(GameManager.set_time_minutes_per_second(60.0) == OK, "Persist rate before exiting process")
		get_tree().quit(failures)
		return
	if args.has("startup-read"):
		check(GameManager.developer_settings.minutes_per_second == 60.0 and GameManager.session.time.time_multiplier == 3600.0, "New process restores saved rate at startup")
		print("Restart persistence verification: ", "PASS" if failures == 0 else "FAIL")
		get_tree().quit(failures)
		return
	if FileAccess.file_exists(TEST_CONFIG):
		DirAccess.remove_absolute(TEST_CONFIG)
	var settings := DeveloperSettings.new(TEST_CONFIG)
	check(settings.minutes_per_second == 1.0, "Missing configuration defaults to one minute per second")
	check(settings.set_minutes_per_second(60.0) == OK, "Save sixty minutes per second")
	check(DeveloperSettings.new(TEST_CONFIG).minutes_per_second == 60.0, "Fresh settings instance restores saved rate")
	check(settings.set_minutes_per_second(-1) == ERR_INVALID_PARAMETER and settings.minutes_per_second == 60.0, "Reject negative rate")
	check(settings.set_minutes_per_second(INF) == ERR_INVALID_PARAMETER, "Reject nonfinite rate")
	check(settings.set_minutes_per_second(61) == ERR_INVALID_PARAMETER, "Reject rate outside UI range")
	var invalid := ConfigFile.new()
	invalid.set_value("time", "minutes_per_real_second", "bad")
	invalid.save(TEST_CONFIG)
	check(DeveloperSettings.new(TEST_CONFIG).minutes_per_second == 1.0, "Invalid configuration falls back safely")
	var clock := TimeManager.new()
	clock.time_multiplier = 3600.0
	var signals := {"minute": 0, "hour": 0, "day": 0, "normalized": true}
	clock.minute_passed.connect(func():
		signals.minute += 1
		signals.normalized = signals.normalized and clock.current_minute < 60 and clock.current_hour < 24)
	clock.hour_passed.connect(func(): signals.hour += 1)
	clock.day_passed.connect(func(): signals.day += 1)
	var before := clock.get_total_minutes()
	clock.tick(1.0)
	check(clock.get_total_minutes() - before == 60, "One real second advances sixty game minutes even in one frame")
	check(signals.minute == 60 and signals.hour == 1 and signals.normalized, "All minute events occur after normalized clock rollover")
	clock.set_time(1, 23, 30)
	clock.tick(1.0)
	check(clock.current_day == 2 and clock.current_hour == 0 and clock.current_minute == 30 and signals.day == 1, "Accelerated clock crosses midnight correctly")
	var split_clock := TimeManager.new()
	split_clock.time_multiplier = 3600.0
	before = split_clock.get_total_minutes()
	for frame in range(4):
		split_clock.tick(0.25)
	check(split_clock.get_total_minutes() - before == 60, "Rate is independent of frame subdivision")
	var slow_clock := TimeManager.new()
	slow_clock.time_multiplier = 6.0
	before = slow_clock.get_total_minutes()
	slow_clock.tick(9.0)
	check(slow_clock.get_total_minutes() == before, "Subminute remainder retained")
	slow_clock.tick(1.0)
	check(slow_clock.get_total_minutes() == before + 1, "Subminute remainder eventually advances a minute")
	var original_settings := GameManager.developer_settings
	GameManager.developer_settings = settings
	GameManager.set_time_minutes_per_second(30.0)
	GameManager.start_new_game()
	check(GameManager.session.time.time_multiplier == 1800.0, "New game inherits persisted developer rate")
	SaveManager._restore_time({"time": {"total_minutes": 1000}})
	check(GameManager.session.time.time_multiplier == 1800.0 and GameManager.session.time.get_total_minutes() == 1000, "Restoring save time retains global developer rate")
	GameManager.set_time_minutes_per_second(60.0)
	var farm: FarmData = GameManager.session.farm
	farm.set_tile_state(Vector2i(0, 0), FarmData.SoilState.PLOWED)
	farm.set_tile_state(Vector2i(5, 0), FarmData.SoilState.PLOWED)
	var sunflower := farm.get_crop(farm.plant_crop_at(Vector3(0.5, 0, 0.5), &"sunflower", CropSpecies.growth_minutes(&"sunflower")))
	var watermelon := farm.get_crop(farm.plant_crop_at(Vector3(5.5, 0, 0.5), &"watermelon", CropSpecies.growth_minutes(&"watermelon")))
	check(sunflower.growth_rate >= CropSpecies.GROWTH_RATE_MIN and sunflower.growth_rate <= CropSpecies.GROWTH_RATE_MAX, "Sunflower gets bounded individual growth rate")
	check(watermelon.growth_rate >= CropSpecies.GROWTH_RATE_MIN and watermelon.growth_rate <= CropSpecies.GROWTH_RATE_MAX, "Watermelon gets bounded individual growth rate")
	for second in range(75):
		GameManager.session.process_tick(1.0)
	check(sunflower.is_harvestable(GameManager.session.time.get_total_minutes()), "60-minute rate matures even the slowest sunflower by 75 real seconds")
	check(not watermelon.is_harvestable(GameManager.session.time.get_total_minutes()), "Watermelon does not mature prematurely")
	for second in range(32):
		GameManager.session.process_tick(1.0)
	check(watermelon.fruit_is_harvestable(0, GameManager.session.time.get_total_minutes()) and not watermelon.fruit_is_harvestable(3, GameManager.session.time.get_total_minutes()), "First watermelon is ripe while the last is still growing by 107 real seconds")
	for second in range(18):
		GameManager.session.process_tick(1.0)
	check(watermelon.fruit_is_harvestable(3, GameManager.session.time.get_total_minutes()), "All watermelon fruit ripens by 125 real seconds")
	GameInput.ensure_default_bindings()
	var ui := load("res://Scenes/UI/MasterUI.tscn").instantiate() as CanvasLayer
	get_tree().root.add_child(ui)
	ui._open_pause_menu()
	check(get_tree().paused and ui.main_page.visible, "Pause menu opens")
	ui.settings_button.pressed.emit()
	check(ui.settings_page.visible and not ui.main_page.visible and get_tree().paused, "Settings page opens while paused")
	var tools: VBoxContainer = ui.settings_page.get_node("DeveloperToolsUI")
	for rate: int in [1, 10, 30, 60]:
		tools.get_node("Presets/Rate%dButton" % rate).pressed.emit()
		check(tools.rate_spinbox.value == rate and GameManager.session.time.time_multiplier == rate * 60.0, "Preset button applies its own rate")
	tools.rate_spinbox.value = 12.5
	check(GameManager.session.time.time_multiplier == 750.0 and DeveloperSettings.new(TEST_CONFIG).minutes_per_second == 12.5, "Custom rate applies and persists")
	check(tools.summary_label.text.contains("115.2"), "UI explains real duration of one game day")
	ui._input(InputEventAction.new())
	var escape := InputEventAction.new()
	escape.action = GameInput.ACTION_TOGGLE_PAUSE_MENU
	escape.pressed = true
	ui._input(escape)
	check(not ui.settings_page.visible and ui.main_page.visible and get_tree().paused, "Escape returns from settings without unpausing")
	ui._input(escape)
	check(not get_tree().paused and not ui.pause_overlay.visible, "Second Escape resumes game")
	tools.get_node("DefaultTimeRateButton").pressed.emit()
	check(settings.minutes_per_second == 1.0 and DeveloperSettings.new(TEST_CONFIG).minutes_per_second == 1.0, "Restore default saves one minute per second")
	ui.free()
	GameManager.developer_settings = original_settings
	GameManager.start_new_game()
	DirAccess.remove_absolute(TEST_CONFIG)
	for signal_name: String in ["minute_passed", "hour_passed", "day_passed"]:
		for connection: Dictionary in clock.get_signal_connection_list(signal_name):
			clock.disconnect(signal_name, connection["callable"])
	print("Developer time verification: ", "PASS" if failures == 0 else "FAIL", " (", failures, " failures)")
	get_tree().quit(0 if failures == 0 else 1)
