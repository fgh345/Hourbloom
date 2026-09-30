# 独立作物与土壤格

`FarmData._grid` 是 1 米土壤格，只记录地面状态、高度等土壤属性；它不保存作物。`CropData` 是单株记录，包含稳定 ID、世界坐标、种类、播种时间、生长时长、种子占位半径和成熟覆盖半径。`FarmData._crops_by_chunk` 按落点所在区块索引作物 ID，供邻近查询、成长更新和场景加载使用。一个土壤格可以包含多株作物。

播种在角色正前方 0.75 米处投射到地面，在接触帧写入精确世界坐标。地面必须已翻耕；播种时仅拒绝两颗种子的实体占位重叠，没有按土壤格或固定株距限制。收获按接触点附近的植株 ID 删除单株，不改变土壤格。`get_crop_covered_tiles(id, minute)` 依据当前生长进度和覆盖半径返回植物涉及的多个土壤格，供后续西瓜藤、水分、养分和密植模拟使用。覆盖半径目前只提供查询与占位显示基础；生长竞争、减产、藤蔓模型尚未实现。

`GridManager` 按作物 ID 创建独立 `CropNode`，节点保留作物精确坐标。当前占位方块在拥挤时缩小，以避免方块相交；正式作物模型需要按具体物种的形状处理碰撞与枝叶遮挡。区块仍按 32 米的土壤坐标加载，不随作物密度增加网格分辨率。

新存档保留土壤热力图，单株写入 `FarmLayers/crop_instances.json`，包含 ID、位置、生长参数和已模拟到的分钟数。读取旧版无该文件的存档时，将作物热力图里的每个作物转为一条位于原土壤格中心的单株记录。重新保存后采用独立作物格式。旧热力图本身没有记录格内精确位置，因此无法恢复旧作物更细的落点。


## Species and spreading plants

See [sunflower and watermelon](../systems/crops.md) for species controls, vine geometry, individual fruit harvesting and save compatibility. CropData persists shape_seed and harvested_fruits. The soil grid does not constrain plant geometry.
