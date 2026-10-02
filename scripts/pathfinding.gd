class_name Pathfinding
## BFS 寻路：在已开区域找最近的可作业墙

# 4 方向移动（曼哈顿距离）
const MOVE_OFFSETS := [
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(0, -1), Vector2i(0, 1),
]


## 找到从 start 出发，能作业（即 8 邻接）任一 target 的最近格子
## 返回 {target: Vector2i, path: Array[Vector2i], work_pos: Vector2i} 或 {}
## path[0] 是从 start 出发要走到的下一格；work_pos 是机器人作业时站的位置
## except_robot：调用方自己；锁是它自己锁的 target 不算"被占用"
## 机器人之间允许互相穿越（可短暂同格）：若把对方格子当墙，
## 对向行进的两台会各自"退绕"再相遇，形成永久震荡活锁
static func find_nearest_target(grid, start: Vector2i, targets: Array, locked: Dictionary, except_robot: Variant = null) -> Dictionary:
	var target_set: Dictionary = {}
	for t in targets:
		var locked_by: Variant = locked.get(t, null)
		if locked_by != null and locked_by != except_robot:
			continue
		target_set[t] = true
	if target_set.is_empty():
		return {}

	var queue: Array = [[start, []]]
	var visited: Dictionary = {start: true}
	while not queue.is_empty():
		var entry = queue.pop_front()
		var pos: Vector2i = entry[0]
		var path: Array = entry[1]

		# 检查 pos 是否 8 邻接任一 target（机器人站这里就能作业）
		for t in target_set:
			if _is_adjacent_8(pos, t):
				return {"target": t, "path": path, "work_pos": pos}

		# 4 方向扩展（移动只用 4 邻接）
		for offset in MOVE_OFFSETS:
			var n: Vector2i = pos + offset
			if visited.has(n):
				continue
			if not grid.is_walkable(n):
				continue
			visited[n] = true
			queue.append([n, path + [n]])
	return {}


static func _is_adjacent_8(a: Vector2i, b: Vector2i) -> bool:
	var dx: int = abs(a.x - b.x)
	var dy: int = abs(a.y - b.y)
	return dx <= 1 and dy <= 1 and not (dx == 0 and dy == 0)


## 同型防抱团过滤（2026-10-02）：剔除「距其他同型机器人已锁目标 ≤ radius 格（切比雪夫）」
## 的候选，让同型机器人优先散开干活；返回空数组 = 全被挤占，调用方回退原始列表
## （挤着也要干活，绝不因为分散而停工）
static func spaced_targets(targets: Array, locked: Dictionary,
		robot_type: String, except_robot: Variant = null, radius: int = 2) -> Array:
	var same_locks: Array = []
	for t in locked:
		var holder: Variant = locked[t]
		if holder != except_robot and holder != null and holder.robot_type == robot_type:
			same_locks.append(t)
	if same_locks.is_empty():
		return targets
	var spaced: Array = []
	for t in targets:
		var crowded := false
		for l in same_locks:
			if maxi(abs(t.x - l.x), abs(t.y - l.y)) <= radius:
				crowded = true
				break
		if not crowded:
			spaced.append(t)
	return spaced


## 无限制 BFS（L4 敌虫用）：不受 walkable 限制（虫爬岩壁），全盘 4 向可走
## 返回从 start 走向 goal 的下一格（Vector2i），start==goal 或不可达返回 Vector2i(-9,-9)
static func find_path_free_step(grid, start: Vector2i, goal: Vector2i) -> Vector2i:
	if start == goal:
		return Vector2i(-9, -9)
	var queue: Array = [start]
	var came_from: Dictionary = {start: Vector2i(-9, -9)}  # coord -> 前驱（根为哨兵）
	while not queue.is_empty():
		var pos: Vector2i = queue.pop_front()
		if pos == goal:
			break
		for offset in MOVE_OFFSETS:
			var n: Vector2i = pos + offset
			if came_from.has(n):
				continue
			if not grid.cells.has(n):
				continue
			came_from[n] = pos
			queue.append(n)
	if not came_from.has(goal):
		return Vector2i(-9, -9)  # 理论不可达（goal 越界）
	# 回溯到 start 的下一步
	var step: Vector2i = goal
	while came_from[step] != start:
		step = came_from[step]
	return step
