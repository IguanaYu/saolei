class_name Grid
extends Node2D
## 16×16 扫雷网格：生成地图、管理 Cell、处理玩家点击、连锁展开、胜利检测

@export var rows: int = 16
@export var cols: int = 16
@export var mine_count: int = 32
@export var cell_size: int = 28
## 岩壁视觉风格：A1-A4 连体岩壁 / B1-B4 碎石泥土（章节可配）
@export var wall_style: String = "V2"

var show_grid_lines := false

var cells: Dictionary = {}  # {Vector2i: Cell}

const CELL_SCENE := preload("res://scenes/cell.tscn")
const FLY_ICON_OPEN := preload("res://visual_v2/runtime/ui/icons/icon_robot_opener.png")
const FLY_ICON_FLAG := preload("res://visual_v2/runtime/ui/icons/icon_robot_marker.png")

## 网格线覆盖层：作为最后一个子节点画在所有格子之上
class GridLines extends Node2D:
	var grid_size := Vector2i(16, 16)  # (rows, cols)
	var cell_px := 28

	func _draw() -> void:
		var w := grid_size.y * cell_px  # 宽 = cols
		var h := grid_size.x * cell_px  # 高 = rows
		var col := Color(0, 0, 0, 0.35)
		for x in grid_size.y + 1:
			draw_line(Vector2(x * cell_px, 0), Vector2(x * cell_px, h), col, 1.0)
		for y in grid_size.x + 1:
			draw_line(Vector2(0, y * cell_px), Vector2(w, y * cell_px), col, 1.0)


var _lines: GridLines = null

signal cell_opened(cell, by_actor: String)
signal cell_flagged(cell, by_actor: String, correct: bool, first_time: bool)
## 撤旗状态变化（拔旗动画用；正确/错误信息不给，保持推理口径）
signal cell_unflagged(cell, by_actor: String)
## 一次开格/和弦的批次结束事件（起点格、执行者、实际开成的格列表）：
## 动效层据此区分单格/连锁（设计稿 §接入点 1），奖励仍按 cell_opened 逐格结算
signal cell_open_batch(start_cell, by_actor: String, opened_cells: Array)
## 矿工卸货（全局坐标+货量；钱已由矿工入账，此事件只驱动确认动效）
signal cargo_unloaded(world_pos: Vector2, amount: int)
signal mine_stepped(cell, by_actor: String)
signal all_safe_opened()
signal vein_created(coord: Vector2i)
signal vein_depleted(coord: Vector2i)
signal obstacle_cleared(cell, kind: String, by_actor: String)  # L4 障碍清除（埋点/剧本转发）
signal processed_mines_changed(current: int)  # L5 牙数变化：旗→矿脉/确认雷/坍塌任一来源
signal fire_extinguish_requested(coord: Vector2i)  # L5 灭火：点任一火格 → 连通组熄灭（组逻辑在 BossManager）
## 任意棋盘点击（含已开空地上的无效点击；教学首句"点一下地图"推进用）
signal board_clicked
## 鼠标进入/离开格子（Area2D 原生信号转发；悬停预览用，见盘点 v1 §接入约束 2）
signal cell_hovered(cell)
signal cell_unhovered(cell)

# 已发过正确旗奖励的格子（coord→true）：同一格奖励仅首次发放、撤旗不退分（设计 §5，防刷）
var rewarded_flags: Dictionary = {}


func _ready() -> void:
	_lines = GridLines.new()
	_lines.visible = bool(GameSettings.get_value("show_grid"))
	add_child(_lines)
	_make_hover_overlay()
	_make_effects_layer()
	GameSettings.setting_changed.connect(_on_setting_changed)
	_center_grid()
	init_empty_grid()


var _fx: EffectsLayer = null


func _make_effects_layer() -> void:
	_fx = EffectsLayer.new()
	_fx.name = "EffectsLayer"  # 显式命名，避免遍历误匹配
	_fx.z_index = 45
	_fx.wall_style = wall_style
	add_child(_fx)
	cell_open_batch.connect(_fx.on_open_batch)
	cell_flagged.connect(func(cell, _a, _c, _f): _fx.fx_flag_dust(cell))
	cell_unflagged.connect(func(cell, _a): _fx.fx_flag_pull(cell))
	cargo_unloaded.connect(func(pos, amt): _fx.fx_unload(pos, amt))


## 悬停/落点预览覆盖层：单精灵复用，z_index 压过格子与网格线
## 贴图规格见 docs/active/局内交互视觉资产盘点-v1.md（tile_hover / place_valid / place_invalid）
var _hover_overlay: Sprite2D = null
var _hover_tex: Dictionary = {}


func _make_hover_overlay() -> void:
	_hover_tex = {
		"normal": load("res://visual_v2/runtime/fx/tile_hover.png"),
		"valid": load("res://visual_v2/runtime/fx/tile_place_valid.png"),
		"invalid": load("res://visual_v2/runtime/fx/tile_place_invalid.png"),
	}
	_hover_overlay = Sprite2D.new()
	_hover_overlay.name = "HoverOverlay"  # 显式命名，避免遍历误匹配
	_hover_overlay.z_index = 40
	_hover_overlay.centered = true
	_hover_overlay.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hover_overlay.visible = false
	add_child(_hover_overlay)


## state: "hide" / "normal"(普通悬停) / "valid" / "invalid"(放置落点合法性)
func set_hover_overlay(coord: Vector2i, state: String) -> void:
	if state == "hide" or not cells.has(coord) or not _hover_tex.has(state):
		if _hover_overlay != null:
			_hover_overlay.visible = false
		return
	_hover_overlay.texture = _hover_tex[state]
	_hover_overlay.position = cells[coord].position
	_hover_overlay.visible = true


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "show_grid":
		show_grid_lines = bool(value)
		_lines.visible = show_grid_lines


## 按关卡参数重置网格（P13）：改尺寸 + 重排位置 + 重建空网格
func configure(new_rows: int, new_cols: int, new_mines: int) -> void:
	rows = new_rows
	cols = new_cols
	mine_count = new_mines
	rewarded_flags.clear()
	board_generated = false
	_center_grid()
	init_empty_grid()


func _center_grid() -> void:
	# 非正方形棋盘（每日挑战等）：宽=cols、高=rows 分别居中
	var w := cols * cell_size
	var h := rows * cell_size
	var viewport: Vector2 = get_viewport_rect().size
	position = (viewport - Vector2(w, h)) / 2.0


## 创建空网格（全关闭），等待玩家放置第一个基地触发雷生成
func init_empty_grid() -> void:
	for c in cells.values():
		c.queue_free()
	cells.clear()
	for y in rows:
		for x in cols:
			var coord := Vector2i(x, y)
			var cell: Cell = CELL_SCENE.instantiate()
			# coord/wall_style 必须在 add_child 前设置：Cell._ready 里要用它们切岩壁 atlas
			cell.coord = coord
			cell.wall_style = wall_style
			add_child(cell)
			cell.position = Vector2(x * cell_size + cell_size / 2.0, y * cell_size + cell_size / 2.0)
			cell.cell_left_clicked.connect(_on_cell_left_clicked)
			cell.cell_right_clicked.connect(_on_cell_right_clicked)
			cell.cell_double_clicked.connect(_on_cell_double_clicked)
			cell.cell_obstacle_cleared.connect(_on_cell_obstacle_cleared)
			cell.mouse_entered.connect(_on_cell_mouse_entered.bind(cell))
			cell.mouse_exited.connect(_on_cell_mouse_exited.bind(cell))
			cells[coord] = cell
	# 网格线覆盖层挪到最后，保证画在格子之上；重开新盘时清掉悬停预览
	if _lines != null:
		_lines.grid_size = Vector2i(rows, cols)
		_lines.cell_px = cell_size
		move_child(_lines, get_child_count() - 1)
		_lines.queue_redraw()
	if _hover_overlay != null:
		_hover_overlay.visible = false
	if _fx != null:
		_fx.clear_all()  # 重开新盘清空岩屑/跳字/飞币等临时动效


func _on_cell_mouse_entered(cell: Cell) -> void:
	cell_hovered.emit(cell)


func _on_cell_mouse_exited(cell: Cell) -> void:
	cell_unhovered.emit(cell)


## 原地切换岩壁风格（不重置局面）：调试键 F5 / 章节主题用
func set_wall_style(style: String) -> void:
	wall_style = style
	if _fx != null:
		_fx.wall_style = style  # 岩屑跟主题换色
	for c in cells.values():
		c.apply_wall_style(style)


## 玩家放置第一个基地：触发雷生成 + 预开安全区 + 标记基地
## 任意关闭格都可放置（特例：不需要先开格）
## pregen_random 关（L4）：盘面已由 apply_random_board 预生成，只校验+落基地
var board_generated := false

## 首基地放置判定（无副作用）：悬停预览与 place_first_base 共用
## 普通随机盘任意关闭格可放；L4 预生成盘只能放已开格
func can_place_first_base(coord: Vector2i) -> bool:
	if not cells.has(coord):
		return false
	return not board_generated or cells[coord].is_opened


func place_first_base(coord: Vector2i) -> bool:
	if not can_place_first_base(coord):
		return false
	if board_generated:
		# L4 随机盘路径：不放雷、不预开安全区；基地只能落在已开格（设计 §3「玩家自放」）
		cells[coord].become_base()
		GameState.register_base(coord)
		GameState.set_game_phase("playing")
		return true
	# 安全区半径：基础 1 + 局外升级
	var radius: int = 1 + int(SaveSystem.unlocks.get("expand_zone", 0))
	var safe_coords: Array = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var sc := coord + Vector2i(dx, dy)
			if cells.has(sc):
				safe_coords.append(sc)
	# 在安全区外生成雷
	var data: Dictionary = MapGenerator.generate_excluding(rows, cols, mine_count, safe_coords)
	var mine_set: Dictionary = data.mine_set
	var numbers: Dictionary = data.numbers
	for c in cells:
		cells[c].is_mine = mine_set.has(c)
		cells[c].adjacent_mines = int(numbers.get(c, 0))
	# 预开安全区（直接设字段，不触发 cell_opened 信号，避免给奖励）
	for sc in safe_coords:
		cells[sc].is_opened = true
		cells[sc].refresh_visual()
	# 标记基地
	cells[coord].become_base()
	GameState.register_base(coord)
	GameState.set_game_phase("playing")
	return true


## 固定盘面装载（试玩版教学关）：写雷位 → 预开烘焙区 → 预置基地，跳过 placing_base 阶段
## data 结构见 FixedBoards：{"mines": [Vector2i...], "preopen": [Vector2i...], "base": Vector2i}
func apply_fixed_board(data: Dictionary) -> void:
	var mine_set: Dictionary = {}
	for m in data.mines:
		mine_set[m] = true
	for c in cells:
		cells[c].is_mine = mine_set.has(c)
		cells[c].adjacent_mines = 0
	# 数字：以雷格邻域计数
	for c in mine_set:
		for n in get_neighbors(c):
			n.adjacent_mines += 1
	# 预开（直接设字段，不触发 cell_opened 信号，不给奖励；refresh_visual 自带描边刷新）
	for sc in data.preopen:
		if cells.has(sc):
			cells[sc].is_opened = true
			cells[sc].refresh_visual()
	# 预置基地；base=(-1,-1) = 玩家自放（L5 Boss 关）：保持 placing_base 阶段，
	# 走 place_first_base 的 board_generated 分支（仅已开格，同 L4 自放口径）
	var base_coord: Vector2i = data.base
	if cells.has(base_coord):
		cells[base_coord].become_base()
		GameState.register_base(base_coord)
		GameState.set_game_phase("playing")
	board_generated = true


## 随机盘装载（试玩版 L4 除害关·裸随机，设计 §7）：
## 40 雷随机布（无排除区）→ 从一个安全零格洪水预开（连通展开自然落多少算多少，不卡比例）
## → 不预置基地（game_phase 保持 placing_base，强制玩家第一步自放，仅已开格可放）
func apply_random_board() -> void:
	var data: Dictionary = MapGenerator.generate_excluding(rows, cols, mine_count, [])
	var mine_set: Dictionary = data.mine_set
	var numbers: Dictionary = data.numbers
	for c in cells:
		cells[c].is_mine = mine_set.has(c)
		cells[c].adjacent_mines = int(numbers.get(c, 0))
	# 起点选择：随机取一个非雷零格（保证有洪水连锁；无零格则任取非雷格）
	var zero_cells: Array = []
	var safe_cells: Array = []
	for c in cells:
		if not cells[c].is_mine:
			safe_cells.append(c)
			if cells[c].adjacent_mines == 0:
				zero_cells.append(c)
	var pool: Array = zero_cells if not zero_cells.is_empty() else safe_cells
	if pool.is_empty():
		push_warning("随机盘生成失败：无安全格")
		board_generated = true
		return
	pool.shuffle()
	var start: Vector2i = pool[0]
	# 洪水预开：与 _flood_open 同构的连通展开，但直接设字段不 emit 信号（不给奖励，
	# 同 apply_fixed_board 预开写法；从起点格自身开起）
	var queue: Array = [start]
	var visited: Dictionary = {start: true}
	cells[start].is_opened = true
	cells[start].refresh_visual()
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for o in MapGenerator.NEIGHBOR_OFFSETS:
			var n: Vector2i = c + o
			if visited.has(n) or not cells.has(n):
				continue
			visited[n] = true
			var n_cell: Cell = cells[n]
			if n_cell.is_opened or n_cell.is_flagged or n_cell.is_mine:
				continue
			n_cell.is_opened = true
			n_cell.refresh_visual()
			if n_cell.adjacent_mines == 0:
				queue.append(n)
	board_generated = true
	# 裂缝与预置虫害的放置在 EnemyManager.setup_board（放基地前即可见，剧本 #0）


## 玩家放置后续基地（必须在已开格上）
func place_base(coord: Vector2i) -> bool:
	if not cells.has(coord):
		return false
	var cell: Cell = cells[coord]
	if not cell.is_opened or cell.is_collapsed or cell.is_base:
		return false
	cell.become_base()
	GameState.register_base(coord)
	return true


func get_cell(coord: Vector2i) -> Cell:
	return cells.get(coord)


## 刷新某格及其 4 邻的岩壁边缘描边（开格后调用，Cell 状态变化时自动触发）
func refresh_edges_around(coord: Vector2i) -> void:
	refresh_edges_at(coord)
	for dir in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		refresh_edges_at(coord + dir)


func refresh_edges_at(coord: Vector2i) -> void:
	var c: Cell = cells.get(coord)
	if c:
		c.refresh_wall_edges()


## 获取所有被标记旗子的格子坐标
func get_all_flagged_cells() -> Array:
	var result: Array = []
	for coord in cells:
		var c: Cell = cells[coord]
		if c.is_flagged and not c.is_vein:
			result.append(coord)
	return result


## 获取所有有资源的矿脉坐标
func get_all_veins() -> Array:
	var result: Array = []
	for coord in cells:
		var c: Cell = cells[coord]
		if c.is_vein and c.vein_resources > 0:
			result.append(coord)
	return result


## 获取离基地最远的 n 个关闭格（无人机用）
func get_farthest_closed_cells(n: int, base_coord: Vector2i) -> Array:
	var candidates: Array = []
	for coord in cells:
		var c: Cell = cells[coord]
		if c.is_opened or c.is_flagged or c.is_mine:
			continue
		if c.is_base or c.is_vein:
			continue
		var dist: int = abs(coord.x - base_coord.x) + abs(coord.y - base_coord.y)
		candidates.append({"coord": coord, "dist": dist})
	candidates.sort_custom(func(a, b): return a.dist > b.dist)
	var result: Array = []
	for i in range(min(n, candidates.size())):
		result.append(candidates[i].coord)
	return result


func get_neighbors(coord: Vector2i) -> Array:
	var result: Array = []
	for o in MapGenerator.NEIGHBOR_OFFSETS:
		var n: Vector2i = coord + o
		if cells.has(n):
			result.append(cells[n])
	return result


func open_cell(coord: Vector2i, by_actor: String) -> void:
	if not cells.has(coord):
		return
	var cell: Cell = cells[coord]
	if not cell.open(by_actor):
		return

	if cell.is_mine:
		cell.collapse()
		refresh_processed_mines()  # L5 牙数：踩塌 = 疼着拔一颗牙
		fx_tooth_at(coord)
		mine_stepped.emit(cell, by_actor)
		return

	cell_opened.emit(cell, by_actor)

	var chain: Array = [cell]
	if cell.adjacent_mines == 0:
		chain.append_array(_flood_open(coord, by_actor))

	# 胜利检测：在所有连锁展开之后
	if count_safe_remaining() == 0:
		all_safe_opened.emit()

	# 批次结束事件：动效层据此区分单格/连锁（奖励已按 cell_opened 逐格结算）
	cell_open_batch.emit(cell, by_actor, chain)


func toggle_flag(coord: Vector2i, by_actor: String) -> void:
	# Boss 关禁标雷：只拦玩家，机器人不受影响（但禁标雷关也不在 allowed_modules）
	if by_actor == "player" and GameState.is_action_forbidden("flag"):
		return
	if not cells.has(coord):
		return
	var cell: Cell = cells[coord]
	var was_flagged: bool = cell.is_flagged
	if not cell.toggle_flag():
		return
	if not was_flagged and cell.is_flagged:
		# 同格正确奖励仅首次发放（WP7）：撤旗再插不重复给奖/不重复计数
		var first_time: bool = not rewarded_flags.has(coord)
		if cell.is_mine and first_time:
			rewarded_flags[coord] = true
			refresh_processed_mines()  # L5 牙数：首次正确旗 = 拔一颗牙
			fx_tooth_at(coord)
		cell_flagged.emit(cell, by_actor, cell.is_mine, first_time)
	elif was_flagged and not cell.is_flagged:
		cell_unflagged.emit(cell, by_actor)


func chord(coord: Vector2i, by_actor: String) -> void:
	if not cells.has(coord):
		return
	var cell: Cell = cells[coord]
	if not cell.is_opened or cell.adjacent_mines == 0:
		return
	var neighbors: Array = get_neighbors(coord)
	var flagged_count: int = 0
	for n in neighbors:
		if n.is_flagged:
			flagged_count += 1
	if flagged_count != cell.adjacent_mines:
		return
	for n in neighbors:
		if not n.is_opened and not n.is_flagged:
			open_cell(n.coord, by_actor)


func is_walkable(coord: Vector2i) -> bool:
	if not cells.has(coord):
		return false
	var c: Cell = cells[coord]
	# 坍塌格视为已开；L5 火区/触手占格 = 通路阻断（path_blockers 0 时与原判定逐字节等价）
	return c.is_opened and c.path_blockers == 0


## 黏液减速判定（L4）：coord 的 3×3 内任一格有黏液 → 机器人间隔 ×2（布尔判定天然不叠乘）
func is_slime_nearby(coord: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c: Cell = cells.get(coord + Vector2i(dx, dy))
			if c != null and c.is_slimed:
				return true
	return false


func count_safe_remaining() -> int:
	var count: int = 0
	for cell in cells.values():
		if not cell.is_mine and not cell.is_opened:
			count += 1
	return count


## 安全格总数（与 count_safe_remaining 同口径；进度条 X/Y 的 Y）
func count_safe_total() -> int:
	var count: int = 0
	for cell in cells.values():
		if not cell.is_mine:
			count += 1
	return count


## 已处理雷数（L5 牙数，设计 §3）：正确旗（rewarded_flags 首次口径，撤旗不回退）
## / 探测确认雷 / 踩塌坍塌 / 矿脉（旧版检测转换），四种格级状态天然去重
func count_processed_mines() -> int:
	var count: int = 0
	for c in cells:
		var cell: Cell = cells[c]
		if cell.is_mine and (cell.is_vein or cell.is_confirmed_mine \
				or cell.is_collapsed or rewarded_flags.has(c)):
			count += 1
	return count


## 牙数变化出口：三处状态变更点（toggle_flag/open_cell 塌雷/probe）调用
func refresh_processed_mines() -> void:
	processed_mines_changed.emit(count_processed_mines())


## L5 拔牙跳字公开入口（EffectsLayer.fx_tooth_pulled 的坐标封装；仅拔牙关生效）
func fx_tooth_at(coord: Vector2i) -> void:
	var obj = GameState.current_objective
	if obj == null or obj.type != ObjectiveData.Type.FIND_ALL_MINES:
		return
	if _fx != null:
		_fx.fx_tooth_pulled(coord_to_world(coord))


func coord_to_world(coord: Vector2i) -> Vector2:
	return global_position + Vector2(
		coord.x * cell_size + cell_size / 2.0,
		coord.y * cell_size + cell_size / 2.0)


func world_to_coord(world_pos: Vector2) -> Vector2i:
	var local: Vector2 = world_pos - global_position
	return Vector2i(int(local.x / cell_size), int(local.y / cell_size))


## 连锁展开，返回本次实际开成的格列表（供批次事件汇总动效用）
func _flood_open(start: Vector2i, by_actor: String) -> Array:
	var start_cell: Cell = cells.get(start)
	if start_cell == null or start_cell.adjacent_mines != 0:
		return []
	var opened: Array = []
	var queue: Array[Vector2i] = [start]
	var visited: Dictionary = {start: true}
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for o in MapGenerator.NEIGHBOR_OFFSETS:
			var n: Vector2i = c + o
			if visited.has(n) or not cells.has(n):
				continue
			visited[n] = true
			var n_cell: Cell = cells[n]
			if n_cell.is_opened or n_cell.is_flagged:
				continue
			if not n_cell.open(by_actor):
				continue  # 锁格等开格失败：不发事件（否则虚假收益/动效）
			cell_opened.emit(n_cell, by_actor)
			opened.append(n_cell)
			if n_cell.adjacent_mines == 0 and not n_cell.is_mine:
				queue.append(n)
	return opened


## 障碍清除统一入口（优先级 锁>网>黏液，同保安索敌序）：返回清除的 kind，""=无可清
func clear_cell_obstacle(cell: Cell, by_actor: String) -> String:
	if cell.is_locked and not cell.is_opened:
		return "lock" if cell.clear_lock(by_actor) else ""
	if cell.is_webbed and cell.is_opened:
		return "web" if cell.clear_web(by_actor) else ""
	if cell.is_slimed:
		return "slime" if cell.clear_slime(by_actor) else ""
	return ""


func _on_cell_obstacle_cleared(cell, kind: String, by_actor: String) -> void:
	obstacle_cleared.emit(cell, kind, by_actor)


func _on_cell_left_clicked(cell: Cell) -> void:
	if not GameState.game_active:
		return
	board_clicked.emit()
	if GameState.is_player_blocked():
		GameState.cd_blocked.emit()
		return
	# L5 灭火优先（设计 §5.2 + Q8：火 > 其他障碍）：点任一火格 = 整片连通火熄灭，吃 1 CD
	# （连通组与奖励在 BossManager；本击只灭火，不做开格）
	if cell.is_on_fire:
		fire_extinguish_requested.emit(cell.coord)
		return
	# L4 障碍清除分流（设计 §9.9）：点击命中障碍 → 本击只清障不开格，吃 1 次 CD
	# （黏液不阻断开/标，但点击命中的是障碍：先清后开，第二击再开格）
	if cell.has_obstacle():
		var kind := clear_cell_obstacle(cell, "player")
		if kind != "":
			GameState.consume_player_action()
			play_player_action_visual(cell.coord, FLY_ICON_OPEN)
		return
	# 先判断动作是否会生效（只对生效动作计 CD 次数），执行后再计数
	var will_open: bool = not cell.is_opened and not cell.is_collapsed \
			and not cell.is_flagged and not cell.is_base
	open_cell(cell.coord, "player")
	if will_open:
		GameState.consume_player_action()
		play_player_action_visual(cell.coord, FLY_ICON_OPEN)


func _on_cell_right_clicked(cell: Cell) -> void:
	if not GameState.game_active:
		return
	board_clicked.emit()
	if GameState.is_player_blocked():
		GameState.cd_blocked.emit()
		return
	# 锁格右键也走清锁：锁同时拦开与标，清除是唯一出路（计划 WP2.3）
	if cell.is_locked and not cell.is_opened:
		if cell.clear_lock("player"):
			GameState.consume_player_action()
			play_player_action_visual(cell.coord, FLY_ICON_FLAG)
		return
	var will_toggle: bool = not cell.is_opened and not cell.is_collapsed
	toggle_flag(cell.coord, "player")
	if will_toggle:
		GameState.consume_player_action()
		play_player_action_visual(cell.coord, FLY_ICON_FLAG)


func _on_cell_double_clicked(cell: Cell) -> void:
	if not GameState.game_active:
		return
	board_clicked.emit()
	if GameState.is_player_blocked():
		GameState.cd_blocked.emit()
		return
	if _chord_would_open(cell):
		chord(cell.coord, "player")
		GameState.consume_player_action()
		play_player_action_visual(cell.coord, FLY_ICON_OPEN)


## 和弦预判：数字格、旗数匹配、且至少有一个可开邻格（与 chord() 判定一致）
func _chord_would_open(cell: Cell) -> bool:
	if not cell.is_opened or cell.adjacent_mines == 0:
		return false
	var flagged := 0
	var openable := 0
	for n in get_neighbors(cell.coord):
		if n.is_flagged:
			flagged += 1
		elif not n.is_opened:
			openable += 1
	return flagged == cell.adjacent_mines and openable > 0


## 玩家操作=一次性机器人：动作瞬发生效后，小机器人图标从最近基地飞落目标格（纯视觉）
func play_player_action_visual(to_coord: Vector2i, icon: Texture2D) -> void:
	var from_coord: Vector2i = to_coord
	var nearest = GameState.get_nearest_base(to_coord)
	if nearest != null:
		from_coord = nearest
	var spr := Sprite2D.new()
	spr.texture = icon
	spr.scale = Vector2(0.55, 0.55)
	spr.z_index = 50
	add_child(spr)
	spr.position = Vector2(
		from_coord.x * cell_size + cell_size / 2.0,
		from_coord.y * cell_size + cell_size / 2.0)
	var to_pos := Vector2(
		to_coord.x * cell_size + cell_size / 2.0,
		to_coord.y * cell_size + cell_size / 2.0)
	var tw := create_tween()
	tw.tween_property(spr, "position", to_pos, 0.35).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(spr, "rotation", TAU, 0.35)
	tw.tween_property(spr, "scale", Vector2(0.1, 0.1), 0.15)
	tw.tween_callback(spr.queue_free)
