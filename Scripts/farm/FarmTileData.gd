extends RefCounted
class_name FarmTileData

var state: int = FarmData.SoilState.GRASS
var moisture: float = 50.0
var nutrients: float = 50.0
var height: float = 0.0

func duplicate_data() -> FarmTileData:
	var copy := FarmTileData.new()
	copy.state = state
	copy.moisture = moisture
	copy.nutrients = nutrients
	copy.height = height
	return copy
