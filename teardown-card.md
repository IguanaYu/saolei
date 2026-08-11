# 扫雷挖矿 · Teardown Card（开发中项目自拆解）

> **拆解类型**：Self-teardown of dev project（非参考游戏）
> **证据等级**：L1 = 设计文档意图 / L2 = 代码实现实际值 / L3 = 规划文档计划
> **拆解日期**：2026-08-11
> **play-time**：N/A（开发中，无实际游玩数据；本卡基于设计文档 + 代码源码）
> **partial 标记**：⚠️ 本卡为 partial teardown，Channel 1（实际录像）和 Channel 6（实际情绪体验）缺失，用设计意图替代

---

## Channel 1 - Core Loop（核心循环）

### 30 秒级动作循环

```
玩家点击格子（左键开格 / 右键标雷 / 双击和弦）
   ↓
即时反馈：开格 +1钱+1分 [L2 main.gd:247-248]
         标对雷 +5钱+5分 [L2 main.gd:253-254]
         标错雷 -3分 [L2 main.gd:262]
   ↓
连锁展开（0 格自动展开周围）
   ↓
机器人每 2s 自动执行确定操作 [L2 game_state.gd:201-208]
```

**juice 设计意图** [L1 §11.4]：
- 开格跳字（+1 钱 +1 分）
- 矿脉金色发光脉动
- 矿工卸货时基地短暂闪光 + 分数飞出
- 充能塔充能时光束特效（未实现 [L2 game_state.gd:48]）
- ⚠️ 实际 juice 实现程度未验证（无游玩录像）

### 5 分钟级（单局）

**当前 90s 流程** [L2 game_state.gd:9]：

| 时间段 | 玩家行为 | 系统状态 |
|---|---|---|
| 0s | 放置第一个基地（3×3 预开） [L2 main.gd:173-181] | game_phase = placing_base |
| 0-20s | 手点开格攒钱，目标攒到 50 买第一个 opener | 钱从 100 起 [L2 game_state.gd:80] |
| 20-50s | 买 opener/marker，机器人接管确定性操作 | 产业链未启动 |
| 50-90s | 攒到 80 买 detector？多数情况来不及 | detector 3s 检测 + miner 60 块 + 运输时间 |
| 90s | timeout 结算 | 积分 ÷ 10 = 矿石 [L1 §10.1] |

**关键问题** [L1 关键设计要点 §2.1]：90s 只够走完"前期手动"阶段，产业链雪球跑不起来。

### 单局日志（设计意图模拟）

```
[0s]   钱:100 分:0 命:3
[20s]  钱:130 分:30 命:3  买 opener(50) 后
[50s]  钱:160 分:60 命:3  opener 开了 30 格，marker 标了 4 雷
[90s]  钱:200 分:100 命:3 timeout，矿脉产业链没启动
[结算] 矿石 +10 (100分÷10)
```

⚠️ 以上为设计意图推演，非实际游玩捕获。

---

## Channel 2 - UI/UX Flow（界面与操作流）

### 屏幕清单 [L2 代码场景结构]

| 屏幕 | 文件 | 状态 |
|---|---|---|
| 主菜单 MainMenu | scripts/ui/main_menu.gd | ✅ |
| 章节选择 ChapterSelect | scripts/ui/chapter_select.gd | ✅ P13 |
| 关卡选择 LevelSelect | scripts/ui/level_select.gd | ✅ P13 |
| 游戏 HUD | scripts/ui/hud.gd | ✅ |
| 商店 Shop | scripts/ui/shop.gd | ✅ |
| 升级面板 UpgradePanel | scripts/ui/upgrade_panel.gd | ✅ |
| 结算面板 ResultsPanel | scripts/ui/results_panel.gd | ✅ |

### HUD 布局 [L2 hud.gd + L1 §11.1]

```
+----------------------------------------------------+
| 钱:150  积分:230  命:3/3  时间:0:42  矿石:35      |
| 目标: 标 5 雷 (3/5)                                |
| [空闲提示] / [阶段提示] / [Toast]                   |
+----------------------------------------------------+
|                                                    |
|              [16 × 16 游戏地图]                    |
|                                                    |
+----------------------------------------------------+
| [opener¥50] [marker¥50] [detector¥80] [miner¥60]  |
| [建基地¥80] [无人机¥100]              [升级面板]    |
+----------------------------------------------------+
```

**⚠️ Bug 发现** [L2 hud.gd:57]：`lives_label.text = "命: %d/3"` 硬编码 `/3`，但 `start_lives` 升级后实际 lives 可达 4-5，HUD 显示会不一致。

### 高频操作流

**流 1：买机器人**
1. 点商店按钮 -> 进入放置模式 [L2 main.gd:186-195]
2. 鼠标移到地图已开格子 -> 光标变手型
3. 左键点击 -> 机器人生成 [L2 main.gd:222-235]
4. 快捷键 1-4 可跳过商店点击 [L2 main.gd:152-170]

**流 2：建基地**
1. 点"建基地"按钮 [L2 shop.gd:91-95]
2. 左键点击已开格子 [L2 main.gd:209-220]
3. 右键/ESC 取消 [L2 main.gd:143-148]

**流 3：放第一个基地（开局）**
1. game_phase = placing_base [L2 game_state.gd:13]
2. 点击任意格子 [L2 main.gd:131-136]
3. 基地周围 3×3 预开 -> 游戏开始倒计时 [L2 main.gd:173-181]

### FTUE（首次体验）

**当前 FTUE** [L2 代码]：
- 无教学引导（无 tutorial 脚本/场景）
- 首次进入直接面对主菜单 -> "开始冒险" -> 章节选择 -> 1-1 关
- 1-1 关默认只有 opener + marker [L1 §10.3]
- 靠关卡进度逐步解锁系统 [L3 P13]

**FTUE 缺失风险** [L1 §15.5]：4 种机器人 + 2 种建筑 + 1 技能 + 局外升级，新手可能懵。当前靠"局外解锁机制让系统逐步开放"缓解。

---

## Channel 3 - Number/Economy（数值与经济）

### 货币系统 [L2 game_state.gd + save_system.gd]

| 货币 | 用途 | 来源 | 跨局 | 代码位置 |
|---|---|---|---|---|
| **钱** | 关卡内购买（机器人/建筑/技能） | 玩家行动 + 机器人行动 | ❌ 不保留 | game_state.gd:5 |
| **积分** | 纯成绩 | 玩家行动 + 机器人行动 | ❌ 不保留 | game_state.gd:6 |
| **矿石** | 局外升级解锁 | 积分 ÷ 10 + 首通奖励 | ✅ 永久 | save_system.gd:7 |

### 行动奖励表 [L2 main.gd + L1 §5.3]

| 行动 | 钱 | 积分 | 代码位置 |
|---|---|---|---|
| 玩家开格（安全） | +1 | +1 | main.gd:247-248 |
| 玩家标对雷 | +5 | +5 | main.gd:253-254 |
| 玩家标错雷 | 0 | -3 | main.gd:262 |
| 玩家踩雷 | 0 | 0（-1命） | main.gd:265-268 |
| opener 开格 | +1 | +1 | main.gd:247（同通道） |
| marker 标对雷 | +5 | +5 | main.gd:253（同通道） |
| detector 验证成功 | 0 | +10 | L1 §5.3（代码在 detector_robot.gd） |
| detector 验证失败 | 0 | 0（自爆消失） | main.gd:99-101 toast 提示 |
| miner 卸货（每分矿） | +1 | +1 | L1 §5.3（代码在 miner_robot.gd） |

**关键设计** [L1 §5.1]：钱和积分完全独立。花钱买机器人不会降低积分。

### 价格递增表 [L2 game_state.gd:175-186]

```python
# get_robot_price(robot_type):
#   count = 已购数量
#   base = 50 (opener/marker) / 80 (detector) / 60 (miner)
#   price = base × 2^count × [1.0, 0.75, 0.5][discount_level]
```

| 第 N 个 | opener/marker | detector | miner |
|---|---|---|---|
| 1 | 50 | 80 | 60 |
| 2 | 100 | 160 | 120 |
| 3 | 200 | 320 | 240 |
| 4 | 400 | 640 | 480 |

基地价格 [L2 game_state.gd:133-135]：`80 × 2^base_count`，第 1 个 80，第 2 个 160...

### 升级树 [L2 save_system.gd:11-19]

**⚠️ 代码与设计文档不一致**：

| 升级项 | 设计文档 §10.2 | 代码实现 | 差异 |
|---|---|---|---|
| start_money | 1-5 级，每级 +10 | max 2 级，每级 +50 [L2 game_state.gd:80] | 级数少但每级幅度大 |
| start_lives | 1-3 级，每级 +1 | max 2 级，每级 +1 [L2 game_state.gd:81] | 级数少 |
| global_speed | 1-3 级，-10%/级 | max 2 级，映射到 [2.0,1.5,1.0] [L2 game_state.gd:201-208] | 级数少，幅度 +25-33% |
| expand_zone | 1-3 级，+1 半径 | max 2 级 [L2 save_system.gd:14] | 级数少 |
| start_robot | 1-2 级 | max 2 级 [L2 save_system.gd:15] | 一致 |
| detector 解锁 | 30 矿石 | 章末解锁（ch02_s05） [L2 level_system.gd:68-72] | **机制不同**：设计文档是矿石买，代码是通关解锁 |
| miner 解锁 | 30 矿石 | 章末解锁（ch03_s05） [L2 level_system.gd:68-72] | 同上 |
| tower 解锁 | 50 矿石 | 章末解锁（ch04_s05） [L2 level_system.gd:68-72] | 同上 + 功能未实现 |
| drone 解锁 | 40 矿石 | 章末解锁（ch05_s05） [L2 level_system.gd:68-72] | 同上 |

**关键发现**：解锁机制已从"矿石购买"改为"通关解锁"，但升级树仍是设计文档的矿石购买式。这是 P13 改造的过渡状态。

### 首小时数值节奏（设计意图） [L1 + L3]

| 时间点 | 预期玩家状态 | 证据 |
|---|---|---|
| 0-5 min | 通关 ch01_s01（教学关），得 ~200 矿石首通奖励 | L3 P13 首通奖励 ore=200 |
| 5-15 min | 通关 ch01 全 5 关，累计 ~600 矿石 | L3 P13 重刷 ore=30/关 |
| 15-30 min | 升级 start_money 到 Lv1（花费 ~50 矿石？），回刷碾压 | L2 升级价格代码未找到（upgrade_panel.gd 未读） |
| 30-60 min | 通关 ch02，解锁 detector，矿脉产业链激活 | L3 P13 章末解锁 |

⚠️ 升级面板的具体矿石价格在 upgrade_panel.gd 中，本次未读取。

### 付费/商业化 [L1 §6.2]

当前无商业化。未来计划 IAA + IAP（月卡/战令/去广告）。

---

## Channel 4 - System Map（系统地图）

### 系统清单 [L2 代码结构]

| 系统 | 文件 | 状态 |
|---|---|---|
| 网格/格子 | grid.gd / cell.gd | ✅ |
| 扫雷求解器 | solver.gd | ✅ |
| 机器人管理 | robot_manager.gd | ✅ |
| 机器人基类 | robot.gd | ✅ |
| opener | robots/detector_robot.gd | ✅ |
| marker | robots/miner_robot.gd | ✅ |
| detector | robots/detector_robot.gd | ✅ |
| miner | robots/miner_robot.gd | ✅ |
| 寻路 | pathfinding.gd | ✅ BFS |
| 地图生成 | map_generator.gd | ✅ |
| 关卡数据 | data/level_database.gd | ✅ 60 关占位 |
| 关卡系统 | autoload/level_system.gd | ✅ |
| 存档 | autoload/save_system.gd | ✅ v3 |
| 全局状态 | autoload/game_state.gd | ✅ |
| 商店 | ui/shop.gd | ✅ |
| HUD | ui/hud.gd | ✅ |
| 升级面板 | ui/upgrade_panel.gd | ✅ |
| 主菜单 | ui/main_menu.gd | ✅ |
| 章节选择 | ui/chapter_select.gd | ✅ |
| 关卡选择 | ui/level_select.gd | ✅ |
| 结算面板 | ui/results_panel.gd | ✅ |
| **充能塔** | - | ❌ 功能未实现 [L2 game_state.gd:48 signal 预留] |
| **装备系统** | - | ❌ 未实现 |
| **角色流派** | - | ❌ 未实现 |
| **社交/排行** | - | ❌ 未实现 |

### 系统依赖关系

```
主菜单
  ↓ "开始冒险"
章节选择
  ↓ 选章节
关卡选择
  ↓ 选关卡
游戏主循环
  ├── Grid（格子逻辑）
  ├── RobotManager → Robot → Pathfinding → Solver
  ├── Shop → 购买机器人/建筑/技能
  ├── HUD → 显示状态/目标进度
  └── GameState → SaveSystem（持久化）
       ↓ 游戏结束
ResultsPanel
  ├── 首通奖励 → SaveSystem.add_ore
  ├── mark_cleared → LevelSystem
  │    └── 章末 → unlock_chapter + unlock_module
  └── 返回关卡选择
```

### Meta 进度地图 [L2 level_system.gd + save_system.gd]

```
ch01 (5关) --通关 ch01_s05--> 解锁 ch02 + opener/marker（默认有）
ch02 (5关) --通关 ch02_s05--> 解锁 ch03 + detector
ch03 (5关) --通关 ch03_s05--> 解锁 ch04 + miner
ch04 (5关) --通关 ch04_s05--> 解锁 ch05 + tower（功能未实现）
ch05 (5关) --通关 ch05_s05--> 解锁 ch06 + drone
...
ch12 (5关) --终局
```

**模块解锁链** [L3 P13]：嵌套式（通关解锁，非矿石购买）

---

## Channel 5 - Player-facing Text（面向玩家的文本）

### 游戏自我描述 [L1 §1.1]

> "将经典扫雷与自动化经营 + 产业链管理结合的 90 秒积分制小游戏。"

一句话总结：**扫雷的规则、挖矿的味道、4 种机器人分工协作、矿脉产业链、90 秒冲分。**

### 教学/提示语气 [L2 hud.gd + shop.gd]

| 场景 | 文本 | 语气 |
|---|---|---|
| 开局放基地 | "请放置第一个基地（点击任意格子）" | 指令式 |
| 机器人空闲 | （idle_hint_label） | 提示式 |
| detector 自爆 | "检测失败！机器人自爆了" | 直接、略带挫败 |
| detector 未解锁 | "检测型未解锁（通 2-5）" | 引导式 |
| miner 未解锁 | "矿工未解锁（通 3-5）" | 引导式 |
| 金币不足 | "金币不足" | 直接 |
| 本关禁用 | "本关禁用检测型" / "本关禁用矿工型" | 规则说明 |

**语气特征**：简洁、指令式、无角色个性。没有故事包装，纯功能文本。

### 叙事/Lore

无。游戏没有故事、世界观、角色个性。只有"扫雷挖矿"的机制隐喻。

---

## Channel 6 - Affective Log（情绪日志）

⚠️ **本 channel 为设计意图情绪，非实际游玩体验**。开发中项目无实际玩家数据。

### 设计意图首次心流时刻 [L1 §1.2]

- **预期**：0-20s，玩家手点开格 + 连锁展开的瞬间
- **机制**：连锁展开（0 格自动打开周围）+ 即时跳字反馈
- **风险**：90s 内只能做 20-30 次操作，心流可能还没建立就 timeout

### 设计意图首次挫败 [L1 §15]

- **预期**：detector 自爆（80 块消失）或 timeout 时积分不够
- **风险**：detector 自爆可能直接 rage quit（§15.3 已识别）
- **缓解**：失败给矿石（积分÷10）+ 自爆有 toast 提示

### 设计意图"给朋友看"时刻

- **预期**：产业链第一次跑起来--detector 验证旗子变矿脉（金光）-> miner 走过去采集 -> 运回基地卸货（分数飞出）
- **风险**：90s 内产业链可能跑不起来，玩家根本看不到这个时刻

### 实际情绪验证状态

❌ 未验证。需要实际游玩测试（5-10 名目标用户）才能填充本 channel。

---

## 证据等级汇总

| Channel | L1（设计意图） | L2（代码实现） | L3（规划文档） | 未验证 |
|---|---|---|---|---|
| 1. Core loop | ✅ | ✅ | ✅ | 实际 juice 体感 |
| 2. UI/UX | ✅ | ✅ | - | 实际操作手感 |
| 3. Economy | ✅ | ✅ | ✅ | 实际经济曲线 |
| 4. System map | ✅ | ✅ | ✅ | - |
| 5. Text | ✅ | ✅ | - | - |
| 6. Affective | ✅（意图） | ❌ | ❌ | 实际玩家情绪 |

---

## 关键发现（供下游分析消费）

1. **90s 单局太短** [L1+L2] - 产业链雪球跑不起来，已识别
2. **升级树代码与设计文档不一致** [L2] - 级数少（max 2）、幅度需拉大
3. **解锁机制已改为通关解锁** [L2] - 从矿石购买改为章末解锁，更嵌套
4. **充能塔功能未实现** [L2] - signal 预留但无执行逻辑
5. **HUD 命数显示 bug** [L2 hud.gd:57] - 硬编码 /3，与 start_lives 升级冲突
6. **无 FTUE 教学引导** [L2] - 靠关卡进度逐步解锁缓解
7. **无叙事/角色个性** [L2] - 纯功能文本
8. **detector 自爆挫败感** [L1 §15.3] - 有 toast 但可能不够
9. **60 关数据全占位** [L3 P13] - 内容雷同风险
10. **upgrade_panel.gd 价格未读取** - 本卡缺失，需补充

---

## 修订记录

| 版本 | 日期 | 内容 |
|---|---|---|
| v0.1 | 2026-08-11 | 初版：开发中项目自拆解，6 channel + 证据等级标注 |
