# 扫雷挖矿 · V2 整套视觉素材

这套素材独立放在 `visual_v2/`，与旧版 `assets/` 分开。当前游戏场景和脚本的贴图引用已指向这里；旧素材没有被覆盖。

## 目录

| 位置 | 用途 |
| --- | --- |
| `concepts/` | 已选定方向的局内、主菜单、结算三张整体概念图与提示词 |
| `source/` | 内置 image_gen 生成的高分辨率矿洞背景、四类机器人和徽记，保留透明原图 |
| `runtime/backgrounds/` | 主菜单、选关和局内共用的矿洞背景 |
| `runtime/tiles/` | 4 套岩壁与地面、边缘、棋盘框、基地、旗帜、矿脉、坍塌等像素素材 |
| `runtime/robots/` | 4 类机器人，每类待机、移动两张图 |
| `runtime/fx/` | 旗面、灰尘、鼠标、棋盘角框、岩屑和金币闪点，供后续局内动效接入 |
| `runtime/ui/` | 金属面板、按钮状态、资源和功能图标、全局 Godot 主题 |
| `review/` | 实机菜单、局内、结算、功能页与特效帧的检查截图 |

运行时共有 **68 张 PNG** 和一份 `ui/ui_theme_v2.tres`。视觉基调为深灰岩层、铜制结构、琥珀矿光、青色设备灯、少量红色警示。四套棋盘环境为 `V2`（勘探）、`V2C`（蓝晶）、`V2M`（苔藓）、`V2R`（砂岩），普通关按章节组分配，每日挑战按日期轮换。

## 后续接入入口

- **开格、连锁、插旗与卸货动效**：按 [局内交互动效设计 v1](../docs/active/局内交互动效设计-v1.md) 接入事件、播放时序和并发限制。
- **鼠标光标、棋盘悬停与放置提示替换**：按 [局内交互视觉资产盘点 v1](../docs/active/局内交互视觉资产盘点-v1.md) 接入对应素材、热点及合法落点判断。

这批图片和设计稿已备好，游戏场景与输入代码尚未引用新素材。

## 插旗特效帧（待接入）

- `runtime/fx/flag_plant_sheet.png`：3 帧横排，每帧 **28×28**；顺序为旗面压缩、反弹、静止。第 3 帧与现有 `tiles/special_flag.png` 完全一致。旗杆和底座三帧不动；落旗的整体下移请在场景中用 Tween 实现。
- `runtime/fx/flag_dust_sheet.png`：3 帧横排，每帧 **16×12**；顺序为触地、扩散、消散。相对格子图像左上角放在 **(1, 16)**，换算成当前 `Cell` 节点本地坐标为 **(-13, 2)**。灰尘在旗子图层上方播放，结束后移除。
- `review/fx_preview.png`：两组特效帧叠在 V2 岩壁上的 8 倍最近邻预览。运行 `python visual_v2/review/render_fx_preview.py` 可重新生成。

其余 8 张鼠标与交互图的尺寸、热点和用途见 [局内交互视觉资产盘点 v1](../docs/active/局内交互视觉资产盘点-v1.md)，放大预览为 `review/interaction_fx_preview.png`。运行 `python visual_v2/review/render_interaction_preview.py` 可重新生成预览。

接入时按 [局内交互动效设计 v1](../docs/active/局内交互动效设计-v1.md) 的收益事件与并发限制实现；目前场景尚未引用这些新图。只重做特效时运行 `python visual_v2/build_fx.py`；该脚本不会改写地形或其他现有素材。

## 重新生成和导入

1. 在项目根目录运行 `python visual_v2/build_runtime.py`。此脚本从 `source/` 提取机器人和徽记，并绘制尺寸精确的棋盘、UI 素材，只写入 `visual_v2/runtime/`。
2. 再运行 `python visual_v2/build_fx.py`，从当前静态旗图生成匹配的旗面帧，并绘制鼠标与交互小图。仅修改特效时只需运行这一步。
3. 新增或更新 PNG 后，先用项目约定的 Godot 路径运行 `--headless --import`，再启动游戏。

注意：当前有已单独调整过的地形图；完整运行 `build_runtime.py` 会重新写入这些图。特效迭代只运行 `build_fx.py`。

`review/shot_runtime.gd` 与 `review/shot_pages.gd` 仅用于截图验收。运行时截图脚本直接装配预设棋盘，不记录关卡结果或改写存档。
