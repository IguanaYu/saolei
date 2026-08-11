# 扫雷挖矿 UI/UX 改进方法论

> 本文档是项目视觉与交互改造的总纲，先讲方法、再讲方案、最后讲路线图。
> 目标：把当前"Godot 默认丑"的界面，做成"有设计感的 indie 游戏"水平。

---

## 一、现状诊断（针对当前代码）

| 维度 | 问题 | 证据 |
|---|---|---|
| 视觉风格 | 全部使用 Godot 默认控件，无 Theme 资源，按钮就是灰色矩形 | `project.godot` 无 gui/theme 配置 |
| 配色 | 暗棕色背景 + 一堆纯色矩形格子，无体系 | `Cell.tscn` 中每个状态一个硬编码 Color |
| 字体 | 默认字体，中文渲染粗糙 | 全局未设 default_font |
| 按钮反馈 | 仅依赖 Godot 默认 hover/press，无缩放、无音效 | `shop.gd`、`main_menu.gd` 仅 `.pressed.connect` |
| 数字变化 | HUD 数值瞬变，无跳动、无飘字 | `hud.gd` 直接 `label.text = "钱: %d"` |
| 界面切换 | 主菜单/关卡选择/结算面板都是瞬切，无过渡动画 | `Main.tscn` 中多个 Panel 共存 |
| 网格交互 | 双击用 0.35s 时间窗 → 单击有延迟感；无 hover 高亮 | `cell.gd:39-58` |
| 信息层级 | HUD 五个 Label 平铺，权重相同 | `HUD.tscn` 单一 HBoxContainer |
| 商店锁定 | 锁定原因藏在 `lock_reason()` 里，玩家看不到 | `shop.gd:77-88` |
| 单位状态 | 机器人 idle/moving/working 三态无任何可视化 | `robot.gd` |

---

## 二、方法论总框架：三层金字塔

```
        ┌───────────┐
        │  交互体验  │  ← UX 流程、信息层级、引导（决定好不好用）
        └───────────┘
        ┌───────────┐
        │  反馈动画  │  ← Juice / Game Feel（决定爽不爽）
        └───────────┘
        ┌───────────┐
        │  视觉基底  │  ← 配色、字体、Theme（决定好不好看）
        └───────────┘
```

**核心原则**：自下而上做。视觉基底没搭好，再多的动画也救不回"丑"；反馈动画没做，视觉再美也"死"。

**核心心法**（来自 "Juice It or Lose It"）：每个玩家操作都必须有视觉 + 听觉 + 运动三层反馈。宁可每个反馈都很轻，也不要任何操作"静默无响应"。

---

## 三、视觉基底方法论

### 3.1 风格选择：5 种候选

| 方案 | 风格 | 特点 | 参考 | 难度 | 适配度 |
|---|---|---|---|---|---|
| **A** | 深色霓虹 Dark Neon | 黑底 + 高饱和强调色 + 数字发光 | Balatro、Hexcells | 低-中 | ★★★★★ |
| B | 极简扁平 Minimal Flat | 大色块、无渐变、靠对比 | Mini Metro | 低 | ★★★ |
| C | 像素复古 Pixel Retro | 低分辨率 + 限色板 | Vampire Survivors | 中 | ★★★★ |
| D | 玻璃拟物 Glassmorphism | 半透明毛玻璃 + 模糊 | 现代卡牌 UI | 高 | ★★ |
| E | 手绘卡通 Hand-drawn | 不规则线条 + 水彩 | Townscaper | 极高 | ★ |

**推荐方案 A（深色霓虹）**：完美契合"挖矿地下 + 矿石发光"主题，零美术素材需求，靠 StyleBoxFlat + 简单 shader 即可实现。

### 3.2 暗色配色系统（5 层）

| 层级 | 用途 | 推荐色值 |
|---|---|---|
| 背景层 | 最底层，游戏区域 | `#0D0805` 或 `#1A1410`（深棕黑） |
| 面板层 | 弹窗、HUD、未挖掘格 | `#1C2128` |
| 格子层 | 已挖掘格子 | `#262D36` |
| 强调层 | 高亮、选中、金币 | `#F0B429`（琥珀金）/ `#00D9A3`（矿翠绿） |
| 警示层 | 地雷、危险 | `#E5484D`（暗红） |

**数字 1-8**（沿用扫雷传统但降饱和，GitHub Dark 配色）：
```
1: #58A6FF  2: #56D364  3: #F85149  4: #D2A8FF
5: #F0883E  6: #79C0FF  7: #FF7B72  8: #D2A8FF
```

**核心法则**：暗色主题中，上层元素要比下层**更亮**，靠亮度差表现层级深度。

**配色工具**：[coolors.co](https://coolors.co)、[colorbox.io](https://colorbox.io)、Material Theme Builder。

### 3.3 字体搭配

| 角色 | 推荐字体 | 协议 |
|---|---|---|
| 标题/UI | 思源黑体（Source Han Sans）Bold | OFL |
| 正文 | 思源黑体 Regular | OFL |
| 数字（HUD/坐标） | m6x11（Balatro 同款）或 Press Start 2P | OFL |

**搭配原则**：标题用粗黑体，正文用常规黑体，数字用等宽/像素字体形成对比。**不超过 2 个字族**。

**Godot 4 处理中文**：直接将 `.ttf`/`.otf` 放入项目，创建 `FontVariation` 资源，在 Theme 中设置 `default_font`。中文字体 5-10MB，但 Godot 4 动态字体按需渲染，无需子集化。

### 3.4 质感提升速查表（Godot 4.6 具体操作）

| 技巧 | Godot 实现方式 |
|---|---|
| 圆角 | StyleBoxFlat → `corner_radius` 6-8px |
| 阴影 | StyleBoxFlat → `shadow_color` + `shadow_size`（无模糊）；要模糊用 `GradientTexture2D` radial + StyleBoxTexture 9-slice |
| 内描边 | StyleBoxFlat → `border_width` 1px + `border_color` 比背景稍亮（如 `#3D444D`） |
| 渐变背景 | `GradientTexture2D` 节点，或 shader 画在 ColorRect 上 |
| 噪点纹理 | FastNoiseLite 生成 seamless noise，叠加 opacity 0.03-0.08 消除塑料感 |
| 数字发光 | Label 配 shader 或 `theme_override_color("font_color", 高饱和色)` |
| 图标库 | Kenney.nl（CC0）、Game-icons.net（CC-BY） |

### 3.5 Godot Theme 系统使用流程

1. **创建**：FileSystem 右键 → New Resource → Theme → 命名 `theme_main.tres`
2. **设全局**：Project Settings → GUI → Theme → Custom → 指向 `theme_main.tres`，所有 Control 自动继承
3. **配置核心控件**（Theme Editor 底部面板）：
   - Button：normal/hover/pressed 三套 StyleBoxFlat，圆角 6px、边框 1px
   - Panel：bg_color 为面板层色，圆角 8px
   - Label：default_font = 思源黑体，font_size 14-16
   - **Theme Type Variation**：创建 `NumberLabel` 类型变体（Base Type = Label），设置不同字体/颜色，在具体 Label 的 `theme_type_variation` 属性填入
4. **代码动态修改**（注意必须 `.duplicate()`）：
   ```gdscript
   var sb := get_theme_stylebox("normal", "Button").duplicate() as StyleBoxFlat
   sb.bg_color = Color("#2D333B")
   add_theme_stylebox_override("normal", sb)
   ```
5. **多主题切换**：创建 `theme_dark.tres` / `theme_light.tres`，运行时 `get_tree().root.theme = load(...)` 一键切换

> ⚠️ `get_theme_stylebox()` 返回共享引用，修改前必须 `.duplicate()`，否则污染全局。

---

## 四、反馈动画方法论（Game Feel）

### 4.1 按钮反馈（三层叠加）

| 方案 | 做法 | 复杂度 |
|---|---|---|
| **A** | **Tween 缩放**：hover → scale 1.08，press → scale 0.92，用 `TRANS_BACK` + `EASE_OUT` 产生微 overshoot。先 `tween.kill()` 防冲突 | 低 |
| **B** | **Theme StyleBox 颜色切换**：4 状态 StyleBoxFlat，hover 亮度 +15%，pressed 亮度 -10%，disabled 降饱和 | 低 |
| **C** | **粒子/涟漪 + 音效**：点击瞬间实例化 5-8 个 GPUParticles2D，音效 `pitch_scale = randf_range(0.95, 1.05)` 防腻 | 中 |

**关键参数**：hover 100-150ms、press 回弹 200ms、缓动用 `EASE_OUT`。

**落地方式**：封装一个 `JuiceButton.gd` 继承 Button，全局复用。

### 4.2 数字变化反馈

| 方案 | 做法 | 适用 |
|---|---|---|
| **D** | **飘字弹出**：预制 `FloatingText.tscn`（Label + Tween 三段：①scale 0→1.3 `TRANS_BACK` 0.15s ②上浮 30px + scale 1.3→1.0 0.3s ③fade out 0.3s）。金币=黄、伤害=红、经验=绿 | 金币、生命、矿石产出 |
| **E** | **HUD 数字跳动补间**：值变化时用 Tween 0.3s 从旧值插值到新值（整数），同时 scale 1.0→1.15→1.0 脉冲；负面变化叠加红色 flash（modulate 红→白 0.2s） | HUD 常驻数值 |

**参考 Slay the Spire**：获得金币时数字跳动 + 飘字 + 音效三层叠加。

### 4.3 界面切换动画

| 方案 | 做法 | 适用 |
|---|---|---|
| **F** | **面板缩放淡入**：scale 0.85→1.0 + modulate.a 0→1，`TRANS_BACK` + `EASE_OUT` 0.25s。⚠️ Control 节点必须设 `pivot_offset` 为中心 | 所有弹窗 |
| **G** | **级联入场**：面板内子元素逐个入场，每个延迟 50-80ms，position.y +20px + alpha 0 滑入 | 主菜单、关卡选择、结算 |

**参考 Mini Metro**：级联延迟 60ms，精致而不拖沓。

### 4.4 重要事件强调

| 方案 | 做法 | 适用 |
|---|---|---|
| **H** | **屏幕震动 + 闪屏**：Camera2D offset 随机抖动（4-8px，0.3s 衰减）+ 全屏 ColorRect flash（alpha 0.4→0，0.15s） | 踩雷、通关、稀有矿 |
| **I** | **粒子爆发 + 慢动作**：GPUParticles2D（20-30 粒子径向爆发 0.6s）+ `Engine.time_scale = 0.3` 持续 0.5s 后 Tween 回弹 | 通关、稀有解锁 |
| **J** | **成就横幅滑入**：顶部横幅（位置 -100→目标Y，`TRANS_BACK`，0.4s），停留 1.5s，滑出 0.3s | 解锁新矿石、里程碑 |

### 4.5 Godot 4.6 工具速查

| 工具 | 用途 | 关键 API |
|---|---|---|
| Tween | 所有动态数值动画 | `create_tween().tween_property(node, "scale", V2*1.1, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)` |
| AnimationPlayer | 多属性/多节点复杂动画 | 面板级联、结算画面 |
| Theme | 统一 StyleBox/字体 | 4 状态 StyleBox |
| GPUParticles2D | 粒子爆发 | 预制 `.tscn`，`one_shot = true` |
| Shader (CanvasItem) | 闪光/溶解/描边 | `material.set_shader_parameter(...)` |
| AudioStreamPlayer | 每个反馈必配音效 | `pitch_scale = randf_range(0.95, 1.05)` |

---

## 五、交互体验方法论（UX）

### 5.1 HUD 信息层级

**痛点**：当前 5 个 Label 平铺等权。

| 方案 | 做法 |
|---|---|
| **A** | **三段分组**：左段（命+钱，大字号红/金色）— 中段（目标进度，居中常驻）— 右段（时间+矿石+积分，小字号灰色） |
| **B** | **按需出现**：矿石/积分默认隐藏，变化时弹出 1.5s 淡出；时间 < 30s 变红放大 |
| **C** | **紧急覆盖**：命=1 或时间<15s 全屏边缘红色脉冲；钱不够买任何东西时钱旁加 "!" 图标 |

### 5.2 网格交互

**痛点**：双击 0.35s 时间窗导致单击延迟；无 hover 高亮。

| 方案 | 做法 |
|---|---|
| **A** | **消除双击延迟**：改用中键 = chord（Microsoft Minesweeper 标准），或"左+右键同时按"和弦。移除 `_last_click_time` 逻辑 |
| **B** | **hover 反馈**：鼠标进入时背景提亮 15% + 半透明边框。Ctrl 按住高亮全部正交邻居（Tametsi 招牌） |
| **C** | **键盘导航**：方向键移光标，空格=开格，F=标雷，Enter=chord。无障碍必备 |

### 5.3 商店/购买流程

**痛点**：锁定原因藏在代码里玩家看不到。

| 方案 | 做法 |
|---|---|
| **A** | **锁定原因内联**：按钮两行——第一行 `🔒 检测型`，第二行灰字 `通关 2-5 解锁`；钱不够时不灰，价格数字变红闪烁 |
| **B** | **购买预览**：hover 商店按钮时，网格上可放置区高亮绿色脉冲，不可放置区灰化（参考 PVZ） |
| **C** | **价格趋势**：基地递增价格旁加 ↑ 箭头提示"下次更贵" |

### 5.4 机器人/单位系统

**痛点**：idle/moving/working 无可视化，玩家不知道机器人在干嘛。

| 方案 | 做法 |
|---|---|
| **A** | **头顶状态气泡**：idle = "...", moving = 方向箭头, working = 星星迸发（参考 Loop Hero） |
| **B** | **目标连线**：每个机器人半透明细线连到 `_current_target`（参考 Mindustry） |
| **C** | **idle 根因区分**：拆为 `idle_no_work`（无安全目标，灰色"无目标"气泡）和 `idle_blocked`（路径被堵，红色闪烁气泡） |

### 5.5 关卡选择/章节地图

**痛点**：当前 GridContainer 排 5 个按钮，无空间叙事。

| 方案 | 做法 |
|---|---|
| **A** | **线性路径图**：`Path2D` + `PathFollow2D`，关卡沿弯曲路径排列，已通关=旗帜，当前位置=闪烁圆点，锁定=剪影（SMB3 World Map 模式） |
| **B** | **分叉选择**：第 3 关后分叉为"奖励关/挑战关"双路径（Slay the Spire 模式） |
| **C** | **章节时间线**：章节选择页显示横轴全景时间线（Hades escape sequence 模式） |

### 5.6 新手引导

**痛点**：当前 `phase_hint_label` 是纯文字教程。

| 方案 | 做法 |
|---|---|
| **A** | **首次出现高亮**：第一次进入 placing_base 阶段时全屏暗化，仅中心区域亮起 + 脉冲箭头；首次有钱买机器人时商店按钮脉冲发光 |
| **B** | **悬停 tooltip**：hover 商店按钮 0.5s 弹气泡（功能简介）；hover 数字格弹气泡（"周围 X 格有 Y 雷"） |
| **C** | **渐进解锁即教程**：第 1 章仅开墙型可用，第 2 章解锁标雷型，第 3 章解锁检测型。用关卡设计引导玩家"先学会只用一种"，无文字引导 |

---

## 六、实施路线图

### 第一阶段：视觉基底（1-2 天，立竿见影）

- [ ] 创建 `theme_main.tres` 并设为全局
- [ ] 配置 5 层配色（背景/面板/格子/强调/警示）
- [ ] 接入思源黑体 + m6x11 数字字体
- [ ] 所有按钮/面板加 6-8px 圆角 + 1px 亮色描边
- [ ] 背景叠噪点纹理（opacity 0.05）
- [ ] Cell.tscn 改用 GitHub Dark 数字配色

### 第二阶段：核心反馈（2-3 天，提升手感）

- [ ] `JuiceButton.gd` 通用脚本（方案 4.1-A/B）
- [ ] `FloatingText.tscn` 飘字系统（方案 4.2-D）
- [ ] HUD 数字跳动补间（方案 4.2-E）
- [ ] 面板入场/退场动画工具函数（方案 4.3-F）
- [ ] 关键事件音效池 + pitch 随机化

### 第三阶段：UX 流程（2-3 天，提升可用性）

- [ ] 消除双击延迟，改中键 chord（方案 5.2-A）
- [ ] Cell hover 反馈（方案 5.2-B）
- [ ] 商店锁定原因内联显示（方案 5.3-A）
- [ ] HUD 三段分组（方案 5.1-A）

### 第四阶段：高光时刻（3-5 天，提升记忆点）

- [ ] 屏幕震动 + 闪屏系统（方案 4.4-H）
- [ ] 通关粒子爆发 + 慢动作（方案 4.4-I）
- [ ] 成就横幅（方案 4.4-J）
- [ ] 机器人头顶状态气泡（方案 5.4-A）

### 第五阶段：体验延展（按需）

- [ ] 关卡路径图重构（方案 5.5-A）
- [ ] 首次出现高亮引导（方案 5.6-A）
- [ ] 渐进式章节解锁（方案 5.6-C，依赖关卡设计）

---

## 七、决策清单（给你做选择）

按以下顺序决定大方向：

1. **视觉风格**：用方案 A（深色霓虹）还是有别的偏好？
2. **数字字体**：m6x11（Balatro 风）还是 Press Start 2P（更像素）？
3. **双击 vs 中键**：取消双击改中键 chord，还是保留双击但优化判定？
4. **章节地图**：现阶段是否值得重构（取决于后续内容量）？
5. **新手引导**：文字 tooltip 还是高亮遮罩？

确定方向后，从第一阶段开始逐项落地。每阶段完成后再看下一阶段是否需要调整。

---

## 附：参考游戏清单

- **Balatro** — 暗背景 + 霓虹强调色、CRT 滤镜、m6x11 字体、按钮反馈
- **Mini Metro / Mini Motorways** — 极简扁平、级联入场动画、纯色配色
- **Slay the Spire** — 章节地图分叉、数字反馈、卡牌 UI
- **Hades** — 时间线回顾、横幅滑入、风格统一
- **Hexcells / Tametsi** — 暗色配色、邻居高亮、扫雷类最佳实践
- **Vampire Survivors** — 像素风、屏幕震动、升级横幅
- **Loop Hero** — 头顶状态图标、自动化可视化
- **Mindustry** — 单位目标连线
- **Microsoft Minesweeper** — 中键 chord、键盘导航
- **PVZ / Bloons TD** — 商店锁定显示、购买预览高亮
