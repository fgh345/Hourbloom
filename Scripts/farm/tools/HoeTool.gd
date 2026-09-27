extends Tool

class_name HoeTool

func _init() -> void:
	tool_name = "锄头（翻耕草地）"

func use_tool(player: CharacterBody3D, _block_pos: Vector3, _normal: Vector3) -> void:
	if player.has_method("start_hoe_action"):
		player.start_hoe_action(self)

# Called once by the player's action clock at the blade's actual ground contact.
func apply_impact(player: CharacterBody3D, block_pos: Vector3) -> void:
	if not GameManager.session.farm.can_plow_at(block_pos):
		GameLog.info("[工具] 此处不可耕作，地面不属于农田区域。（灰度 ID：%d）" % GameManager.session.farm.get_raw_region_value(block_pos))
		return

	var grid_pos := GameManager.session.farm.world_to_grid(block_pos)
	var soil_service: Node = player.get_tree().get_first_node_in_group("soil_layer_service")

	if soil_service != null and soil_service.has_method("plow_world"):
		if soil_service.plow_world(block_pos):
			GameLog.info("[工具] 已翻耕土壤 %s！（灰度 ID：%d）" % [str(grid_pos), GameManager.session.farm.get_raw_region_value(block_pos)])
		else:
			GameLog.info("[工具] 这里已经翻耕过了。")
		return

	# Fallback if world service is not present
	var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
	if tile_data.state == FarmData.SoilState.GRASS:
		GameManager.session.farm.set_tile_state(grid_pos, FarmData.SoilState.PLOWED, block_pos.y)
		GameLog.info("[工具] 已翻耕土壤 %s！（灰度 ID：%d）" % [str(grid_pos), GameManager.session.farm.get_raw_region_value(block_pos)])
	else:
		GameLog.info("[工具] 这里已经翻耕过了。")
