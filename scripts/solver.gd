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
		# L4 网失明：被网盖住的数字格不再提供推理依据（机器人失明停摆，设计 §5）
		# L5 炸弹压格同口径（bomb_masked，设计 §5.2）：数字被挡 = 同盲
		if not cell.is_opened or cell.is_collapsed or cell.is_webbed \
				or cell.bomb_masked or cell.adjacent_mines == 0:
			continue
		var neighbors: Array = grid.get_neighbors(coord)
		var flagged_count: int = 0
		var unopened: Array = []
		for n in neighbors:
			# 矿脉 / 坍塌格 = 已确认的雷（已开但不再有旗子），等价于旗子计入雷数
			# 否则求解器会少算雷数，误把周围安全格标成雷 → 永远无法胜利
			# L4「确认雷」同理：机器人视同旗（探测情报直接进规则 1/2 推理）
			if n.is_flagged or n.is_vein or n.is_collapsed or n.is_confirmed_mine:
				flagged_count += 1
			elif not n.is_opened and not n.is_collapsed:
				# 锁格保留在 unopened 参与雷数计数（锁格真值未知，从计数里消失会误标邻格），
				# 只在动作生成时跳过（机器人开不了锁格，WP2.4）
				unopened.append(n)

		# 规则 1：已标雷数 == 数字 → 其余未开邻格全安全
		if flagged_count == cell.adjacent_mines and unopened.size() > 0:
			for n in unopened:
				if n.is_locked:
					continue  # 锁格谁都不能开——动作跳过，玩家/保安清锁后恢复
				var key := "open:" + str(n.coord)
				if not seen.has(key):
					seen[key] = true
					actions.append({"coord": n.coord, "action": "open", "source": coord})

		# 规则 2：未开邻格 + 已标雷数 == 数字 → 未开的全是雷
		if flagged_count + unopened.size() == cell.adjacent_mines and unopened.size() > 0:
			for n in unopened:
				if n.is_locked:
					continue  # 锁格不能标（机器人不能在锁格上动作）
				var key := "flag:" + str(n.coord)
				if not seen.has(key):
					seen[key] = true
					actions.append({"coord": n.coord, "action": "flag", "source": coord})
	return actions
