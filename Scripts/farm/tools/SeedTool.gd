extends Tool

class_name SeedTool

func _init() -> void:
	tool_name = "种子（种植作物）"

func use_tool(player: CharacterBody3D, block_pos: Vector3, _normal: Vector3) -> void:
	var grid_pos := GameManager.session.farm.world_to_grid(block_pos)
	var soil_service: Node = player.get_tree().get_first_node_in_group("soil_layer_service")

	if soil_service != null and soil_service.has_method("seed_world"):
		if soil_service.seed_world(block_pos):
			GameLog.info("[工具] 已在 %s 播种！" % str(grid_pos))
		else:
			var tile_data_fail: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
			if tile_data_fail.state == FarmData.SoilState.GRASS:
				GameLog.info("[工具] 草地不能播种，请先翻耕土壤。")
			else:
				GameLog.info("[工具] 这里已经种了作物。")
		return

	# Fallback if world service is not present
	var tile_data: FarmTileData = GameManager.session.farm.get_tile_data(grid_pos)
	if tile_data.state == FarmData.SoilState.PLOWED:
		if GameManager.session.farm.plant_crop_at(block_pos) > 0:
			GameLog.info("[工具] 已在 %s 播种！" % str(grid_pos))
		else:
			GameLog.info("[工具] 此位置与已有种子重叠。")
	elif tile_data.state == FarmData.SoilState.GRASS:
		GameLog.info("[工具] 草地不能播种，请先翻耕土壤。")
	else:
		GameLog.info("[工具] 这里已经种了作物。")
