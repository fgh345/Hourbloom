class_name DeveloperSettings
extends RefCounted

const CONFIG_PATH := "user://developer_settings.cfg"
const DEFAULT_MINUTES_PER_SECOND := 1.0
const MIN_MINUTES_PER_SECOND := 0.1
const MAX_MINUTES_PER_SECOND := 60.0
const DEFAULT_CHARACTER_ID := "female"
const CHARACTER_IDS := ["female", "male"]

var minutes_per_second: float = DEFAULT_MINUTES_PER_SECOND
var character_id: String = DEFAULT_CHARACTER_ID
var config_path: String

func _init(path: String = CONFIG_PATH) -> void:
	config_path = path
	load_settings()

func load_settings() -> void:
	minutes_per_second = DEFAULT_MINUTES_PER_SECOND
	character_id = DEFAULT_CHARACTER_ID
	var config := ConfigFile.new()
	if config.load(config_path) != OK:
		return
	var value: Variant = config.get_value("time", "minutes_per_real_second", DEFAULT_MINUTES_PER_SECOND)
	if value is float or value is int:
		var rate := float(value)
		if is_finite(rate) and rate >= MIN_MINUTES_PER_SECOND and rate <= MAX_MINUTES_PER_SECOND:
			minutes_per_second = rate
	var saved_character: Variant = config.get_value("character", "id", DEFAULT_CHARACTER_ID)
	if saved_character is String and saved_character in CHARACTER_IDS:
		character_id = saved_character

func set_minutes_per_second(rate: float) -> Error:
	if not is_finite(rate) or rate < MIN_MINUTES_PER_SECOND or rate > MAX_MINUTES_PER_SECOND:
		return ERR_INVALID_PARAMETER
	minutes_per_second = rate
	return _save_settings()

func set_character_id(id: String) -> Error:
	if id not in CHARACTER_IDS:
		return ERR_INVALID_PARAMETER
	character_id = id
	return _save_settings()

func _save_settings() -> Error:
	var config := ConfigFile.new()
	config.load(config_path)
	config.set_value("time", "minutes_per_real_second", minutes_per_second)
	config.set_value("character", "id", character_id)
	return config.save(config_path)
