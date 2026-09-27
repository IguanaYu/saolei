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
