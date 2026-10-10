class_name SpecialOre
extends Node2D
## 2-3 特殊矿石（改版提案 2026-10-10 §4）：中立多格不可破坏设施。
## 玩家激光束止于它（命中即触发，不穿透），向 3 个随机互异八向各影响 ≤3 格——
## 无限次重复触发（consumed 恒 false），一块「多点几下就能持续开区」的本地工具。
## 足迹落预开安全格（同连爆节点先例）：已开格永不进 Solver 目标集，
## 「不可破坏」由 LaserManager 结算跳过足迹格保证；挡路/挡施工走 grid.facility_cells。

const SIZE := 2                    # 足迹边长（2×2；实测后调清单项）
const BURST_DIRS := 3              # 每次爆发的方向数（拍板 #4）
const BURST_RANGE := 3             # 每向影响步数（拍板 #3 射程 3）
## 八向全表（互异即两两夹角 ≥45°>30°——拍板 #4 的角度约束在八向口径下天然满足）
const ALL_DIRS := [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]

var origin: Vector2i = Vector2i(-9, -9)


func setup(o: Vector2i, grid) -> void:
	origin = o
	z_index = 8  # 同连爆节点：压过格子与网格线，低于虫(10)/机器人悬停角框(40)
	# 2×2 几何中心 = 四格中心的均值（origin 格心 + 半格偏移）
	position = grid.coord_to_world(origin) + Vector2(grid.cell_size / 2.0,
			grid.cell_size / 2.0)
	queue_redraw()


## 足迹全格（占格/结算跳过/触发判定共用）
func footprint() -> Array:
	var out: Array = []
	for dy in SIZE:
		for dx in SIZE:
			out.append(origin + Vector2i(dx, dy))
	return out


## 爆发格集：3 个随机互异八向，各向从足迹外缘格出发 ≤3 步（边界裁切、剔足迹）。
## 斜向是 2 宽阶梯带（同主束斜射口径，LaserGeometry 全章唯一几何源）。
## rng 注入：测试可复现；每轮调用重新随机（无限次触发=每次新形状）
func burst_cells(grid, rng: RandomNumberGenerator) -> Array:
	var dirs: Array = ALL_DIRS.duplicate()
	for i in range(dirs.size() - 1, 0, -1):  # Fisher-Yates 用注入 rng
		var j: int = rng.randi_range(0, i)
		var t: Vector2i = dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = t
	var foot: Dictionary = {}
	for c in footprint():
		foot[c] = true
	var out: Array = []
	for d in dirs.slice(0, BURST_DIRS):
		var edge := origin + Vector2i(1 if d.x > 0 else 0, 1 if d.y > 0 else 0)
		for c in LaserGeometry.beam_cells(edge, edge + d * BURST_RANGE):
			if foot.has(c) or not grid.cells.has(c) or out.has(c):
				continue
			out.append(c)
	return out


func _draw() -> void:
	# 程序绘制占位：青蓝同心环晶簇 + 白芯菱晶（沿 ChainNode 同心环语言，素材批后换贴图）
	draw_arc(Vector2.ZERO, 23.0, 0.0, TAU, 28, Color(0.30, 0.85, 0.95, 0.92), 2.0)
	draw_arc(Vector2.ZERO, 17.0, 0.0, TAU, 24, Color(0.55, 0.95, 1.0, 0.85), 1.5)
	draw_circle(Vector2.ZERO, 13.0, Color(0.10, 0.35, 0.45, 0.55))
	var pts := PackedVector2Array([Vector2(0, -9), Vector2(7, 0), Vector2(0, 9), Vector2(-7, 0)])
	draw_colored_polygon(pts, Color(0.85, 0.98, 1.0, 0.95))
	draw_circle(Vector2.ZERO, 2.5, Color(1.0, 1.0, 1.0))
