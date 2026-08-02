class_name Solver
## 扫雷求解器：返回所有 100% 确定的操作（不开/标错任何不确定的格子）
##
## 规则 1：一个数字格子的相邻已标雷数 == 数字 → 其余未开邻格全安全，可开
## 规则 2：一个数字格子的相邻未开格数（含已标雷）== 数字 → 未开格全是雷，可标

static func find_certain_actions(grid) -> Array:
	var actions: Array = []
	var seen: Dictionary = {}
	for coord in grid.cells:
		var cell = grid.cells[coord]
		if not cell.is_opened or cell.is_collapsed or cell.adjacent_mines == 0:
			continue
		var neighbors: Array = grid.get_neighbors(coord)
		var flagged_count: int = 0
		var unopened: Array = []
		for n in neighbors:
			if n.is_flagged:
				flagged_count += 1
			elif not n.is_opened and not n.is_collapsed:
				unopened.append(n)

		# 规则 1：已标雷数 == 数字 → 其余未开邻格全安全
		if flagged_count == cell.adjacent_mines and unopened.size() > 0:
			for n in unopened:
				var key := "open:" + str(n.coord)
				if not seen.has(key):
					seen[key] = true
					actions.append({"coord": n.coord, "action": "open", "source": coord})

		# 规则 2：未开邻格 + 已标雷数 == 数字 → 未开的全是雷
		if flagged_count + unopened.size() == cell.adjacent_mines and unopened.size() > 0:
			for n in unopened:
				var key := "flag:" + str(n.coord)
				if not seen.has(key):
					seen[key] = true
					actions.append({"coord": n.coord, "action": "flag", "source": coord})
	return actions
