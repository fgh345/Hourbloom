# 森林女孩角色接入

玩家使用 `forest_girl_package (1).zip` 的第三版模型。原始交付保存在 `Art/Characters/ForestGirl/Source/`；附件脚本仅归档，不执行。运行资源为 `Assets/Characters/ForestGirl/forest_girl.glb`，可编辑运行工程为 `Art/Characters/ForestGirl/runtime.blend`。

保留 254 个网格、29 个材质、25,122 个三角形和 16 根骨骼，统一缩放到 1.20 米并归零脚底。`shape_profile.py` 只修改静止网格前后坐标，逐顶点检查横向与高度坐标不变。头部深度由源单位 0.808 增至 1.066，衣身 0.440 → 0.618，裙摆 0.716 → 1.160；头发、五官、服装细节、帽子与包袋同步调整。源文件不变，重新生成不会累积变形。

## 动画和跳跃

运行模型有 13 段动画。源 Idle/Walk 保留，并提供 freehand 命名、跑步、左右倾斜和跳跃动作。源动画和新增动作统一使用四元数，避免四元数／欧拉模式不一致造成摆腿轨道丢失。导入脚本保留头部顶点色，并只循环待机、行走和跑步。

原地和移动跳跃分别使用 `jump_start` / `jump_move`、`freehand_fall` / `fall_move`。上升约 0.292 秒，从蹬伸姿势开始，随后收腿；移动跳跃前后错腿、反向摆臂。下落约 0.25 秒，伸腿后保持准备触地的姿势。AnimationTree 的 jump_style/fall_style 根据离地水平速度锁定混合比例，包括走下台阶；空中松开方向键不重新切换腿势。

玩家跳跃速度为 4.8、局部重力倍率为 1.6，整体为更短的小跳。全局重力和走跑速度不改。独立平地测试观测到约 0.7 米跳高和 0.62 秒腾空。

原地落地使用约 0.208 秒的 `landing_soft`，控制器保持 0.18 秒，走动或再次起跳可立即打断。移动落地直接恢复 Walk/Run，通过 OneShot ADD 叠加 `landing_recoil`：仅胸、头和双臂缓冲，腿、骨盆及根节点不受影响，腿部继续迈步。叠加淡入 0.02 秒、淡出 0.08 秒，再次起跳立即终止。普通状态混合时间为 0.05 秒。

翻滚动画、状态、触发阈值、减速、输入锁定及强制恢复行走逻辑已移除。原地落地鞋底按实际变形网格校准，并检查关键帧之间的高度，最低误差约 1.5 毫米。人物位移仍由 CharacterBody3D 处理，没有添加根运动或地形 IK；源 Walk 的步幅与移动速度匹配仍沿用现有配置。

## 重新生成与验证

在项目根目录使用隔离 Blender 后台进程执行 `Art/Characters/ForestGirl/prepare_runtime.py`，然后运行 Godot 编辑器导入。Blender MCP 当前未连接；后台方式不会覆盖用户正在编辑的 Blender 场景。导出后会重新导入并检查身高、骨骼、动作、有限矩阵和落地高度，记录在 `runtime_manifest.json`。

Godot 检查脚本：

- `Scripts/tests/verify_forest_girl.gd`：模型、材质、动画轨道，局部摆腿／摆臂、原地与移动姿势区别，以及叠加过滤和腿部中立。
- `Scripts/tests/verify_player_jump.gd`：真实玩家在独立平地上原地／走／跑跳跃，空中姿势选择锁定、落地继续迈步、速度不降、原地恢复被移动打断，以及首个着陆帧再跳。手动积分与引擎物理步长统一为 60 Hz，避免此前测试步长不一致。
- `Scripts/tests/verify_farmer_girl.gd` 和 `verify_resource_uids.gd`：旧资源及场景引用兼容性。

本轮三套角色与跳跃测试均通过。移动落地缓冲期间大腿局部旋转仍变化，行走／奔跑保持 5／8 速度；独立测试无退出泄漏告警。主场景另以项目默认 120 Hz 验证走跑、跳跃和落地，退出仍有既有资源清理告警。

## 连续动态预览

`Scenes/Tools/FarmerGirlReview.tscn` 提供多角度单动作预览，`capture_review.gd` 和 `render_runtime.py` 更新静态检查图。`Review/profile_before_side.png` 是此前本机记录的修改前侧面图，不属于可重新生成的当前模型输出，也不随仓库分发。

`capture_jump_motion.gd` 用真实玩家和控制器在独立舞台连续演示原地跳、移动跳、奔跑跳与落地立即再跳，不加载存档。录制命令：

```sh
godot --path . --resolution 1152x648 --fixed-fps 60 --write-movie /tmp/jump_motion.avi --script Art/Characters/ForestGirl/capture_jump_motion.gd
ffmpeg -i /tmp/jump_motion.avi -c:v libx264 -pix_fmt yuv420p -crf 20 -an -movflags +faststart Art/Characters/ForestGirl/Review/jump_motion.mp4
```

`Review/jump_motion.mp4` 是正常速度连续演示；`motion_*.png` 是其中的起跳、空中和着陆帧，用于核对视频与实际姿势。静态图不替代连续动作验收。

## 评审输出与版本管理

评审脚本生成的截图、录像保留在本机，不提交到仓库；运行上面的命令可重新生成。仓库仅保留角色正面图和锄头姿势对照图作为代表性参考。文中其他评审输出路径是生成目标，并非检出后必有的文件。源模型、原始交付、制作脚本和运行资源继续版本管理。
