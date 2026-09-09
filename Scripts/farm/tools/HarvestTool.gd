extends Tool

class_name HarvestTool

const WHEAT_DEF_ID := &"item.wheat"

func _init() -> void:
	tool_name = "镰刀（收获作物）"

func use_tool(player: CharacterBody3D, block_pos: Vector3, _normal: Vector3) -> void:
	if GameManager.session == null or GameManager.session.farm == null:
		return
	if GameManager.session.entities == null:
		return

	var farm := GameManager.session.farm
	var grid_pos: Vector2i = farm.world_to_grid(block_pos)
	var tile_data: FarmTileData = farm.get_tile_data(grid_pos)

	if tile_data.state != FarmData.SoilState.HARVESTABLE:
		if tile_data.state == FarmData.SoilState.SEEDED:
			GameLog.info("[工具] 作物还没成熟，再等等。")
		elif tile_data.state == FarmData.SoilState.PLOWED:
			GameLog.info("[工具] 这里刚翻耕过，还没播种。")
		else:
			GameLog.info("[工具] 这里没有可收获的作物。")
		return

	# 收获地块：清作物、回 PLOWED，并经由 tile_updated 自动刷掉作物模型与土壤贴图。
	var harvest: Dictionary = _harvest_at(player, block_pos, grid_pos)
	if harvest.is_empty():
		GameLog.info("[工具] 收获失败。")
		return

	var yield_count: int = maxi(1, int(harvest.get("yield", 1)))
	_give_yield_to_player(player, yield_count)

## 经由土壤服务收获（优先走服务，便于统一刷 Terrain 贴图与后续特效钩子）。
func _harvest_at(player: CharacterBody3D, block_pos: Vector3, grid_pos: Vector2i) -> Dictionary:
	var soil_service: Node = player.get_tree().get_first_node_in_group("soil_layer_service")
	if soil_service != null and soil_service.has_method("harvest_world"):
		return soil_service.harvest_world(block_pos) as Dictionary
	return GameManager.session.farm.harvest_crop(grid_pos)

## 产量进背包；背包满则掉在脚边，保证不丢作物。
func _give_yield_to_player(player: CharacterBody3D, yield_count: int) -> void:
	var em := GameManager.session.entities as EntityManager
	var registry: Node = Engine.get_main_loop().root.get_node(^"EntityRegistry")
	if registry == null or not registry.has_method("create_entity"):
		GameLog.warn("[工具] EntityRegistry 不可用，收获丢失。")
		return

	var wheat: EntityData = registry.create_entity(WHEAT_DEF_ID)
	if wheat == null:
		GameLog.warn("[工具] 无法创建小麦实体，收获丢失。")
		return
	var stack_comp := wheat.get_component(&"stackable") as StackableComponent
	if stack_comp != null:
		stack_comp.count = yield_count
	em.register_entity(wheat)

	var player_data: PlayerData = em.get_player(_resolve_player_id(player))
	var absorbed: int = player_data.pockets.try_add_entity(wheat.runtime_id)
	if absorbed <= 0:
		var drop_pos: Vector3 = player.global_position + (-player.global_transform.basis.z * 1.5) + Vector3.UP * 1.0
		em.clear_entity_parent(wheat.runtime_id, drop_pos, player.rotation.y)
		GameLog.warn("[工具] 背包满了，小麦掉在地上。")
		return

	if player_data.pockets.has_entity(wheat.runtime_id):
		em.set_entity_parent(wheat.runtime_id, player_data.player_id)
	else:
		# 整包并入已有堆叠，原实体不再需要。
		em.remove_entity(wheat.runtime_id)
	GameLog.info("[工具] 收获小麦 ×%d！" % absorbed)

func _resolve_player_id(player: CharacterBody3D) -> StringName:
	var id_any: Variant = player.get("simulation_player_id")
	if id_any is StringName:
		return id_any
	if id_any is String:
		return StringName(id_any)
	return &"player.main"
