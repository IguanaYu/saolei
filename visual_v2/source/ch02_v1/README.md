# 第二章表现素材 v1

三套角色/设施原图使用 Codex 内置 `image_gen` 制作，参照已有开墙机器人风格；原图保留，运行时加载缩小后的帧表。激光、扩爆与章节徽记为自行绘制的 SVG 像素图标。生成提示词见 [manifest.json](manifest.json)。

| 对象 | 单帧 | 帧表 | 图标 |
|---|---|---|---|
| 过载机器人 | 24×24 | 72×24，3 帧 | 24×24 |
| 筑墙工 | 22×22 | 66×22，3 帧 | 24×24 |
| 特殊矿石 | 48×48 | 144×48，3 帧 | 24×24 |
| 激光、扩爆 | SVG | 不适用 | 24×24 |
| 章节徽记 | SVG | 不适用 | 32×32 |

导出运行 `node visual_v2/export_ch02_v1.cjs`，需要 `sharp`；可用 `CH02_SHARP_PATH` 指定模块路径。脚本只做裁切、锚点对齐、最近邻缩小及透明边缘清理。公共缩放比例保留微动作幅度，三帧脚底保持同一行；不会因每帧自动填满而改变本体大小。

逐像素校验运行 `python scripts/tools/verify_ch02_assets.py`，先输出 bbox、alpha 与帧差，再检查帧边距和脚底锚点。导出测量表在 `runtime/ch02_v1/export_manifest.json`。

新增素材后先执行 Godot `--headless --import`。TextureRect 图标明确采用 `EXPAND_IGNORE_SIZE`，角色 Sprite2D 使用最近邻采样；矿石缩放在其 2×2 足迹内。
