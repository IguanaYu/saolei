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
static func find_nearest_target(grid, start: Vector2i, targets: Array, locked: Dictionary, robot_at: Dictionary, except_robot: Variant = null) -> Dictionary:
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
			if robot_at.has(n) and n != start:
				continue
			visited[n] = true
			queue.append([n, path + [n]])
	return {}


static func _is_adjacent_8(a: Vector2i, b: Vector2i) -> bool:
	var dx: int = abs(a.x - b.x)
	var dy: int = abs(a.y - b.y)
	return dx <= 1 and dy <= 1 and not (dx == 0 and dy == 0)
