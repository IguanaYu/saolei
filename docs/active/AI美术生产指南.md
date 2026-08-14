# AI 美术生产指南 · 暖色像素矿洞风

> 本项目（扫雷挖矿）的 AI 美术生产方法论、Prompt 库、工具链。
> 基于 2026-08-13/14 用 CogView-3-flash（生图）+ GLM-4.6V-Flash（识图质检）的实测。

## 一、视觉风格定稿
**暖色像素矿洞风**（V1 决策）。参考：Dome Keeper / Brotato / Mindustry。
暖棕底 + 4 色矿脉（铜/金/翠/红）+ chunky 方块机器人。

## 二、AI 能力边界（实测，非空谈）
| 任务 | CogView | 实测证据 |
|---|---|---|
| 画风 moodboard / 氛围图 | ✅ 能 | style_A 通过 GLM 确认 |
| 单图纯色身体 | ✅ 能（加 `SOLID color`） | 修好 miner 头黄身绿 |
| 精确几何符号 | ❌ 不能 | 钻头→方框、矿车→按钮（~50% 错） |
| seamless 纹理 | ❌ 不能 | seam 分数 105/177（需 <15） |
| 多帧角色一致性 | ❌ 不能 | idle/move 头身肢体全不同 |

## 三、生产 SOP（三条腿分工）
| 元素 | 方法 | 工具 |
|---|---|---|
| 地砖 tile | **AI 抠块拼接**（§4.2，已接入 Cell） | cogview + 切块脚本 |
| 纯背景真无缝 | 代码 wraparound noise | `gen_tiles.py` |
| 数字/符号/网格 | 代码绘制 | Godot Label / PIL |
| 机器人/角色 | AI turnaround sheet → 降色 → 裁帧 | cogview + `postprocess.py` |
| 氛围图/封面 | AI 直出 → 降色 | cogview + `postprocess.py` |
| 质检 | GLM 视觉（非高峰期） | `analyze_image.py` |

## 四、关键方法

### 4.1 后处理降色（最大杠杆）
CogView 直出 **54984 色**假像素画 → `quantize` 到 16-32 色 = 真像素画。比 prompt 优化更大，所有 AI 出图必做。
```
python tmp/postprocess.py <输入> <输出> [颜色数，默认16]
```

### 4.2 地砖抠块拼接法（地砖首选，已接入游戏）
地砖本就该有缝，**不追求 seamless**：
1. CogView 出一张铺好的地砖图（prompt 见 §5.5）
2. 程序化检测网格缝隙：行/列亮度找暗带 → 等距网格 + 局部对齐最暗缝隙行/列（refine ±10px）
3. `crop` 切块 → `resize` 统一（80×80）
4. 游戏里每个已开格子随机锁一块铺设
产物 `assets/tiles/floor_bricks_sheet.png`（12×12=144 块）已接入 `Cell`。
**验证**：用户认可整体效果；seamless 难题被「砖缝天然」绕开。

### 4.3 turnaround sheet（角色一致性）
一次生成前/侧/后多视角设定图（同张图生成 → 天然一致），从中裁帧。比分别生成多帧靠谱。

### 4.4 真 seamless（仅纯背景需求）
wraparound value noise（代码，环面采样），seam 9/11。`gen_tiles.py`。像素风小纹理够用，但用户觉得偏丑，退为打底/纯无缝需求。

## 五、Prompt 库（可抄用）

### 5.1 像素画通用后缀（拼到每个 prompt 末尾）
```
pixel art, 8-bit style, chunky pixels, no anti-aliasing, hard sharp edges,
no smooth gradients, flat cel shading, limited palette (about 10 colors),
crisp hard pixels
```
负向（CogView 无 negative prompt，融入正向）：`no smooth, no gradient, no blurry, no watermark, no text`

### 5.2 单个角色 sprite（已验证纯色有效）
```
[主体+动作], single game character sprite, Dome Keeper Brotato aesthetic,
[§5.1 通用后缀], ONE single cute blocky robot, front-facing, centered,
SOLID [COLOR] body entirely [color] from top to bottom,
[符号形状描述], plain background, no watermark
```

### 5.3 turnaround sheet（角色一致性）
```
character design turnaround sheet of [角色], showing front view, side view,
and back view in a row, all three views of the SAME robot with consistent
size proportions and colors, [§5.1 通用后缀],
arranged horizontally on neutral plain background
```

### 5.4 画风 moodboard（已用，效果通过）
```
Top-down view of a minesweeper-style grid game in play.
A square grid of tiles, some revealed showing numbers, mineral ore veins,
one blocky robot. Warm chunky pixel art style, warm brown earthy background,
4-color mineral ore veins in copper gold emerald ruby, blocky square robot,
Dome Keeper and Brotato aesthetic
```

### 5.5 地砖图（给 §4.2 抠块用）
```
Warm pixel art, top-down view of a paved dirt brick floor for a mine cave.
Flat uniform lighting, bricks with mortar gaps between them forming a grid,
small pebbles and cracks scattered. Dome Keeper Brotato aesthetic,
warm earthy brown palette, chunky pixels, no anti-aliasing
```
> 注：不需要 seamless 约束——要的就是「有缝的地砖」，缝隙正是抠块切割线。

### 5.6 seamless 纹理（⚠️ 不可行，仅记录失败教训）
即使 prompt 死强调 `MUST be seamlessly tileable, edges wrap around` 也无效（seam 105/177）。
→ 改用 §4.2 抠块法 或 §4.4 代码生成，别再试 prompt seamless。

## 六、工具脚本（`tmp/`）
| 脚本 | 作用 | 用法 |
|---|---|---|
| `cogview_cat.py` | 调 CogView 生图 | `COGVIEW_PROMPT="..." COGVIEW_OUT=x.png python tmp/cogview_cat.py` |
| `postprocess.py` | 降色到 N 色 | `python tmp/postprocess.py 输入 输出 [颜色数]` |
| `gen_tiles.py` | wraparound noise 真 seamless tile | `python tmp/gen_tiles.py` |
| `analyze_image.py` | GLM-4.6V-Flash 识图质检（带 429 退避重试） | `python tmp/analyze_image.py 图片 "问题"` |

API key 在 `.env`（`ZHIPUAI_API_KEY`，已 gitignore）。

## 七、坑 & 结论
- CogView 不是 SD，无 negative prompt，**prompt 优化边际有限，后处理降色才是大杠杆**
- GLM-4.6V-Flash 高峰期 429 严重，质检改非高峰或抽检
- 地砖/方块类用**抠块拼接**（接缝 = 自然砖缝），纯背景用**代码 seamless**
- 精确符号/数字一律**代码画**，别交给 AI
- AI 只做它擅长的：moodboard、单张立绘、氛围封面
