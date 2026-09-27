# Q版 Low Poly 农场女孩
## AI / Blender 自动建模规范 v1.0

### 1. 项目目标

创建一个适用于农场经营 / 生活模拟游戏的 Q 版女性角色。

角色需要满足：

- Low Poly
- Game Ready
- 可绑定骨骼
- 可制作基础动作
- Blender 内结构清晰
- 可导出 GLB / FBX
- 适合 Unity / Godot / Unreal
- 优先保证轮廓和可读性，不追求电影级细节
- 不使用复杂毛发、布料模拟或高模雕刻

视觉方向：

- 温暖的日系乡村动画感
- 柔和自然色彩
- 手绘材质
- 简洁大色块
- 少量颜色渐变
- 可见轻微 Low Poly 几何切面
- 可爱、友善、轻松的农场生活气质

---

# 2. 基础尺寸

Blender 单位：

```text
Unit System: Metric
Unit Scale: 1.0
```

角色标准高度：

```text
Height: 1.20 m
```

坐标规范：

```text
Z = Up
X = Left / Right
Y = Front / Back
```

角色：

```text
面对 -Y
脚底 = Z 0
角色中心 = X 0
Root Origin = 双脚中心地面位置
```

所有对象：

```text
Scale = 1,1,1
Rotation 已 Apply
```

---

# 3. 身体比例

整体采用约：

```text
2.7～2.9 头身
```

目标：

```text
Head height:   0.40～0.43 m
Body:          0.35～0.38 m
Legs:          0.35～0.40 m
```

视觉比例：

```text
头部          很大
躯干          短
手臂          短粗
腿            短粗
手            简化
脚            略大
肩宽          窄
腰            不强调
```

不要使用真实人体比例。

---

# 4. 推荐 Polygon Budget

完整角色目标：

```text
3000～4500 triangles
```

推荐目标：

```text
约 3500 tris
```

允许最大值：

```text
5000 tris
```

各部分预算：

| Mesh | Target tris |
|---|---:|
| Head | 500 |
| Face | 包含于 Head |
| Hair | 600～800 |
| Body | 400 |
| Arms + Hands | 350 |
| Legs | 300 |
| Boots | 300 |
| Shirt / Overalls | 350 |
| Scarf | 150 |
| Hat | 350 |
| Backpack | 300 |
| Accessories | 100～300 |

不要为了达到预算而强行增加 Polygon。

---

# 5. Mesh 拆分

必须至少拆成：

```text
CHR_Body
CHR_Head
CHR_Hair
CHR_Hat
CHR_Scarf
CHR_Clothes
CHR_Boots
CHR_Backpack
CHR_Eyes
```

可选：

```text
CHR_Mouth
CHR_Accessories
CHR_HairAccessory
```

推荐 Blender Collection：

```text
Character
├── Mesh
├── Rig
├── Props
└── Reference
```

---

# 6. Head

头部采用简单 Q 版球形结构。

要求：

- 接近圆形
- 下巴非常弱
- 脸部略扁
- 后脑比脸部略大
- 不制作写实鼻梁
- 鼻子可完全使用贴图表示
- 不制作复杂嘴唇

建议：

```text
12～16 segment 基础球体
```

允许局部调整轮廓。

禁止使用：

```text
Subdivision Surface > Level 1
```

最终导出前尽量 Apply 或移除。

---

# 7. Face

眼睛主要使用贴图实现。

不要制作：

- 完整眼球系统
- 眼窝
- 复杂眼睑
- 独立睫毛 Mesh

推荐：

```text
Eye Mesh = 两个轻微浮出脸部的小平面
```

或者直接使用：

```text
Face BaseColor texture
```

眼睛比例：

```text
大
圆润
间距略宽
```

鼻子：

```text
贴图
```

嘴：

```text
贴图或非常简单 Curve/Mesh
```

---

# 8. Hair

这是最重要的 Low Poly 控制区域。

禁止：

```text
Particle Hair
Geometry Nodes Hair
Hair Curves
大量独立发丝
```

头发必须使用：

```text
大型几何发块
```

推荐结构：

```text
Hair_Main
Hair_Bangs
Hair_Left
Hair_Right
Hair_Back
```

总发块：

```text
约 8～16 个
```

刘海：

```text
3～6 个主要几何块
```

发尾使用明显 Polygon 轮廓。

目标不是表现每根头发，而是表现：

```text
发型轮廓
```

---

# 9. Hat

农场草帽采用明显 Low Poly 建模。

拆分：

```text
Hat_Crown
Hat_Brim
Hat_Ribbon
Hat_Flower
```

草编纹理：

不要建模。

全部通过 BaseColor 表现。

帽檐建议：

```text
12～16 sides
```

帽顶：

```text
10～14 sides
```

允许明显多边形切面。

---

# 10. Clothes

服装：

```text
白色内衬
绿色农场工作服
短裤 / 连体工作服
红橙色围巾
```

不要使用 Cloth Simulation 作为最终方案。

衣服尽量：

```text
贴合 Body
```

通过少量轮廓变化表现层次。

褶皱：

```text
主要使用贴图
```

不要建大量几何褶皱。

---

# 11. Hands

手部使用极简设计。

推荐：

```text
Mitten Style
```

即：

```text
手掌 + 拇指
```

不要求五根独立手指。

如果需要抓取工具：

```text
Thumb
Palm
```

必须保证可以握住：

- 水壶
- 锄头
- 菜篮
- 种子袋

---

# 12. Boots

靴子使用大型块面。

每只鞋控制：

```text
100～160 tris
```

鞋带：

```text
不要建模
```

使用 BaseColor texture。

鞋底可以有：

```text
一层简单几何
```

---

# 13. Backpack

结构：

```text
Main Bag
Top Flap
2 Straps
Optional Buckle
```

禁止：

```text
真实缝线
复杂金属扣
多个小袋
```

背包目标：

```text
200～350 tris
```

---

# 14. Material

优先使用：

```text
1 个角色主材质
```

Material：

```text
MAT_Character
```

可选：

```text
MAT_Eyes
```

不要为：

```text
帽子
鞋子
衣服
头发
背包
```

分别建立大量材质。

尽量 Atlas。

---

# 15. Texture

主纹理：

```text
CHR_BaseColor.png
```

分辨率：

```text
1024 × 1024
```

游戏特别轻量时允许：

```text
512 × 512
```

默认不要求：

```text
Normal Map
Metallic Map
Height Map
```

推荐：

```text
BaseColor
AO
```

如果使用 ORM：

```text
R = AO
G = Roughness
B = Metallic
```

但本角色 Metallic 应基本为：

```text
0
```

---

# 16. 色彩

主要 Palette：

```text
Hair:
#5B4031

Skin:
#F1C6A8

Green:
#758558

Dark Green:
#536849

Cream:
#F1E5C7

Scarf:
#C96550

Leather:
#795239

Boot:
#68452F

Straw:
#D9AA62
```

允许 AI 根据光照轻微调整。

避免：

```text
高饱和 Neon
纯黑
纯白
强金属
```

---

# 17. Shader

推荐：

```text
Principled BSDF
```

参数参考：

```text
Metallic: 0
Roughness: 0.65～0.9
Specular: 低
```

目标：

```text
柔和
哑光
手绘
```

不要追求 PBR 写实材质。

---

# 18. UV

所有主要 Mesh 应共用：

```text
1 个 1024 × 1024 Atlas
```

UV 要求：

```text
无明显重叠
除非左右完全对称区域
```

建议 Padding：

```text
8～16 px @ 1024
```

高优先级区域：

```text
Face
Hair front
Torso
Hat front
```

可以使用更大的 UV 面积。

低优先级：

```text
鞋底
帽子内部
背包底面
```

可以降低 texel density。

---

# 19. Rig

Armature 名称：

```text
RIG_Character
```

基础结构：

```text
root

└── pelvis
    └── spine_01
        └── spine_02
            └── neck
                └── head
```

腿：

```text
pelvis
├── thigh_L
│   └── shin_L
│       └── foot_L
│           └── toe_L
│
└── thigh_R
    └── shin_R
        └── foot_R
            └── toe_R
```

手臂：

```text
spine_02
├── upperarm_L
│   └── forearm_L
│       └── hand_L
│
└── upperarm_R
    └── forearm_R
        └── hand_R
```

可增加：

```text
hair_L
hair_R
scarf
backpack
```

作为简单 Secondary Bones。

---

# 20. Rig Simplification

不要建立：

```text
独立手指骨骼
面部完整 Rig
肌肉 Rig
Twist Bone 系统
复杂 Dynamic Bone 系统
```

本角色优先游戏实用性。

---

# 21. IK

建议建立：

```text
IK_Hand_L
IK_Hand_R
IK_Foot_L
IK_Foot_R
```

腿部 IK 必须支持：

```text
走路
跑步
蹲下
浇水
种植
```

---

# 22. Skinning

每个 Vertex 建议：

```text
≤ 4 Bone Influences
```

肩部、胯部需要保证正常变形。

重点检查：

```text
Shoulders
Elbows
Hip
Knees
Neck
```

由于角色是 Low Poly：

不要追求完全真实肌肉变形。

---

# 23. Facial Expressions

不要创建复杂 Face Rig。

推荐：

```text
Texture Swap
或者
Shape Keys
```

至少：

```text
Neutral
Happy
Surprised
Angry
Sad
Blink
```

Shape Key：

```text
Face_Happy
Face_Sad
Face_Blink
Face_Surprised
```

---

# 24. 动画需求

首批动画：

```text
Idle
Walk
Run
Pickup
Carry
Watering
Hoe
Plant
Wave
```

推荐帧率：

```text
30 FPS
```

Loop 动画：

```text
Idle
Walk
Run
Watering
Hoe
```

---

# 25. 农场工具兼容

右手默认需要兼容：

```text
Watering Can
Hoe
Axe
Pickaxe
Fishing Rod
```

推荐增加 Bone：

```text
socket_hand_R
```

背部：

```text
socket_back
```

头部：

```text
socket_head
```

方便游戏运行时挂载物品。

---

# 26. 建模策略

AI Agent 应按照以下顺序执行：

```text
01. 创建 Scene
02. 设置 Metric
03. 建立角色高度参考线
04. Blockout Head
05. Blockout Torso
06. Arms
07. Legs
08. Boots
09. Hair
10. Clothes
11. Hat
12. Accessories
13. Backpack
14. 调整 Silhouette
15. 控制 Poly Count
16. UV
17. Texture
18. Rig
19. Skin Weight
20. Test Pose
21. Export
```

禁止一开始制作：

```text
纹理
细节
花纹
小饰品
```

必须先保证：

```text
Silhouette
Proportion
Topology
```

---

# 27. AI 建模优先级

优先级从高到低：

```text
1. 正确比例
2. 清晰轮廓
3. Low Poly
4. Rig 可用
5. UV 正确
6. 色彩风格
7. 小细节
```

如果面数超预算：

首先删除：

```text
小饰品
头发小块
服装褶皱
帽子装饰
```

不要降低脸部主要轮廓质量。

---

# 28. 禁止事项

Agent 不得：

```text
使用 Sculpt 创建高模再直接保留
使用真实毛发
使用复杂 Cloth Simulation
自动生成数万 Polygon
给每个部件创建独立 4K Texture
建立复杂五指 Rig
建立写实眼球
建立真实牙齿
使用写实皮肤 Shader
加入不必要 Geometry Nodes
```

---

# 29. Blender 文件命名

推荐：

```text
farm_girl_v01.blend
```

Objects：

```text
CHR_Body
CHR_Head
CHR_Hair
CHR_Hat
CHR_Clothes
CHR_Boots
CHR_Backpack
RIG_Character
```

Textures：

```text
T_CHR_BaseColor.png
T_CHR_AO.png
```

Material：

```text
M_CHR_Main
```

---

# 30. 导出

首选：

```text
GLB
```

文件：

```text
farm_girl.glb
```

备选：

```text
FBX
```

Export 前：

```text
Apply Rotation
Apply Scale
Check Normals
Triangulate
Remove unused materials
Remove hidden meshes
Remove reference images
```

保留：

```text
Armature
Animations
Materials
Textures
```

---

# 31. 最终验收

Agent 完成后必须检查：

### Geometry

```text
Total triangles ≤ 5000
目标约 3500
```

### Transform

```text
Scale = 1
脚底 Z = 0
```

### Mesh

```text
无 Non-Manifold
无重复 Vertex
无反向 Normal
```

### UV

```text
无意外重叠
无越界
```

### Rig

测试：

```text
T Pose
Walk Pose
Squat Pose
Arms Up
Hold Item
```

不得出现明显穿模和严重拉伸。

### Engine

确认：

```text
GLB 可以重新导入 Blender
Armature 正常
Texture 正常
Animation 正常
```

---

# 32. 最终交付物

AI Agent 最终必须生成：

```text
farm_girl_v01.blend

farm_girl.glb

textures/
├── T_CHR_BaseColor.png
└── T_CHR_AO.png

renders/
├── front.png
├── side.png
├── back.png
└── perspective.png
```

以及：

```text
model_report.txt
```

报告内容：

```text
Triangle Count
Vertex Count
Material Count
Texture Resolution
Bone Count
Animation List
Export File
```

---

# 33. 给 Blender AI Agent 的最终执行指令

创建一个 Game Ready 的 Q 版 Low Poly 农场女孩角色。

严格遵循本文档的角色比例、Polygon Budget、Mesh 拆分、材质、UV、Rig 和导出规则。

建模时首先保证角色 Silhouette 和比例。

不要试图完全还原概念图中的细碎装饰。

所有细节应遵循：

“能用 Texture 表现的，不增加 Geometry。”

角色最终 Triangle Count 目标约 3500，绝对不要超过 5000。

完成基础模型后再创建 UV、手绘风格 BaseColor、Rig 和基础动画。

所有阶段都应保持 Scene 整洁、对象名称规范，并保证最终资产可以直接作为实时游戏角色使用。