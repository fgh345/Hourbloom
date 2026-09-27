# 森林农具 01：锄头预览

锄头已接入实际 Player，保留独立场景用于造型、双手握持和挥锄节奏评审。运行时使用统一角色骨架，包含原有移动、跳跃动画及挥锄动作。

## 造型与动作

延续森林女孩的低多边形风格：暖棕木柄、灰蓝金属锄刃、浅色布条握把。锄头总长约 0.85 米、刃宽 0.192 米，按 1.2 米角色比例制作。当前按五阶段动作示意图重做，全长 0.60 秒：低位准备、举锄蓄力、全身下挥、触地下沉、小幅拔锄后直接收手。整段从 1.15 秒等比例加速至 0.60 秒，触地后收尾约 0.157 秒，取消再次高举及停顿。取消此前“脸前停止、小于 90°、严格无侧偏”的限制，加入身体重心和腿部配合。

角色现有骨架没有手指骨骼，预览使用专用闭合握持网格替换原张开手掌。两个手臂跟随锄柄握持位置，工具与人物一同烘焙导出，减少运行时握持漂移。原独立角色资产保留，Player 改用合并后的 `Assets/Tools/Hoe/forest_girl_tools.glb`。

预览手臂使用 `arm_geometry.py` 重建：袖子、袖口、前臂及手腕是连续封闭曲面，肘腕共享顶点并渐变分配骨骼权重。两段手臂的固定总长从约 21.8 厘米调整到 30.6 厘米，让双手能在脸前留出空间；挥动中不伸缩。头部随发力自然下视，触地时约低头 11°。姿态参考五阶段示意图，允许举锄阶段轻微侧向姿势和躯干配合；帽檐穿插仍仅记录，不为避帽扭曲动作。

前臂绕自身轴线的旋转以握持手掌朝向为参考，与手掌一起平顺回位，避免收锄时手腕突然向内拧。使用始终与前臂保持夹角的掌面方向，避免参考轴接近平行时翻转。

## 评审

打开 `Scenes/Tools/HoeReview.tscn`，运行当前场景（F6）。左上可切换正面、45°、侧面，暂停、慢放，或拖动时间条逐帧查看。场景不加载游戏关卡，不操作农场数据。

- `Assets/Tools/Hoe/hoe.glb`：独立工具资源。
- `Assets/Tools/Hoe/character_with_hoe.glb`：人物、握持手和工具的联合预览资源。
- `Art/Tools/Hoe/`：Blender 制作脚本、可编辑源文件及测量报告。
- `Art/Tools/Hoe/Review/hoe_motion.mp4`：Godot 实际导入后的连续多角度录像。
- `Art/Tools/Hoe/Review/hoe_recovery.mp4`：收锄阶段半速近景录像。

## 验证与录制

Blender 以 240 fps 烘焙，并将动画从第 0 帧导出；Godot 也保留 240 fps 导入，避免快速下挥段的重采样造成滑手。触地时刻约 0.443478 秒落在两个采样帧之间，因此相邻两帧使用同一触地姿态，保证事件发生时锄刃贴地。生成脚本重导入 GLB 后再测量握持误差及锄刃最低点。

```sh
blender --background --factory-startup --python Art/Tools/Hoe/build_hoe_preview.py
godot --headless --path . --editor --import
godot --headless --path . --script Scripts/tests/verify_hoe_review.gd
godot --path . --resolution 1152x648 --fixed-fps 60 --write-movie /tmp/hoe_review.avi --script Scripts/debug/capture_hoe_review.gd
ffmpeg -y -i /tmp/hoe_review.avi -c:v libx264 -pix_fmt yuv420p -crf 20 -an -movflags +faststart Art/Tools/Hoe/Review/hoe_motion.mp4
```

验证检查 Godot 导入、动作时长、双手与工具骨骼实际位移、所有采样姿态的有效性及独立场景完整循环。额外计算导入后蒙皮变形的握把顶点与手腕距离、锄刃最低点，防止仅骨骼数据正确而可见工具脱手。触地时还检查：锋刃明显低于金属套筒、以接近竖直的角度切土；触地后锄刃小幅离地，双手保持低位收回。避免仅检查“某个顶点碰到地面”而遗漏锄刃反向。

五阶段评审重点是：准备低位、蓄力高举、下挥时身体前倾、触地时屈膝下沉、收回时锄刃小幅离地后直接收手，不再二次高举。验证全程握柄稳定、手臂与腿部骨段不伸缩、靴底不穿地，触地只有一个连续区间。头部、头发和帽檐的穿插计数保留在 manifest.json 中，不阻断导出。

时序与物理落点共用 `Assets/Tools/Hoe/HoeMotion.gd`：准备约 0.052 秒、蓄力约 0.261 秒、下挥约 0.381 秒、触地约 0.443 秒、低位收回约 0.532 秒，0.60 秒结束。

Godot 验证还在握持、抬锄、触地及收回姿势对导入后手臂曲面焊接重合点，确认只有一个连通体、每条边闭合，避免仅骨骼连上而袖口仍断裂。手臂近景可用 `godot --path . --resolution 1152x648 --script Scripts/debug/capture_hoe_review.gd -- --arms-only` 重新生成。

收锄旋转回归检查覆盖导入后关键帧之间的插值，要求前臂与掌面参考的轴向偏差小于 0.5°。收锄近景录制使用上述录像命令，并在脚本参数后追加 `-- --recovery-only`；以半速循环播放触地至结束的片段。

## 游戏内使用

按 `1` 选择锄头后仍保持普通空手待机；鼠标左键使用时才显示工具并挥锄，结束后恢复空手。挥锄沿人物当前面朝的方向，点击时不转向准星；镜头朝天空也能操作。实际翻耕发生在角色前方约 0.87 米的锄刃落点，不能远程翻地。落点须为可耕地面、没有实体遮挡且与脚下高度差不超过 0.12 米，坡度不超过 20°；坡地适配目前采用拒绝超范围操作，而非修改挥锄轨迹。

动作时钟与 AnimationTree 的时间定位共用：约 0.443 秒触地时调用原 `HoeTool` / `SoilLayerService` 翻耕，0.60 秒结束。挥锄期间固定朝向、停止水平移动，阻止跳跃、重复点击、切工具和交互。失去地面、开启控制台、隐藏玩家、暂停或进入飞行模式时取消未完成动作；触地前重新校验落点。站立、走跑跳及切换工具均使用普通手掌与原动作；工具和握持手只在挥锄的有效握持阶段显示，起手和收手各以约 0.052 秒混合回普通动作，避免工具在过渡姿势中脱手。

运行时资产由 `build_hoe_runtime.py` 合并原动作与已经验证的锄头姿势，统一使用连续手臂骨架，避免切换整个人物。原动作按秒转换至 240 fps，普通手掌重新绑定到加长后的手腕。运行时仅包含 `Hoe` 工具动作，删除 `HoeIdle` 和持锄待机混合分支。可见锄头与握持手同步切换，连续袖口始终保留。

```sh
blender --background --factory-startup --python Art/Tools/Hoe/build_hoe_runtime.py
godot --headless --path . --editor --import
godot --headless --path . --script Scripts/tests/verify_hoe_review.gd -- --runtime
godot --headless --path . --script Scripts/tests/verify_player_hoe.gd
godot --headless --path . --script Scripts/tests/verify_player_jump.gd
godot --path . --resolution 1152x648 --fixed-fps 60 --write-movie /tmp/hoe_gameplay.avi --script Scripts/debug/capture_player_hoe.gd
```

`Review/hoe_gameplay.mp4` 使用真实 Player 和内存农田，在隔离平地上录制挥锄、翻耕、移动与跳跃，不读取或写入玩家存档。专项测试覆盖触地时机、重复输入、行动锁定、切工具显隐、控制台取消、空中/飞行禁用、区域限制、实体遮挡及实际土壤服务调用，并验证四个朝向与镜头方向解耦。

五个关键姿势可用 `godot --path . --script Scripts/debug/capture_hoe_review.gd -- --poses-only` 生成；`Review/hoe_reference_poses.png` 是对应姿势对照图，`Review/hoe_motion.mp4` 提供 45°、侧面、正面的连续动作录像。
