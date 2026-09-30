extends Tool

class_name HarvestTool

func _init() -> void:
	tool_name = "采收（向日葵 / 单个西瓜）"

func use_tool(player: CharacterBody3D, block_pos: Vector3, _normal: Vector3) -> void:
	if GameManager.session == null or GameManager.session.farm == null:
		return
	if GameManager.session.entities == null:
		return

	var player_data := GameManager.session.entities.get_player(_resolve_player_id(player))
	if player_data == null:
		return
	var farm := GameManager.session.farm
	var crop := farm.get_crop_near(block_pos, 0.6, true)
	if crop == null:
		if farm.get_crop_near(block_pos, 0.6) != null:
			GameLog.info("[工具] 作物还没成熟，再等等。")
		else:
			GameLog.info("[工具] 这里没有可收获的作物。")
		return

	if not EntityRegistry.has_def(CropSpecies.item_id(crop.crop_type)):
		GameLog.warn("[工具] 缺少收获物品定义，保留作物。")
		return

	# 按地面位置采摘一个成熟目标；西瓜藤蔓保留。
	var harvest: Dictionary = farm.harvest_at(block_pos)
	if harvest.is_empty():
		GameLog.info("[工具] 收获失败。")
		return

	var yield_count: int = maxi(1, int(harvest.get("yield", 1)))
	_give_yield_to_player(player, yield_count, StringName(harvest.get("crop_type", "sunflower")))

## 产量进背包；背包满则掉在脚边，保证不丢作物。
func _give_yield_to_player(player: CharacterBody3D, yield_count: int, species: StringName) -> void:
	var em := GameManager.session.entities as EntityManager
	var registry: Node = Engine.get_main_loop().root.get_node(^"EntityRegistry")
	if registry == null or not registry.has_method("create_entity"):
		GameLog.warn("[工具] EntityRegistry 不可用，收获丢失。")
		return

	var harvested_item: EntityData = registry.create_entity(CropSpecies.item_id(species))
	if harvested_item == null:
		GameLog.warn("[工具] 无法创建收获实体，收获丢失。")
		return
	var stack_comp := harvested_item.get_component(&"stackable") as StackableComponent
	if stack_comp != null:
		stack_comp.count = yield_count
	em.register_entity(harvested_item)

	var player_data: PlayerData = em.get_player(_resolve_player_id(player))
	var absorbed: int = player_data.pockets.try_add_entity(harvested_item.runtime_id)
	if absorbed <= 0:
		var drop_pos: Vector3 = player.global_position + (-player.global_transform.basis.z * 1.5) + Vector3.UP * 1.0
		em.clear_entity_parent(harvested_item.runtime_id, drop_pos, player.rotation.y)
		GameLog.warn("[工具] 背包满了，作物掉在地上。")
		return

	if player_data.pockets.has_entity(harvested_item.runtime_id):
		em.set_entity_parent(harvested_item.runtime_id, player_data.player_id)
	else:
		# 整包并入已有堆叠，原实体不再需要。
		em.remove_entity(harvested_item.runtime_id)
	GameLog.info("[工具] 收获%s ×%d！" % [CropSpecies.display_name(species), absorbed])

func _resolve_player_id(player: CharacterBody3D) -> StringName:
	var id_any: Variant = player.get("simulation_player_id")
	if id_any is StringName:
		return id_any
	if id_any is String:
		return StringName(id_any)
	return &"player.main"
