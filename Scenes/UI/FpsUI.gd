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
	var process_ms := float(Performance.get_monitor(Performance.TIME_PROCESS)) * 1000.0
	var physics_ms := float(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)) * 1000.0
	var draw_calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var rendered_objects := int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var primitives := int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var video_mem_mb := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0)
	var node_count := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var resource_count := int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))

	fps_label.text = "FPS: %s\nCPU: %.2f ms  Physics: %.2f ms\nDraw Calls: %d  Objects: %d\nPrimitives: %d\nVideo Mem: %.1f MB\nNodes: %d  Resources: %d" % [
		str(fps) if fps > 0 else "--",
		process_ms,
		physics_ms,
		draw_calls,
		rendered_objects,
		primitives,
		video_mem_mb,
		node_count,
		resource_count
	]
