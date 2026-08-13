# 项目文档索引

扫雷挖矿项目的所有设计、分析、调研、归档文档都在 `docs/` 下。本文件是唯一入口。

## 目录结构

| 目录 | 用途 | 何时往这里放 |
|------|------|------|
| [active/](active/) | 进行中的主线文档与现行设计 | 还在推进或仍在被频繁查阅的"现行工作" |
| [reference/design/](reference/design/) | 项目自身的设计分析与方法论 | game-design pipeline 产出的拆解/分析、本游戏用到的设计方法论 |
| [reference/research/](reference/research/) | 跨游戏调研 | 对标产品调研、跨游戏数值/机制调研 |
| [archived/](archived/) | 历史归档 | 已被新方案取代、保留作为历史快照 |

根目录仍保留：`claude.md`（项目指令）、`todo.md`（任务清单）、`sessions/`（对话纪要）。

---

## active/ — 现行主线与设计

### M1 可宣传里程碑（当前主线）
- [M1-可宣传里程碑-开发主线.md](active/M1-可宣传里程碑-开发主线.md) — 第一个可宣传里程碑（30s 宣传视频 + 上架收愿望单）；四 Sprint S1→S4

### T2 主线（M1 后续推进）
- [T2-主线开发文档.md](active/T2-主线开发文档.md) — T2 阶段入口；五件套中 P15/P16 已推到 M1 之后、P14 压缩进 M1.S3.5
- [P0改造方案-微信小游戏体感.md](active/P0改造方案-微信小游戏体感.md) — T2 五件套核心方案依据
- [P13-关卡章节系统-主线任务.md](active/P13-关卡章节系统-主线任务.md) — 60 关/12 章；已实施完成，作 M1 内容容器

### 核心设计
- [游戏设计文档.md](active/游戏设计文档.md) — 项目核心设计文档（90 秒冲分 + 机器人产业链）
- [实现设计文档_v0.2.md](active/实现设计文档_v0.2.md) — v0.2 实现细节（P6-P11）
- [数值模型_v0.1.md](active/数值模型_v0.1.md) — 5 个数学子模型（产出/价格/目标分/升级成本/失败容忍）

### 节奏与里程碑
- [数值节奏规划-v0.1.md](active/数值节奏规划-v0.1.md) — 60 关/12 章整体节奏（已被 P13 落地）
- [里程碑路线图.md](active/里程碑路线图.md) — M1-M5 路线图

---

## reference/design/ — 项目设计分析与方法论

### game-design pipeline 七件套（2026-08-11 同时产出）
- [design-brief.md](reference/design/design-brief.md) — Layer 1 战略张力（"慢思考 × 快节奏"）
- [teardown-card.md](reference/design/teardown-card.md) — 开发中项目自拆解
- [gameplay-analysis.md](reference/design/gameplay-analysis.md) — 玩法循环多时间尺度分析
- [economy-analysis.md](reference/design/economy-analysis.md) — 六框架经济分析
- [uiux-analysis.md](reference/design/uiux-analysis.md) — 六框架 UI/UX 分析
- [feature-benchmark.md](reference/design/feature-benchmark.md) — 局外解锁链跨游戏对比
- [competitive-report.md](reference/design/competitive-report.md) — 综合决策报告（synthesis）

### 方法论
- [关键设计要点-数值机制与理论.md](reference/design/关键设计要点-数值机制与理论.md) — 数值机制与理论框架
- [通用游戏数值节奏骨架方法论.md](reference/design/通用游戏数值节奏骨架方法论.md) — 跨类型宏观节奏方法论
- [里程碑规划方法论.md](reference/design/里程碑规划方法论.md) — 里程碑规划理论依据
- [UI_UX改进方法论.md](reference/design/UI_UX改进方法论.md) — UI/UX 改进方法论

---

## reference/research/ — 跨游戏调研

- [对标调研-微信小游戏循环.md](reference/research/对标调研-微信小游戏循环.md) — 微信小游戏"卡关-升级-碾压"循环对标
- [调研_同类游戏数值.md](reference/research/调研_同类游戏数值.md) — 19 款短局制/微信/挖矿游戏数值
- [调研资源提炼库.md](reference/research/调研资源提炼库.md) — 调研文章核心提炼合集
- [通用数值节奏骨架/](reference/research/通用数值节奏骨架/) — 4 套节奏骨架提炼材料（json + md 双版本）

---

## archived/ — 历史归档

- [改造计划-v0.1.md](archived/改造计划-v0.1.md) — T2 之前的诊断快照，"决策点 1-6" 已被 P13 + 微信体感五件套取代
