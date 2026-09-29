extends RefCounted

var _camera: Camera3D
var _max_distance: float

func _init(camera: Camera3D, max_distance: float = 64.0) -> void:
	_camera = camera
	_max_distance = max_distance

func try_interact(player: Node3D) -> bool:
	var hit := _raycast_from_screen_center(player)
	if hit.is_empty():
		return false

	var obj: Variant = hit.get("collider")
	if not obj is Node3D or not obj.has_method("interact"):
		return false
	var target := obj as Node3D
	if player.global_position.distance_to(hit["position"]) > 2.5:
		return false
	var kind: StringName = &"Pickup" if target is InteractableItem3D else &"Interact"
	var effect: Callable = func():
		if is_instance_valid(target):
			target.interact(player)
	var valid: Callable = func():
		var current := _raycast_from_screen_center(player)
		return is_instance_valid(target) and not current.is_empty() and current.get("collider") == target and player.global_position.distance_to(current["position"]) <= 2.5
	return player.start_basic_action(kind, effect, valid)

func process_hover(player: CharacterBody3D) -> void:
	if EventBus == null:
		return

	var hit := _raycast_from_screen_center(player)
	if hit.is_empty():
		EventBus.update_crosshair_prompt.emit("")
		return

	var obj: Variant = hit.get("collider")
	var prompt: String = ""
	var interact_key: String = GameInput.get_action_binding_text(GameInput.ACTION_INTERACT)
	
	if obj is EntityView3D:
		var view := obj as EntityView3D
		if view.entity_data:
			if view.entity_data.has_component(&"container"):
				prompt = "打开容器 [%s]" % interact_key
			elif view.entity_data.has_component(&"seat"):
				prompt = "驾驶车辆 [%s]" % interact_key
			else:
				prompt = "交互 [%s]" % interact_key
				
		# Fallback for subclass overrides
		if view.has_method("get_interaction_prompt"):
			prompt = view.call("get_interaction_prompt")
				
		EventBus.update_crosshair_prompt.emit(prompt)
	elif obj != null and obj.has_method("interact"):
		prompt = "交互 [%s]" % interact_key
		if obj.has_method("get_interaction_prompt"):
			prompt = obj.get_interaction_prompt()
		EventBus.update_crosshair_prompt.emit(prompt)
	else:
		# 地形等无交互碰撞体：若脚下是成熟作物，提示可收获。
		EventBus.update_crosshair_prompt.emit(_get_farm_tile_prompt(hit.get("position", Vector3.ZERO)))

## 成熟作物准星提示。CropNode 自身无碰撞体，射线只会打中地形，
## 因此按命中点反查农田网格状态。
func _get_farm_tile_prompt(hit_pos: Vector3) -> String:
	if GameManager.session == null or GameManager.session.farm == null:
		return ""
	var farm := GameManager.session.farm
	var tile_data: FarmTileData = farm.get_tile_data(farm.world_to_grid(hit_pos))
	if tile_data != null and tile_data.state == FarmData.SoilState.HARVESTABLE:
		return "收获小麦 [鼠标左键 / 3]"
	return ""

func try_use_tool(player: CharacterBody3D, tool: Tool) -> bool:
	if tool == null:
		return false

	# Hoe contact is sampled in front of the character, even when the camera
	# points into the sky. Other tools retain their screen-target interaction.
	if tool is HoeTool:
		return player.has_method("start_hoe_action") and player.start_hoe_action(tool)

	var hit := _raycast_from_screen_center(player)
	if hit.is_empty():
		return false

	var hit_pos: Vector3 = hit.get("position", Vector3.ZERO)
	var normal: Vector3 = hit.get("normal", Vector3.UP)
	if not tool is SeedTool and not tool is HarvestTool:
		tool.use_tool(player, hit_pos, normal)
		return true
	if player.global_position.distance_to(hit_pos) > 2.5 or GameManager.session == null or GameManager.session.farm == null:
		return false
	var farm := GameManager.session.farm
	var tile: FarmTileData = farm.get_tile_data(farm.world_to_grid(hit_pos))
	var kind: StringName = &"Seed" if tool is SeedTool else &"Harvest"
	if tile == null or (kind == &"Seed" and tile.state != FarmData.SoilState.PLOWED) or (kind == &"Harvest" and tile.state != FarmData.SoilState.HARVESTABLE):
		return false
	var collider: Object = hit["collider"]
	var effect: Callable = func(): tool.use_tool(player, hit_pos, normal)
	var valid: Callable = func():
		var current := _raycast_from_screen_center(player)
		if current.is_empty() or current.get("collider") != collider or (current["position"] as Vector3).distance_to(hit_pos) > 0.3:
			return false
		var state: FarmTileData = farm.get_tile_data(farm.world_to_grid(hit_pos))
		return state != null and state.state == (FarmData.SoilState.PLOWED if kind == &"Seed" else FarmData.SoilState.HARVESTABLE)
	return player.start_basic_action(kind, effect, valid)

func _raycast_from_screen_center(player: Node3D) -> Dictionary:
	if _camera == null or not is_instance_valid(_camera):
		return {}

	var viewport := _camera.get_viewport()
	if viewport == null:
		return {}

	var center_screen := viewport.get_visible_rect().size * 0.5
	var origin: Vector3 = _camera.project_ray_origin(center_screen)
	var direction: Vector3 = _camera.project_ray_normal(center_screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + direction * _max_distance)
	query.collide_with_areas = true
	query.collide_with_bodies = true

	if player != null and player is CollisionObject3D:
		query.exclude = [player.get_rid()]

	var world := _camera.get_world_3d()
	if world == null:
		return {}

	return world.direct_space_state.intersect_ray(query)
