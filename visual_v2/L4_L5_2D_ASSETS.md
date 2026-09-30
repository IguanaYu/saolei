# L4–L5 纯 2D 像素素材包

本批次只面向当前 28px 棋盘的 2D 游戏。运行 `python visual_v2/build_l4_l5_sprites.py` 可重建所有透明 PNG；预览见 `review/l4_l5_sprite_sheet.png`。游戏读取 `runtime/`，`source/boss_concept_sheet.png` 只作造型参考，不参与运行。

| 类别 | 文件 | 原生尺寸 | 游戏接入 |
| --- | --- | --- | --- |
| Boss | `runtime/boss/beast_p{1,2,3}_{idle,claw,inhale,growl,staggered,crawl,fall}.png` | 每帧 140×64 | `BossBeast` 已接入；右侧由现有代码旋转 |
| 落弹 | `runtime/boss/bomb_{shadow,fuse_0,fuse_1,deflect,explosion0..3}.png` | 28×28 | `Bomb` 已接入；引信与爆炸按帧播放 |
| 触手 | `runtime/boss/tentacle_{root,middle,tip,broken}.png` | 28×28 | `Tentacle` 已接入 |
| 敌人 | `runtime/enemies/{web,lock,slow,slime}_{0,1}.png` | 22×22 | `Enemy` 已接入，3 帧/秒切换 |
| 虫巢 | `runtime/enemies/nest_{0,1,2}.png` | 28×28 | `Nest` 已接入完好／受击／破碎态 |
| 保安 | `runtime/robots/robot_guard_{idle,move}.png` | 24×24 | `Robot.SKINS` 已接入 |
| 格子覆盖 | `runtime/tiles/overlays/{lock,web,slime_wall,slime_floor,confirmed,fire_0,fire_1,fire_low}.png` | 28×28 | `Cell` 已接入；火随剩余时间切帧 |
| 小图与特效 | `runtime/fx/{tooth,chain_link}.png` | 16×16 / 12×12 | 拔牙跳图、Boss 抛锁已接入 |
| UI 小图 | `runtime/ui/icons/{icon_tooth,icon_robot_guard,icon_probe}.png` | 16×16 / 24×24 | 文件已备；HUD 牙图和保安／探测商品入口待 UI 接入 |

素材准则：透明背景、最近邻采样、硬边像素、深蓝灰岩壳＋黄铜高光；Boss 三阶段用裂纹与发红区分，炸弹不复用棋盘地雷的红黑尖刺轮廓。Boss 概念稿使用内置 imagegen，提示词要点为“暗紫岩甲、牙形岩刺、琥珀眼、抓住棋盘边缘、七姿态一致、透明 2D 像素画、无 3D、无 emoji”；最终运行帧由本目录脚本在原生像素尺寸绘制，以保证格子对齐和动画一致性。
