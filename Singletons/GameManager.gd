extends Node

## The single Autoload that holds the active GameSession

var session: GameSession = null
var developer_settings := DeveloperSettings.new()

func _enter_tree() -> void:
    # Ensure there is always a session available immediately when the game boots
    if session == null:
        start_new_game()

func _process(delta: float) -> void:
    if session != null:
        session.process_tick(delta)

func start_new_game() -> void:
    session = GameSession.new()
    session.time.time_multiplier = developer_settings.minutes_per_second * 60.0

func end_game() -> void:
    session = null

func set_time_minutes_per_second(rate: float) -> Error:
    var error := developer_settings.set_minutes_per_second(rate)
    if error != ERR_INVALID_PARAMETER and session != null:
        session.time.time_multiplier = developer_settings.minutes_per_second * 60.0
    return error

func set_character_id(id: String) -> Error:
    if id not in DeveloperSettings.CHARACTER_IDS:
        return ERR_INVALID_PARAMETER
    var player := get_tree().get_first_node_in_group("player")
    if player != null and (not player.has_method("set_character_visual") or not player.call("set_character_visual", id)):
        return ERR_CANT_CREATE
    return developer_settings.set_character_id(id)
