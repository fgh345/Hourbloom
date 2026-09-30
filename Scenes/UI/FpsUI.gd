extends PanelContainer

const UPDATE_INTERVAL := 0.25
var _elapsed: float = 0.0

@onready var fps_label: Label = $Margin/FpsLabel

func _ready() -> void:
	_refresh()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= UPDATE_INTERVAL:
		_elapsed = fmod(_elapsed, UPDATE_INTERVAL)
		_refresh()

func _refresh() -> void:
	var fps := int(Engine.get_frames_per_second())
	fps_label.text = "FPS: %d" % fps if fps > 0 else "FPS: --"
