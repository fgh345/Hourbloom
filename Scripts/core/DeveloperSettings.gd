class_name DeveloperSettings
extends RefCounted

const CONFIG_PATH := "user://developer_settings.cfg"
const DEFAULT_MINUTES_PER_SECOND := 1.0
const MIN_MINUTES_PER_SECOND := 0.1
const MAX_MINUTES_PER_SECOND := 60.0

var minutes_per_second: float = DEFAULT_MINUTES_PER_SECOND
var config_path: String

func _init(path: String = CONFIG_PATH) -> void:
	config_path = path
	load_settings()

func load_settings() -> void:
	minutes_per_second = DEFAULT_MINUTES_PER_SECOND
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	var value: Variant = config.get_value("time", "minutes_per_real_second", DEFAULT_MINUTES_PER_SECOND)
	if value is float or value is int:
		var rate := float(value)
		if is_finite(rate) and rate >= MIN_MINUTES_PER_SECOND and rate <= MAX_MINUTES_PER_SECOND:
			minutes_per_second = rate

func set_minutes_per_second(rate: float) -> Error:
	if not is_finite(rate) or rate < MIN_MINUTES_PER_SECOND or rate > MAX_MINUTES_PER_SECOND:
		return ERR_INVALID_PARAMETER
	minutes_per_second = rate
	var config := ConfigFile.new()
	config.set_value("time", "minutes_per_real_second", rate)
	return config.save(config_path)
