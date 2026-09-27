# V2 生产素材生成规格

生成方式：**内置 image_gen**。`concepts/PROMPTS.md` 保留了三张方向图的完整提示词。以下是生产素材的归档规格，供后续继续扩展同一套风格；它们不是逐字调用日志。

## 共用风格

> Premium crisp pixel art for an underground industrial minesweeper mining game. Charcoal slate caverns, brass and sandstone structures, amber ore glow, restrained cyan machine lights and rare red hazard accents. Hand-placed square pixels, clear silhouettes, limited palette. No words, fake glyphs, smooth gradients, blur, photorealism or watermark. Match the approved gameplay and menu concept images in `visual_v2/concepts/`.

## `mine_cutaway.png`

> Clean reusable 4:3 mine cutaway environment derived from the approved menu direction. Keep the rocky ceiling, shafts, rails, lanterns, ore carts, cyan signal stations and distant red hazard chamber. Leave the center dark and open for game UI. Remove all menu title, buttons, text, signs and interface panels. Full-bleed background, crisp pixel art.

## 四类透明机器人

每张均要求 **单个主体、完整轮廓、真实透明背景（RGBA）**，无地面、投影板、文字和装饰边框。与局内概念图保持像素尺寸感和配色。

| 文件 | 主体要求 |
| --- | --- |
| `robot_opener.png` | 小型履带钻探机，青色屏幕与前置钢钻头 |
| `robot_marker.png` | 小型履带标雷车，醒目的红旗机构 |
| `robot_detector.png` | 小型履带扫描机，紫色探测镜和信号弧 |
| `robot_miner.png` | 小型履带矿工车，琥珀矿石货斗 |

## `menu_emblem.png`

> A compact crossed-pickaxe and square mine-grid insignia, brass and warm gold with small cyan details. Centered, isolated, genuinely transparent RGBA. Crisp pixel art, readable at small UI size, no letters or border panel.
