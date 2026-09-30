# 田园女孩：Low Poly v1

> 此文档记录保留的旧田园女孩素材。当前游戏主角已切换为用户提供的 Forest Girl，接入说明见 `forest_girl.md`。

外观以新版三视图为准：短碎发、红帽带与花饰、绿色短外套、米色裙装、红围巾、斜挎皮包、棕靴。技术规格采用 `Art/Characters/FarmerGirl/model_specification.md`。文档中旧背带裤描述被新版图覆盖；总高1.20m包括帽子。

当前验收：3,608三角面、1,950编辑顶点、11个运行网格、1个主材质、27根骨（含4个编辑IK控制骨）；总高1.20m、头高0.42m，约2.86头身。身体UV栅格交叠检测为0，所有原始壳体闭合，最大4骨影响。Blender GLB重新导入、Godot角色检查（含动作有效握持位置和表情实例隔离）、33文件UID检查通过，主场景实际行走/跳跃通过。完整游戏退出仍有既有的资源释放告警；独立角色验证退出正常。

## 可编辑源与交付

- `Art/Characters/FarmerGirl/farm_girl_v01.blend`：分网格、骨架、编辑用IK、动画、评审灯光。
- `Assets/Characters/FarmerGirl/farm_girl.glb`：规范交付名。
- `Assets/Characters/FarmerGirl/farmer_girl.glb`：游戏既有资源名，内容与交付版相同，保留原资源UID。
- `Assets/Characters/FarmerGirl/textures/T_CHR_BaseColor.png`、`T_CHR_AO.png`：1024²主色图与真实AO烘焙。AO保留供调色使用，运行材质使用主色图，避免重复阴影。
- `Art/Characters/FarmerGirl/renders/`：四视图及真实骨骼动作评审图。
- `Art/Characters/FarmerGirl/model_report.txt`、`asset_manifest.json`：生成统计。

规范出现 `MAT_Character` 与 `M_CHR_Main` 两种材质名称，这版统一选后者。角色使用单一主材质，按 `CHR_*` 分网格，面朝 Blender -Y，导入 Godot后朝 +Z；Player保持180°转向。角色根原点与脚底位于地面，所有几何按米直接构建。

## 制作方式

`build_farmer_girl.py` 先调用 `lowpoly_geometry.py` 构建闭合低模，检查退化面和非流形边，再展开UV与绘制主色、建立骨架、烘焙AO、导出和渲染。身体UV使用统一打包的独立岛；眼嘴独立预留带边距纹理单元，闭合薄壳的隐藏背面有意共享对应面部颜色。细部花纹、鞋带和眼睛使用贴图，不增加几何。

`lowpoly_rig.py` 提供9个规定动作，另外保留13个游戏移动/预览兼容动作与4个验收姿势。IK控制骨在源文件中可开启约束用于编辑；导出动作使用已写入的FK关键帧，运行时无需IK求解。

表情为Neutral、Happy、Surprised、Angry、Sad、Blink、Sleepy、Thinking。`CharacterAppearance.gd` 对每个角色创建独立材质，按面部UV区域切换贴图行；自动眨眼只覆盖眼睛。游戏角色胶囊、镜头锚点和near已按1.20m校准。

水壶和收获篮沿用既有独立道具；预览中按新角色比例缩放，不计入角色面数。农活动作目前可在评审场景播放；这一资产制作没有新增农活玩法入口。

## 重建与检查

```bash
blender --factory-startup --background --python Art/Characters/FarmerGirl/build_farmer_girl.py
blender --background Art/Characters/FarmerGirl/farm_girl_v01.blend --python Art/Characters/FarmerGirl/render_review.py
godot --headless --path . --editor --import
godot --headless --path . --script Scripts/tests/verify_farmer_girl.gd
godot --path . res://Scenes/Tools/FarmerGirlReview.tscn
```

本机 Blender 5.2 与系统OCIO版本不同。验证时使用临时OCIO 2.4兼容配置，不改系统安装；普通一致版本环境无需此设置。

视觉保真仍应结合实际渲染评审：这版是可继续编辑的程序建模低模资产，概念图的手绘笔触、柔和衣褶和精细五官不会自动成为完全相同的成品。

## 评审输出与版本管理

评审脚本生成的截图、录像保留在本机，不提交到仓库；运行上面的命令可重新生成。仓库仅保留角色正面图和锄头姿势对照图作为代表性参考。文中其他评审输出路径是生成目标，并非检出后必有的文件。源模型、原始交付、制作脚本和运行资源继续版本管理。
