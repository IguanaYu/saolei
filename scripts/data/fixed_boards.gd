class_name FixedBoards
extends RefCounted
## 固定盘面数据（试玩版关卡用）：雷位 / 预开区（含洪水结果）/ 预置基地
## 由 tmp/level1_board_finder.py 搜索烘焙（seed=18, base=(5,5)），
## 验收标准见 docs/active/试玩版内容/第一关-设计文档.md §7
## L2 由 tmp/level2_board_finder.py 烘焙（seed=1, base=(3,7), 7x7 方形预开），
## 验收标准见 docs/active/试玩版内容/第二关-设计文档.md §7

const L1 := {
	"mines": [Vector2i(1, 5), Vector2i(2, 3), Vector2i(2, 5), Vector2i(3, 0), Vector2i(5, 2), Vector2i(8, 2), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(9, 9)],
	"preopen": [Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(1, 9), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 9), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(3, 9), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8), Vector2i(4, 9), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5)],
	"base": Vector2i(5, 5),
}

const L2 := {
	"mines": [Vector2i(0, 0), Vector2i(0, 2), Vector2i(0, 3), Vector2i(1, 0), Vector2i(2, 2), Vector2i(3, 3), Vector2i(3, 12), Vector2i(4, 2), Vector2i(4, 13), Vector2i(5, 12), Vector2i(7, 4), Vector2i(7, 9), Vector2i(8, 2), Vector2i(8, 5), Vector2i(10, 6), Vector2i(10, 8), Vector2i(11, 5), Vector2i(11, 9), Vector2i(11, 10), Vector2i(12, 1), Vector2i(12, 5), Vector2i(12, 7), Vector2i(13, 7), Vector2i(13, 12)],
	"preopen": [Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(0, 9), Vector2i(0, 10), Vector2i(0, 11), Vector2i(0, 12), Vector2i(0, 13), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(1, 9), Vector2i(1, 10), Vector2i(1, 11), Vector2i(1, 12), Vector2i(1, 13), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10), Vector2i(2, 11), Vector2i(2, 12), Vector2i(2, 13), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(3, 9), Vector2i(3, 10), Vector2i(3, 11), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8), Vector2i(4, 9), Vector2i(4, 10), Vector2i(4, 11), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9), Vector2i(5, 10), Vector2i(5, 11), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(6, 10), Vector2i(6, 11), Vector2i(7, 5), Vector2i(7, 6), Vector2i(7, 7), Vector2i(7, 8), Vector2i(8, 6), Vector2i(8, 7), Vector2i(8, 8), Vector2i(9, 6), Vector2i(9, 7), Vector2i(9, 8)],
	"base": Vector2i(3, 7),
}

## L3 由 tmp/level3_board_finder.py 烘焙（seed=43, base=(3,5), 5x5 方形预开）：
## 预开 101 格（起始分）/ 过线时 29 旗+54 开格（扫七成雷）/ 停摆总分 395 /
## 角部歧义残余 9 格（核心区 R=6 干净）/ 最大连锁 24 格，验收全过（设计 §7）
const L3 := {
	"mines": [Vector2i(0, 4), Vector2i(0, 9), Vector2i(0, 14), Vector2i(1, 13), Vector2i(2, 0), Vector2i(2, 9), Vector2i(2, 10), Vector2i(2, 14), Vector2i(3, 1), Vector2i(3, 8), Vector2i(3, 12), Vector2i(5, 14), Vector2i(6, 2), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(7, 12), Vector2i(7, 13), Vector2i(8, 7), Vector2i(8, 8), Vector2i(8, 13), Vector2i(8, 15), Vector2i(9, 7), Vector2i(9, 8), Vector2i(9, 10), Vector2i(9, 12), Vector2i(10, 5), Vector2i(10, 12), Vector2i(11, 1), Vector2i(11, 2), Vector2i(11, 4), Vector2i(11, 8), Vector2i(12, 4), Vector2i(12, 11), Vector2i(13, 10), Vector2i(13, 12), Vector2i(14, 3), Vector2i(14, 15), Vector2i(15, 5), Vector2i(15, 13)],
	"preopen": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 9), Vector2i(3, 10), Vector2i(3, 11), Vector2i(4, 0), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8), Vector2i(4, 9), Vector2i(4, 10), Vector2i(4, 11), Vector2i(4, 12), Vector2i(4, 13), Vector2i(5, 0), Vector2i(5, 1), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(5, 9), Vector2i(5, 10), Vector2i(5, 11), Vector2i(5, 12), Vector2i(5, 13), Vector2i(6, 0), Vector2i(6, 1), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(6, 9), Vector2i(6, 10), Vector2i(6, 11), Vector2i(6, 12), Vector2i(6, 13), Vector2i(7, 0), Vector2i(7, 1), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6), Vector2i(8, 0), Vector2i(8, 1), Vector2i(8, 2), Vector2i(8, 3), Vector2i(8, 4), Vector2i(8, 5), Vector2i(8, 6), Vector2i(9, 0), Vector2i(9, 1), Vector2i(9, 2), Vector2i(9, 3), Vector2i(9, 4), Vector2i(9, 5), Vector2i(9, 6), Vector2i(10, 0), Vector2i(10, 1), Vector2i(10, 2), Vector2i(10, 3), Vector2i(10, 4)],
	"base": Vector2i(3, 5),
}

## L4 由 tmp/level4_board_finder.py 烘焙（seed=65, start=(9,9) 单起点洪水）：
## 预开 57 格（安全格 26%，v2.3 盲测反馈"开局一小撮"→固定图保大片预开）/
## 数字边界 32 格（预置网 x3 余量足）/ 区外零格 32（机器人连锁口袋）/ 象限雷 [9,11,9,11]，
## 验收标准见 docs/active/试玩版内容/第四关-设计文档.md §7（v2.3）
## 化石 origin=(5,8)（2026-10-04 后加，约束校验见 化石障碍-实施计划-v1.md §3）：
## 4 格全非雷非预开 / 距预开前沿切比雪夫 2（开局可见教学）/ 西侧走廊中部（机器人绕行=难度）/
## 全盘 4 连通校验通过（不产生口袋）；透明口径不改任何数字，安全格 216→212（胜利线 160 不动）
const L4 := {
	"mines": [Vector2i(0, 11), Vector2i(1, 2), Vector2i(1, 12), Vector2i(1, 15), Vector2i(2, 2), Vector2i(2, 8), Vector2i(3, 2), Vector2i(3, 8), Vector2i(3, 9), Vector2i(4, 1), Vector2i(4, 3), Vector2i(4, 9), Vector2i(5, 6), Vector2i(6, 15), Vector2i(7, 1), Vector2i(7, 5), Vector2i(7, 7), Vector2i(7, 9), Vector2i(8, 3), Vector2i(8, 7), Vector2i(8, 13), Vector2i(8, 15), Vector2i(9, 15), Vector2i(10, 3), Vector2i(10, 7), Vector2i(10, 15), Vector2i(11, 1), Vector2i(11, 12), Vector2i(12, 12), Vector2i(13, 2), Vector2i(13, 3), Vector2i(13, 4), Vector2i(13, 8), Vector2i(13, 11), Vector2i(14, 2), Vector2i(14, 6), Vector2i(14, 13), Vector2i(15, 7), Vector2i(15, 9), Vector2i(15, 14)],
	"preopen": [Vector2i(2, 10), Vector2i(2, 11), Vector2i(2, 12), Vector2i(2, 13), Vector2i(2, 14), Vector2i(2, 15), Vector2i(3, 10), Vector2i(3, 11), Vector2i(3, 12), Vector2i(3, 13), Vector2i(3, 14), Vector2i(3, 15), Vector2i(4, 10), Vector2i(4, 11), Vector2i(4, 12), Vector2i(4, 13), Vector2i(4, 14), Vector2i(4, 15), Vector2i(5, 10), Vector2i(5, 11), Vector2i(5, 12), Vector2i(5, 13), Vector2i(5, 14), Vector2i(5, 15), Vector2i(6, 10), Vector2i(6, 11), Vector2i(6, 12), Vector2i(6, 13), Vector2i(6, 14), Vector2i(7, 10), Vector2i(7, 11), Vector2i(7, 12), Vector2i(7, 13), Vector2i(7, 14), Vector2i(8, 8), Vector2i(8, 9), Vector2i(8, 10), Vector2i(8, 11), Vector2i(8, 12), Vector2i(9, 8), Vector2i(9, 9), Vector2i(9, 10), Vector2i(9, 11), Vector2i(9, 12), Vector2i(10, 8), Vector2i(10, 9), Vector2i(10, 10), Vector2i(10, 11), Vector2i(10, 12), Vector2i(11, 8), Vector2i(11, 9), Vector2i(11, 10), Vector2i(11, 11), Vector2i(12, 8), Vector2i(12, 9), Vector2i(12, 10), Vector2i(12, 11)],
	"fossils": [Vector2i(5, 8)],
}   # base 玩家自放：level_database 里 fixed_base=(-1,-1)（同 L5 口径）

## L5 由 tmp/level5_board_finder.py 烘焙（seed=67, center=(3,5), 7x7 方形预开）：
## 全程双规则可解（20 旗+108 开=全盘，拔完 20 颗牙不猜雷）/ 预开 68 格（35%）/
## 开局 5 个秒推目标含 5 面旗 / 最大连锁 19 格 / 第一行整行留墙（史莱姆入场通道）+
## 上边中段 x∈[4,10] 与最右列 x=13 无雷（Boss 入口区，设计 §9.6/9.7），验收全过（设计 §9）
const L5 := {
	"mines": [Vector2i(0, 12), Vector2i(1, 9), Vector2i(2, 0), Vector2i(3, 12), Vector2i(5, 1), Vector2i(5, 9), Vector2i(7, 7), Vector2i(7, 8), Vector2i(7, 9), Vector2i(8, 1), Vector2i(8, 4), Vector2i(9, 5), Vector2i(9, 8), Vector2i(9, 11), Vector2i(10, 0), Vector2i(10, 13), Vector2i(12, 0), Vector2i(12, 4), Vector2i(12, 7), Vector2i(12, 11)],
	"preopen": [Vector2i(0, 1), Vector2i(0, 2), Vector2i(0, 3), Vector2i(0, 4), Vector2i(0, 5), Vector2i(0, 6), Vector2i(0, 7), Vector2i(0, 8), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6), Vector2i(1, 7), Vector2i(1, 8), Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6), Vector2i(2, 7), Vector2i(2, 8), Vector2i(2, 9), Vector2i(2, 10), Vector2i(2, 11), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6), Vector2i(3, 7), Vector2i(3, 8), Vector2i(3, 9), Vector2i(3, 10), Vector2i(3, 11), Vector2i(4, 1), Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5), Vector2i(4, 6), Vector2i(4, 7), Vector2i(4, 8), Vector2i(4, 9), Vector2i(4, 10), Vector2i(4, 11), Vector2i(5, 2), Vector2i(5, 3), Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8), Vector2i(6, 2), Vector2i(6, 3), Vector2i(6, 4), Vector2i(6, 5), Vector2i(6, 6), Vector2i(6, 7), Vector2i(6, 8), Vector2i(7, 2), Vector2i(7, 3), Vector2i(7, 4), Vector2i(7, 5), Vector2i(7, 6)],
}   # base 玩家自放：level_database 里 fixed_base=(-1,-1)
