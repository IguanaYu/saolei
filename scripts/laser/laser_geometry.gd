class_name LaserGeometry
extends RefCounted
## 第二章激光几何：全章唯一几何源（预览/结算/Python 烘焙对拍共用同一套规则）
## 设计：docs/active/玩法设计/第二章-激光矿场/00-核心思路与章节总纲.md §5
## 实施计划：2-1 WP1——超覆盖 Bresenham（格心到格心），预览=结算同源的结构保证

## 格心连线的超覆盖：返回线触及的全部格（不含起点、含终点）。
## 恰穿过格点时收「先横后竖」路径的两格（横步格 + 斜步格），不收纯竖步格——
## 统一栅格规则（45° 斜线 = 2 格宽阶梯带；预览与结算同源所以对玩家始终自洽）。
## 实现：按参数 t 收集竖线/横线穿越事件，整数叉乘比较合并同刻事件（无浮点误差）；
## 竖线事件键 (2i-1)*|dy|、横线事件键 (2j-1)*|dx|（格心出发，首条网格线在半格处）。
static func beam_cells(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if from == to:
		return []
	var out: Array[Vector2i] = []
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	var ax: int = absi(dx)
	var ay: int = absi(dy)
	var sx: int = signi(dx)
	var sy: int = signi(dy)
	var events: Array = []  # [键(排序用 int), 类型(0=竖线 1=横线)]；同键同类不可能（i/j 互异）
	for i in range(1, ax + 1):
		events.append([(2 * i - 1) * ay, 0])
	for j in range(1, ay + 1):
		events.append([(2 * j - 1) * ax, 1])
	events.sort_custom(func(a, b):
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1])  # 同键时竖线先于横线（先横后竖的固定序）
	var cur := from
	var idx := 0
	while idx < events.size():
		var key: int = events[idx][0]
		# 同刻横竖事件对 = 恰过格点：两格都收（先横后竖）
		if idx + 1 < events.size() and events[idx + 1][0] == key \
				and events[idx][1] != events[idx + 1][1]:
			cur.x += sx
			out.append(cur)
			cur.y += sy
			out.append(cur)
			idx += 2
			continue
		if events[idx][1] == 0:
			cur.x += sx
		else:
			cur.y += sy
		out.append(cur)
		idx += 1
	return out


## 方向八向量化：取与格心连线夹角最小的八方向。
## 22.5° 阈值用整数比较（tan22.5°≈0.4142 → 10000 倍放大），无三角函数无浮点。
## 2-3 宽束/散射出射方向与 2-5 引光柱轴量化用。
static func octant_dir(from: Vector2i, to: Vector2i) -> Vector2i:
	var dx: int = to.x - from.x
	var dy: int = to.y - from.y
	if dx == 0 and dy == 0:
		return Vector2i.ZERO
	var sx: int = signi(dx)
	var sy: int = signi(dy)
	var ax: int = absi(dx)
	var ay: int = absi(dy)
	if ay * 10000 <= ax * 4142:
		return Vector2i(sx, 0)   # 近水平
	if ax * 10000 <= ay * 4142:
		return Vector2i(0, sy)   # 近垂直
	return Vector2i(sx, sy)      # 斜向


## 八向旋转 ±45°（octant ± 1）：dir8 必须是八方向单位向量（分量 ∈ {-1,0,1}，非零）
static func rotate_octant(dir8: Vector2i, steps: int) -> Vector2i:
	const OCT := [
		Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	]
	var idx := OCT.find(dir8)
	if idx < 0:
		return dir8
	return OCT[wrapi(idx + steps, 0, 8)]
