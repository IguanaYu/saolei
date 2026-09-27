# 扫雷变种机制扫描：世界上的扫雷游戏都改了什么

> **文献型扫描（teardown-lite）**。拆解日期：2026-08-22。
> 目的：为"扫雷+机器人自动化"增量游戏挖掘**扫雷独有的可设计维度**提供先例证据——哪些维度已被验证好玩、哪些被验证是坑。
> 维度标签：(a)数字/信息规则 (b)雷的身份与语义 (c)确定性与猜测处理 (d)棋盘形态/领土 (e)风险与容错 (f)动作集 (g)元层（任务/养成/对战）
> 证据等级：[L1]单一评论 [L2]多来源社区共识 [L3]wiki/攻略含具体数值 [L4]开发者/官方自述

---

## 1. Microsoft Minesweeper（Win8/10）Adventure 模式 —— 官方的"扫雷 RPG 化"标本

**改动维度：(b)(d)(e)(f)(g) 全上，唯独 (a) 数字规则基本没动。**

具体机制：
- 地下迷宫连续棋盘，英雄从地表走向地心，**棋盘变成有空间纵深的"关卡领土"**（d）。地形类型包括水、岩浆、冰等，各有特殊效果（岩浆烧血、冰面滑行等）[L2]
- 敌人（骷髅、蝙蝠等）在棋盘上游荡，踩到会掉血；**生命值（hearts）**系统替代了"踩雷即死" [L2]
- 道具/武器掉落：镐、铲、地图、蜡烛等，可探测/规避/清除危险格——**在"开格/标雷"之外扩展了动作集**（f）[L2]
- 战利品（金币/宝箱）作为过关奖励，接 Xbox 成就元层（g）
- Xbox 官方描述："collect loot and uncover weapons to help you defeat enemies and avoid hazards" [L4，官方页面]

评价：
- 社区普遍认为这是"官方扫雷最大胆的一次改造"，前几关免费后收费（Win8 时代 Microsoft Casual Games 的广告/付费模式）被骂得多，玩法本身评价尚可 [L1-L2]
- speedrun.com 有 Adventure 模式速通榜（有玩家 <15 秒破关），说明其规则深度有限、可被高度优化 [L3]

**对本项目的证据价值**：官方验证了"雷→怪物/危险格 + 生命值 + 道具"这条 RPG 化路线**可行但不惊艳**；核心问题在于它没改数字规则（a），逻辑层仍是原版扫雷，RPG 层是贴皮。真正被记住的改造都动了 (a) 或 (c)。

来源：
- https://support.xbox.com/en-US/game/microsoft-casual-games/microsoft-minesweeper/support/what-is-adventure-mode-and-how-do-i-play-it-in-microsoft-minesweeper
- https://www.trueachievements.com/game/Microsoft-Minesweeper/walkthrough
- https://gaming.stackexchange.com/questions/97856/how-many-levels-are-there-in-minesweeper-adventure-mode
- https://speedrun.com/win8mine

---

## 2. Tametsi —— "无猜测"路线的巅峰，扫雷作为纯逻辑谜题

**改动维度：(a)(c)(d)。**

具体机制：
- 100 个手工设计关卡 + 60 个奖励关，**每一关保证纯逻辑可解、零猜测**（no-guess）[L3，Steam 讨论区与多个评测确认]
- 大量棋盘形态变体：非矩形棋盘、洞、断裂区域（d）；数字格本身有不同类型——有的数字只算正交邻居、有的只算对角、有的是"斜列"计数等（a）[L2]
- 内置笔记系统，玩家可在格子上做标记辅助推理（f 的轻量扩展）[L2]

评价：
- Steam 压倒性好评。典型评价："minesweeper but more logic focused rather than RNG focused. Every level is solved with pure logic, never guessing anything." [L2]
- Electron Dance 称其为 "Hexcells killer"：更难、关卡更多、因有笔记支持而不令人崩溃 [L1]
- 社区常拿它当"好扫雷"的黄金标准："Tametsi only contains no guess minesweeper puzzles, the logic was sound" [L2]

**对本项目的证据价值**：**(c) 确定性处理是被验证最好玩的维度之一**。扫雷玩家社区对"被迫 50/50 猜"的怨恨是结构性的——把确定性做成承诺（保证可解）本身就是卖点。增量游戏的"机器人自动化"天然与确定性承诺互补：机器人能算的，正是玩家不必猜的。

来源：
- https://steamcommunity.com/app/709920/discussions/0/1743352529774852917/
- https://electrondance.com/puzzleworks-2-tametsi/
- https://www.reddit.com/r/Minesweeper/comments/1eavny4/meta_no_guess_minesweeper/
- https://thinkygames.com/games/tametsi/

---

## 3. Hexcells 系列 —— 信息规则扩展的教科书

**改动维度：(a)(c)(d)。**

具体机制：
- 六边形棋盘，每格 6 邻居（d）[L3]
- 四类新信息规则（a）[L3，Steam 讨论区规则帖 + Archipelago wiki]：
  1. **黑格上的数字**：相邻蓝格（"雷"）计数——同原版但邻接关系变了
  2. **花括号 `{2}`**：相邻的雷必须**连续成串**（连通约束）
  3. **连字符 `-2-`**：相邻的雷必须**互不连通**（反连通约束）
  4. **棋盘外的行/列数字**：整行/整列雷的总数（全局约束）
- 全部关卡手工设计、纯逻辑可解（c）[L3]

评价：
- 系列口碑极佳（Hexcells / Plus / Infinite），是"扫雷-like 但更好"的最早大众证据 [L2]
- 但社区共识是 Tametsi 更难更深——Hexcells 的缺点是**信息给得太足**，中后期变成机械填格（"做题感"）[L1-L2]

**对本项目的证据价值**：**(a) 是扫雷最富饶的改造维度**。连通/反连通、行总数这类"元信息"约束是三消/烹饪完全没有的东西——它们直接改变推理链条的形状。警示：信息给太足会退化成填空题，好版本要制造"远距离约束联动"。

来源：
- https://steamcommunity.com/app/265890/discussions/0/1318836262647289364/
- https://archipelago.miraheze.org/wiki/Hexcells_Infinite
- https://www.newgamenetwork.com/article/1160/hexcells-infinite-review/

---

## 4. Globesweeper —— 棋盘拓扑改造（球面/立方体/五边形）

**改动维度：(d)，附带 (e)。**

具体机制：
- 棋盘铺在球面上，六边形格（后期作 Hex Puzzler 转为纯关卡制）；也有立方体、含五边形格的模式 [L2-L3]
- 六边形意味着每格最多 6 邻居 → 最大数字从 8 降到 6，概率结构改变 [L3]
- Hex Puzzler（续作）转向手工关卡、无猜测 [L2]

评价：
- PCWorld："February's most addictive game" [L1]
- Rock Paper Shotgun 的批评极具参考价值："It's not a terrible game! But it's a terrible **puzzle** game. Because Minesweeper involves guessing, and that's fundamentally bad puzzle design." [L1]——骂的还是猜测，不是球面
- Steam 用户："superb level design, mechanics that make sense" [L1]

**对本项目的证据价值**：(d) 拓扑改造能提供新鲜感且被接受，但**单靠形态改动撑不起长线**——Globesweeper 被批评的仍然是原版扫雷的猜测问题。形态改动是调味，不是主菜。

来源：
- https://www.pcworld.com/article/403374/globesweeper-review.html
- https://www.rockpapershotgun.com/globesweeper-review
- https://store.steampowered.com/app/1121530/Globesweeper_Hex_Puzzler/

---

## 5. Mamono Sweeper（魔物扫雷）—— 数字语义 RPG 化，最接近本项目"雷有身份"的先例

**改动维度：(a)(b)(e)(f)。**

具体机制 [L3，MZRG 攻略页 + Jay is Games 评测，数值具体]：
- 雷变成 1–9 级怪物；**格子上的数字 = 周围怪物等级之和**（不再只是雷数）——数字语义从"计数"变成"加权和"，同一数字对应多种怪物组合，信息变模糊但更可推理
- 玩家有等级和经验：打死 1 级怪得 1 XP，每升一级 XP 翻倍；**玩家等级 ≥ 怪物等级时可以安全点击（战斗胜利）**，否则受伤
- 踩到低级怪不再即死，而是"打怪吃伤害"——即死改成 HP 容错（e）
- 胜利条件：清光所有怪物（而不是"开所有安全格"）
- 有 HUGE 版（大棋盘）与 HX 版（**实时多人对战**，mamono.nmans.io）：多人同棋盘竞速打怪升级（g）

评价：
- Jay is Games、Kill Ten Rats 等均好评，网页游戏时代流传度广；"从 1 级怪吃起逐步升级"的节奏被明确称赞——**它把扫雷的'开局随机点'变成了有目的的成长开局** [L2]

**对本项目的证据价值**：这是"雷的身份/等级"维度的最佳验证。数字=等级之和是绝妙的一笔：保留了数字推理，但让"哪个雷"变得重要（先吃弱雷）。升级门槛（等级≥怪级）天然形成推进节奏，与增量游戏的成长曲线同构。**强烈推荐作为核心参考**。

来源：
- https://mzrg.com/mines/mamono.shtml
- https://jayisgames.com/review/mamono-sweeper.php
- https://www.killtenrats.com/2015/05/17/mamono-sweeper/
- https://mamono.nmans.io/

---

## 6. 14 Minesweeper Variants（1 & 2）—— 数字规则变体的系统化枚举

**改动维度：(a) 的极致，几乎只改 (a)。**

具体机制 [L3，Codex Gamicus wiki 列全表]：
- 一代 14 个变体：Vanilla / Quad / Multiple / Liar（数字会说谎）/ Wall（每列有墙限制雷位）/ Connected（雷须连通）/ Fort / Oneway / Shield / Cross / Partition / Eyesight / Triplet（雷不得三连）等
- 设计原则两条（Thinky Games 概括）：**给原规则加新约束**，或**改变数字的含义** [L2]
- 2024 年出续作，全换 14 条新规则，证明"纯规则变体"有持续市场 [L3]
- 开发者 Artless Games 自述骑士步变体（Knightsweeper）被砍——社区实测太难/不好玩 [L4，开发者推特]

评价：
- 口碑良好（"cursed variants"视频系列在 YouTube 走红），社区尤其喜欢 Liar、Triplet 这类"改变推理方向"的规则 [L2]

**对本项目的证据价值**：**(a) 维度几乎无穷**，且已被验证可独立支撑商业产品（两作）。"数字会说谎""雷须连通""雷不得三连"这类规则零美术成本、纯逻辑收益，非常适合增量游戏做"规则升级树"。被砍的骑士变体提示：**邻接关系改太狠会摧毁玩家的直觉缓存**。

来源：
- https://gamicus.fandom.com/wiki/14_Minesweeper_Variants
- https://thinkygames.com/games/14-minesweeper-variants/
- https://steamcommunity.com/sharedfiles/filedetails/?id=（成就攻略）

---

## 7. Minesweeper Flags（Xbox 360）—— 对战模式：把"躲雷"反转成"抢雷"

**改动维度：(b)(c)(g)。**

具体机制 [L3，Wikipedia + TrueAchievements]：
- 目标反转：不躲雷，而是**抢先找到雷并插旗占领**；4 人轮流开格，先拿到多数旗（如 26/51）者胜
- 完全回合制、零运气？不——**找雷仍靠推理，但对手开出的数字是共享信息**，读牌/抢位置成为博弈层（c 的对战化）
- TrueSkill 排位、战绩统计（g）

评价：
- TrueAchievements："Flags 是整个包里唯一真正的新体验" [L1]
- IGN 差评："The only thing more boring than playing Minesweeper…"——节奏慢、当付费产品单薄 [L1]
- OXM 6.5/10：有价值但不惊艳 [L1]

**对本项目的证据价值**：**(b) 语义反转（雷从惩罚变奖励）是对战扫雷的核心创新且被认可**，但纯回合制轮流点击的呈现方式拖垮了节奏——被骂的是包装不是机制。QQ/微信扫雷对战基本同构（抢标雷积分）。启示：语义反转好玩，回合制无聊；异步/实时更好。

来源：
- https://en.wikipedia.org/wiki/Minesweeper_Flags
- https://www.ign.com/articles/2009/02/12/minesweeper-flags-review
- https://www.trueachievements.com/game/Minesweeper-Flags/reviews

---

## 8. minesweeper.online / World of Minesweeper —— 元进度层怎么加

**改动维度：(g)，玩法本体不动。**

具体机制 [L3，官方 help 页]：
- 每日任务 ×3 + 赛季任务 + 事件积分（完成越快分越高，随机掉落）→ 赛季通行证式进度
- 成就体系（官方明说部分成就就是"让玩家感到投入"）；货币（gems/minecoins）、装备、段位、奖杯
- Reddit 有专门"grinding 攻略"：约 3500 进度点买稀有引擎（engine），用经验/宝石加速——**存在"用道具缩短劳动"的付费/资源回路** [L1]

评价：
- 该站是西方最大扫雷社区之一，日活稳定，元层被接受 [L2]；但无证据表明元层本身"好玩"，更像是留存工程

**相邻证据：World of Mines!（iOS）/ Geo Minesweeper worldmap**：把地球/国家地图铺成扫雷棋盘，清完一国即"占领"一国（d+g 的领土化）[L2]

**对本项目的证据价值**：(g) 元层在扫雷上已被大规模验证为**可行的留存手段而非乐趣来源**。领土/地图占领（World of Mines）是 (d) 与 (g) 结合的轻量先例，与"机器人自动化占地"的幻想兼容。

来源：
- https://minesweeper.online/help/quests
- https://minesweeper.online/help/achievements
- https://minesweeper.online/help/events
- https://www.reddit.com/r/Minesweeper/comments/1r2wfgq/a_brief_guide_to_grinding_on_world_of_minesweeper/
- https://apps.apple.com/us/app/world-of-mines/id1435138884

---

## 9. 其他值得记录的变体（简条）

- **Heptaveegesimal 拼图日历**：特殊格类型如 "Large Rock"（周围 8 格中恰好 3 对角+3 正交安全）、"Cactus"——**格子本身携带复杂约束**，(a) 的进一步碎片化 [L3]
- **Cursed variants 社区视频系列**（YouTube）：光环雷、负数雷、无理数雷、虚数雷、幽灵雷（Locksweeper）等——证明玩家对"雷的身份"实验有强烈观赏/把玩兴趣 [L1-L2]
- **Orbiboom**：3D 球面含五边形格，(d) 的社区延续 [L1]
- **Crossmines / Minesweeper X / Minehunt**：被 Wikipedia 记录的早期变体，方向是多种雷尺寸/形状与扩展难度 [L2]
- **未找到"女神异闻录扫雷"的可靠资料**（ Persona 系列无扫雷玩法；疑为记忆混淆），不纳入。

来源：
- https://heptaveegesimal.com/2018/advent-calendar/
- https://www.youtube.com/watch?v=BASZIQEWYpg
- https://en.wikipedia.org/wiki/Minesweeper_(video_game)
- https://www.reddit.com/r/Minesweeper/comments/1i7b2au/orbiboom_a_3d_spherical_minesweeper_game/

---

## 汇总矩阵

| 变种 | a 数字规则 | b 雷身份 | c 确定性 | d 棋盘/领土 | e 容错 | f 动作集 | g 元层 | 关键教训 |
|---|---|---|---|---|---|---|---|---|
| MS Adventure | — | ✔(怪/地形) | — | ✔(纵深迷宫) | ✔(生命) | ✔(道具) | ✔ | 官方最大胆但逻辑层没动，RPG 层似贴皮 |
| Tametsi | ✔ | — | ✔(零猜测承诺) | ✔ | — | ✔(笔记) | — | 无猜测本身是卖点 |
| Hexcells | ✔✔ | — | ✔ | ✔(六边) | — | — | — | 信息规则最富饶；给太足变填空 |
| Globesweeper | — | — | ✘(仍可猜，被RPS骂) | ✔✔(球面) | — | — | — | 形态是调味不是主菜 |
| Mamono Sweeper | ✔(等级和) | ✔✔ | — | — | ✔(HP) | ✔(战斗) | ✔(HX多人) | 数字=等级和 + 等级门槛，最接近本项目 |
| 14 MV 1/2 | ✔✔ | ✔(部分) | ✔ | — | — | — | ✔(成就) | 纯规则变体可撑两作；邻接改太狠翻车 |
| Minesweeper Flags | — | ✔(雷=得分) | ✔(共享信息博弈) | — | — | ✔(插旗占领) | ✔ | 语义反转好玩，回合制节奏被骂 |
| minesweeper.online | — | — | — | — | — | — | ✔✔ | 元层=留存工程，非乐趣 |

## 与"自动化/助手"设计的交集（专项回答）

- **没有任何主流扫雷变种把"求解器/自动扫雷"做成玩法核心**——检索 solver/hint/auto-solve 只命中研究工具与泛谜题提示理论，无商业先例。这是一个**空位**。
- 间接证据：Tametsi 的笔记系统（人工辅助推理）、MS Adventure 的地图/蜡烛道具（消除不确定性的消耗品）、minesweeper.online 的 engine 装备（数值加速）——三者都是"降低玩家推理负担"的不同形态，均被接受。
- 提示系统研究的共识警示：明示的"Get Hint"按钮会被玩家感知为作弊，降低完成满足感（cjleo.com、Unity 论坛讨论）→ 若做机器人助手，应把自动化包装为**生产力/经济增长**而非"替你解题"，让玩家保留"我推理得来"的归因。

## 结论：维度验证总表

**已验证好玩**：(a) 数字信息规则变体（Hexcells/14MV/Tametsi/Mamono，最强维度）；(c) 无猜测承诺（Tametsi/Globesweeper 反例互证）；(b) 雷的身份化+数字=等级和（Mamono）；(b) 语义反转抢雷（Flags 机制层）。
**已验证是坑**：保留可猜测却自称谜题（Globesweeper 被 RPS 骂）；邻接关系大改摧毁直觉（Knightsweeper 被开发者自砍）；回合制轮流点击的对战呈现（Flags 被骂无聊）；RPG 层贴皮不改逻辑层（MS Adventure 平淡）。
**无人做过**：把扫雷求解器/自动化本身作为玩法与经济核心。
