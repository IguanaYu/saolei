# 外部试玩版 · UI 裁剪与变强商店解锁 · 实施计划

> **版本**：v1.0（2026-09-28）
> **✅ 2026-10-01 执行状态**：已落地——章节页/每日挑战/签到/挖矿档案入口已断开隐藏，变强商店与总矿石 L2 通关后揭示（L3 起 meta 生效），分享/DEBUG/F5 收口。
> **上游**：[外部试玩版-v0.1-执行计划.md](../外部试玩版-v0.1-执行计划.md) 第 1 步第 5 项（标出试玩版要呈现的菜单和功能）
> **依据**：L1–L4 设计文档 + 2026-09-28 会话逐项确认
> **性质**：代码改动计划——定「改哪里、怎么改、怎么验」。实施时逐提交推进，每提交过一遍对应回归项。

---

## 0. 已确认决策（2026-09-28）

| # | 决策 | 备注 |
|---|---|---|
| 1 | 试玩版交付**已有 4 关**（1-1~1-4），第五关**后续必做**，本次只隐藏不实现 | |
| 2 | **变强商店在通关 L2 后才对玩家开放**；此前所有矿石/商店入口隐藏 | L1/L2 为 `meta_progression=false`，提前开放会让玩家买到无效升级 |
| 3 | **L2 通关后引导玩家回主页（主菜单）选择升级**：结算页做揭示，揭示时刻落在主菜单 | 选关页高亮保留为二次强化 |
| 4 | 收起：章节选择页、每日挑战、签到、挖矿档案、分享按钮；设置页砍占位项 | 面板与场景保留，仅不可达/隐藏，发行候选阶段再逐项定去留 |
| 5 | 移除 F5 换肤调试入口；Splash 版本号改试玩版文案 | DEBUG 加钱按钮 L1–L4 已由 `shop_hidden` 覆盖 |

**核心原则**：矿石作为**奖励**从 L1 结算就开始积累显示（钩子），**消费入口**（商店）通关 L2 前不可见；解锁瞬间「新东西出现」即体感断层时刻。

---

## 1. 改动总览

| 提交 | 主题 | 涉及文件 |
|---|---|---|
| ① | 数据层：L1 meta 修正 + unlock_hint 字段 | `scripts/data/level_database.gd`、`scripts/data/level_data.gd` |
| ② | 变强商店解锁链（可见性 + 防呆） | `scripts/autoload/save_system.gd`、`scripts/ui/main_menu.gd`、`scripts/ui/level_select.gd`、`scripts/ui/hud.gd`、`scripts/ui/ore_shop.gd`、`scripts/main.gd` |
| ③ | L2 揭示与回主页引导 | `scripts/ui/results_panel.gd` |
| ④ | 页面裁剪 + 调试/占位清理 | `scripts/main.gd`、`scripts/ui/level_select.gd`、`scripts/ui/settings_panel.gd`、`scenes/ui/MainMenu.tscn`、`scenes/ui/SettingsPanel.tscn`、`scenes/ui/ResultsPanel.tscn`、`scenes/ui/SplashScreen.tscn` |
| ⑤ | 全流程回归（§5 清单） | — |

---

## 2. 分项详述

### 提交 ① 数据层

**A1. L1 显式 `meta_progression = false`**
- 位置：`level_database.gd` `_apply_playtest_level1()`（现 L2/L3/L4 均已显式设置，唯独 L1 漏了，默认 `true`）
- 理由：L1 教学算术「起始 75 + 免费阶段收入 = 耗尽时刻恰好够买 opener+marker（100）」必须保护——起始金币轨会 +50 破坏它；`start_lives = 0`（无命）会被起始生命轨破坏
- 附带收益：HUD 矿石标签可见性统一按 `meta_progression` 控制（见 B5）

**A2. LevelData 新增 `unlock_hint: String = ""`**
- 位置：`level_data.gd` 字段区（挨着 `no_stars` / `is_playtest`）
- L2 配置：`_apply_playtest_level2()` 中 `lvl.unlock_hint = "变强商店"`
- 数据驱动：首通某关后追加「🎉 新功能解锁」行；L5 等后续关可直接复用

### 提交 ② 变强商店解锁链

**统一解锁条件**：`LevelSystem.is_level_unlocked("ch01_s03")`（等价于「L2 已通关」）。

**B1. SaveSystem 持久化「商店已见过」标志**
- 新增存档字段 `oreshop_seen: bool` + `is_oreshop_seen()` / `mark_oreshop_seen()`
- 在 OreShop 首次 `open()` 时置位（写完触发既有存档保存路径）

**B2. 主菜单（`main_menu.gd`）**
- `_refresh_ore()` 扩展为同时控制可见性：
  - 未解锁 → `PowerUpButton` 与 `OreLabel`（总矿石）`visible = false`
  - 已解锁 → 显示；若 `not SaveSystem.is_oreshop_seen()` → 金色 modulate 高亮（同选关页手法）+ 按钮文案前缀「新 · 」
- 既有 `unlock_changed` / `ore_changed` 信号连接正好驱动刷新，无需新增信号

**B3. 选关页（`level_select.gd` `_refresh_ore_row()`）**
- OreRow（总矿石 + 变强 + 教学句）可见性挂同一条件：未解锁**整行隐藏**
- 高亮逻辑维持现状（L3 已解锁且未进过 L3）——玩家在主页买完回来仍见「矿石能变强。」作二次强化；进过 L3 后永久可见、不再高亮

**B4. HUD（`hud.gd`）**
- 新增 `set_ore_visible(v: bool)` 控制 `ore_label`（`hud.gd:13`）
- `main.gd` `_start_level_with()` 进关时按 `lvl.meta_progression` 调用：L1/L2 隐藏，L3/L4 显示
- 局内看得见的矿石必须在本局有意义

**B5. OreShop 入口防呆（`ore_shop.gd` `open()`）**
- 函数开头：未解锁直接 `return`（单点防护，覆盖 `main.gd:70-71` 两个信号入口及其他潜在路径）

### 提交 ③ L2 揭示与回主页引导（`results_panel.gd`）

**C1. 首通解锁提示**
- `_unlock_feedback()`（现仅章末关触发，`results_panel.gd:304-320`）扩展：当前关 `lvl.unlock_hint != ""` 且本次为首通 → 追加 `"🎉 新功能解锁: %s" % lvl.unlock_hint`
- 效果：L2 首通结算出现「🎉 新功能解锁: 变强商店」，玩家知道攒的矿石有用途了

**C2. 返回按钮改道主页**
- `_handle_level_mode()` 中：若当前关为 L2 且首通且 result == "win" → `back_button.text = "返回主页"` 并置实例标志 `_back_to_menu = true`
- `_on_back()`（`results_panel.gd:43-47`）优先检查该标志 → emit `back_to_menu_requested`
- **仅首通生效**：重打 L2 恢复「返回选关」；L1/L3/L4 通关仍「返回选关」（下一关就在手边）
- 引导链完整闭环：L2 结算揭示 → 主页高亮「新 · 变强商店」→ 首次购买 → 开始冒险 → 选关页高亮 → L3 进场即见

### 提交 ④ 页面裁剪 + 调试/占位清理

**D1. 开始冒险直达选关（`main.gd`）**
- `_on_start_adventure()`（`main.gd:149-152`）：改为 `level_select.set_chapter("ch01"); level_select.show()`，跳过 ChapterSelect
- `_on_level_select_back()`（`main.gd:167-170`）：改为显示主菜单（原为章节页）
- ChapterSelect 场景保留但不可达（12 章网格是死内容观感）

**D2. 选关页只显示试玩关（`level_select.gd` `refresh()`）**
- 循环内 `if not lvl.is_playtest: continue` → 1-5（未改造的旧 Boss 关）隐藏
- 未来第五关配置 `is_playtest = true` 后**自动出现**，无需再改此处
- BackButton 文案「返回章节」→「返回主菜单」

**D3. 主菜单精简（`MainMenu.tscn`）**
- 隐藏 MenuRow 中 `StatsButton` / `DailyButton` / `SignInButton`，保留 `SettingsButton`
- 解锁前主菜单只有：开始冒险、设置；解锁后：开始冒险、新·变强商店、设置

**D4. 移除签到自动弹窗（`main.gd:132-138`）**
- `_on_splash_finished()` 删除 `can_sign_today()` 判断与 tween 弹窗

**D5. 设置页精简（`SettingsPanel.tscn` / `settings_panel.gd`）**
- 隐藏：音频组（音乐/音效开关、音量滑条、「音频系统尚未接入」占位注）、「重看新手教程」按钮（toast 占位）
- 保留：屏幕震动、网格线、全屏、清除存档、返回

**D6. 结算页隐藏分享（`ResultsPanel.tscn`）**
- 隐藏 `ShareButton` 节点；`main.gd:80-81` 的 toast 连接一并删除

**E1. 移除 F5 换肤（`main.gd:448-452`）**

**E2. Splash 版本文案（`SplashScreen.tscn`）**
- 「v0.3 · Godot 4.6 · 单机开发版」→「v0.1 · 外部试玩版」

**E3. DEBUG 加钱按钮**：L1–L4 已在 `shop_hidden` 含 `"debug"`；随 D2 过滤后无其他可达关卡，无需额外改动。

---

## 3. 经济核对（解锁时刻的购买力）

L1 + L2 首通共 **400 矿**（各 200，`level_database.gd:233-234` 默认值）。变强商店 Lv1 价格：起始金币 50 / 起始生命 80 / 移动速度 100 / 工作速度 100 / 开局送机器人 100。400 矿够买 3–4 条 Lv1 轨但买不全 5 条——**第一次间场购买有真实取舍**，符合 L3「进场即见」的设计分量。

---

## 4. 决策依据备忘

- **揭示时刻放主菜单而非选关页**：2026-09-28 用户拍板「L2 通关后引导玩家回主页选择升级」；主菜单是每次必经 hub，变强商店按钮与开始冒险并列，位置天然醒目。
- **隐藏而非灰锁定**：玩家尚不知道矿石是什么时，锁定按钮没有信息量只是噪音；「新东西出现」本身即体感断层（玩法解构方法论 §5 质量分）。
- **L1 meta=false**：保护教学算术与无命状态（§2-A1），并与 L2「盲测冷启动确定」口径一致。

---

## 5. 回归清单（新档冷启动 walkthrough）

1. 闪屏显示「v0.1 · 外部试玩版」→ 主菜单：**无签到弹窗**；只有 开始冒险 + 设置；无商店、无总矿石
2. 开始冒险 → **直接进选关页**（4 关卡片，无矿石行；1-1 带 [新]；无 1-5）
3. 打 L1：HUD **无矿石标签**；通关结算显示「首通奖励 +200 矿」、无分享按钮 → 「返回选关」→ 1-2 解锁
4. 打 L2：结算首通行出现「🎉 新功能解锁: 变强商店」+ 主按钮「**返回主页**」→ 主页：变强商店高亮「新 · 」+ 总矿石 400
5. 首次打开商店（高亮消除、标志置位）→ 购买 2–3 条 Lv1 轨 → 开始冒险 → 选关页**矿石行出现且高亮**「矿石能变强。」
6. 进 L3：HUD 矿石标签**显示**；起始资金 = 300 + 局外起始金币加成（进场即见）；1-3 带 [新]
7. 重打 L2（已解锁后）：无解锁提示行、按钮恢复「返回选关」；进过 L3 后主页/选关**高亮消失但入口保留**
8. 设置页：无音频组、无「重看教程」；全屏/网格线/震屏生效；清档 → 回到第 1 步冷启动状态
9. 防呆：未解锁状态下以任意路径调 `ore_shop.open()` 均不生效
10. 不可达验证：1-5、ch2+、每日挑战、签到、挖矿档案、ChapterSelect 均无入口；F5 无效

---

## 6. 遗留（不在本次范围）

- **第五关**：设计与实施（用户已确认必做，延后；做时配 `is_playtest = true` 即自动入列）
- **每日挑战**：本次仅收起；规则是否按试玩计分改造、入口去留，发行候选阶段定
- **反馈入口**：执行计划第 5 步要求，随发行候选包补
- **试玩终点提示**：打通 4 关后是否加「试玩版到此结束，感谢游玩」行——可选项，盲测前定

---

## 7. 通关后商店聚光引导（2026-10-07 增补，已实装）

§3 的静态揭示（金色高亮+「新」角标）是弱信号，玩家点「下一关」可整体跳过商店。本次补齐通行做法的第三板斧——**带玩家走完全流程的聚光引导**（吸血鬼幸存者/哈迪斯类首访强制引导），终点点在完成一次购买。

### 流程（验收基准）

1. L2 胜利结算页：聚光「返回选关」按钮，气泡「矿石攒下了。点『返回选关』，去花掉它。」（12s 未动换提示）
2. 选关页：聚光金色「升级」按钮「新解锁的『升级』：花矿石，永久变强。」
3. 矿石商店：聚光收紧到第一个可买行（起始金币 50 矿，首通手上 ≥400）的购买按钮「买一件强化。起始金币最便宜。」
4. 完成购买 → 引导无声收场，`tutorial_done_shop_guide` 落盘，永不重播

脱轨自愈（弱引导，压暗层不挡点击）：点「下一关」直进 L3 → 引导随进关收掉，进过 L3 窗口永久关闭；商店开着没买关掉 → 聚光退回当前屏「升级」按钮；跳过/ESC → 视为看过；中途逛去主菜单/重启游戏 → 下次出现在窗口期内的屏即重新聚光（主菜单走「升级·新」按钮）。

### 实现要点

- `scripts/shop_guide_director.gd`：换屏自愈式驱动——结算/选关/主菜单每换一屏重注入该屏步骤（同 flag key 走 guide `_run_level` 直通，L1 双段同机制）；购买步骤的聚光目标在商店 `open()` 后一帧改写为第一个未禁用 `BuyButton`（行动态创建，不能提前引用）。
- `TutorialGuide` 增加可选 `flag_key` 参数（局外流程绕开陈旧的 `current_level_id` 键），并在 UILayer 中挪到菜单区面板之后（原树序在不透明全屏菜单之下会被整层盖住，同 OreShop 挪层先例）。
- 触发窗口与 §2 金色高亮同口径：`is_level_cleared(ch01_s02) && !has_entered_level(ch01_s03) && !tutorial_done_shop_guide`；键已注册 `settings_manager.DEFAULTS`，设置「重看教学」一并重置（重置后仍需处于窗口期才会重播）。
- 顺带修复前置 bug：`main_menu.refresh()` 不刷矿石行 + `mark_cleared` 不发信号 → 首通 L2 后回主菜单「升级」按钮陈旧隐藏；现 `refresh()` 补调 `_refresh_ore()`。结算提示行「回主菜单看看」与实际去向（返回选关）不符，改「新功能解锁：升级商店」。
