extends SceneTree
## 路径驱动地图生成器 · 对拍测试（设计文档 §12 末段：Python 搜索与 Godot 结算共同场景对拍）
## 流程：读 tools/route_gen/out/parity_scenario.json → 真实 Grid 装载固定盘 →
##       逐条执行动作（open/flag/chord/clear_lock/probe）→ 写 parity_result.json
## 奖励口径镜像 main.gd:1530(_on_cell_opened +1金+1分) / 1549(_on_cell_flagged 正确首次+5)
##      / 1353(探针 -100金) / 1883(_trigger_probe 3×3 确认雷)
## 用法：python tools/route_gen/parity.py（内部调）或
##       Godot_console.exe --path . --headless -s res://tests/route_gen_parity.gd
## 注意：-s 模式下编译期引用 Grid/Cell/GameState 标识符会在 autoload 注册前编译失败
##      （grid.gd:91 引 GameSettings），全部走运行期 load()/get_node（同 tmp 测试套路）。

const SCENARIO_PATH := "res://tools/route_gen/out/parity_scenario.json"
const RESULT_PATH := "res://tools/route_gen/out/parity_result.json"

# 奖励镜像用成员变量（GDScript lambda 对局部变量值捕获，累加必须挂成员上）
var _money := 0
var _score := 0
var _flag_rewards: Array = []


func _initialize() -> void:
	call_deferred("_run")


func _v2i(a) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


func _run() -> void:
	await process_frame
	await process_frame
	var fails: Array = []
	if not FileAccess.file_exists(SCENARIO_PATH):
		push_error("场景不存在：%s（先跑 python tools/route_gen/parity.py --emit）" % SCENARIO_PATH)
		quit(1)
		return
	var f := FileAccess.open(SCENARIO_PATH, FileAccess.READ)
	var scen: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var board: Dictionary = scen["board"]
	var w: int = int(board["w"])
	var h: int = int(board["h"])
	var mines: Array = []
	for m in board["mines"]:
		mines.append(_v2i(m))
	var preopen: Array = []
	for p in board["preopen"]:
		preopen.append(_v2i(p))
	var data := {
		"mines": mines,
		"preopen": preopen,
		"base": _v2i(board["base"]),
	}
	if board.has("fossils"):
		var fos: Array = []
		for o in board["fossils"]:
			fos.append(_v2i(o))
		data["fossils"] = fos
	if board.has("walls"):
		var wls: Array = []
		for wl in board["walls"]:
			wls.append(_v2i(wl))
		data["walls"] = wls

	# ---- 装载真实 Grid（固定盘路径，与 apply_fixed_board 全一致）----
	var grid_script = load("res://scripts/grid.gd")
	var grid: Node2D = grid_script.new()
	grid.name = "ParityGrid"
	root.add_child(grid)
	grid.configure(h, w, mines.size())   # configure(rows, cols, mines)：rows=y 数
	grid.apply_fixed_board(data)
	# apply_fixed_board 无锁格字段（锁在真实游戏由虫害系统铺设）：对齐 cell.apply_lock 口径补铺
	if board.has("locked"):
		for lk in board["locked"]:
			var lcell = grid.get_cell(_v2i(lk))
			if lcell != null:
				lcell.apply_lock()
	var gs = root.get_node("/root/GameState")
	await process_frame

	# ---- 奖励镜像（main.gd 口径；drone 分支不涉及）----
	_money = int(scen.get("start_money", 0))
	_score = 0
	_flag_rewards = []
	grid.cell_opened.connect(func(_cell, _actor):
		_money += 1
		_score += 1)
	grid.cell_flagged.connect(func(cell, _actor, correct: bool, first_time: bool):
		# main.gd:1549 正确首次 +5；confirmed_mine 不重复给；错旗无惩罚
		var fired: bool = correct and first_time and not cell.is_confirmed_mine
		if fired:
			_money += 5
			_score += 5
		_flag_rewards.append({"coord": [cell.coord.x, cell.coord.y], "reward_fired": fired}))

	# ---- 执行动作 ----
	for act in scen["actions"]:
		var kind: String = act["kind"]
		var coord := _v2i(act["coord"])
		match kind:
			"open":
				grid.open_cell(coord, "player")
			"flag":
				grid.toggle_flag(coord, "player")
			"chord":
				grid.chord(coord, "player")
			"clear_lock":
				var cell = grid.get_cell(coord)
				if cell != null:
					cell.clear_lock("player")
			"probe":
				# main.gd:1353 扣费 + 1883 3×3 确认雷
				_money -= int(gs.PROBE_PRICE)
				for dy in range(-1, 2):
					for dx in range(-1, 2):
						var c = grid.get_cell(coord + Vector2i(dx, dy))
						if c != null and c.is_mine and not c.is_confirmed_mine:
							c.confirm_mine()
			_:
				fails.append("未知动作类型 %s" % kind)
	await process_frame

	# ---- 汇总终态 ----
	var opened: Array = []
	var flagged: Array = []
	var collapsed: Array = []
	var confirmed: Array = []
	var wall_hp: Array = []
	var locked: Array = []
	for coord in grid.cells:
		var cell = grid.cells[coord]
		var xy := [coord.x, coord.y]
		if cell.is_opened:
			opened.append(xy)
		if cell.is_flagged:
			flagged.append(xy)
		if cell.is_collapsed:
			collapsed.append(xy)
		if cell.is_confirmed_mine:
			confirmed.append(xy)
		if cell.is_locked:
			locked.append(xy)
		if cell.wall_hp != 1 and not cell.is_opened:
			wall_hp.append({"coord": xy, "hp": cell.wall_hp})
	var result := {
		"opened": opened, "flagged": flagged, "collapsed": collapsed,
		"confirmed": confirmed, "locked": locked, "wall_hp": wall_hp,
		"money": _money, "score": _score, "flag_rewards": _flag_rewards,
	}
	var fw := FileAccess.open(RESULT_PATH, FileAccess.WRITE)
	fw.store_string(JSON.stringify(result, "  "))
	fw.close()
	print("[Parity] 动作 %d 条执行完毕：opened=%d flagged=%d collapsed=%d money=%d score=%d" % [
		scen["actions"].size(), opened.size(), flagged.size(), collapsed.size(), _money, _score])
	quit(0 if fails.is_empty() else 1)
