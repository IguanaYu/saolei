class_name LaserManager
extends Node2D
## 第二章激光发射/结算管理器（2-1 WP3；后续关在此扩多束/充能/对敌/连爆）
## 设计：docs/active/玩法设计/第二章-激光矿场/00-核心思路与章节总纲.md §5
## 结算序（总纲 §5.3）：几何快照 → 逐格结算（同一格本轮至多一次）→ 奖励 → 本轮完再判达标
## （达标判定走 main._on_score_changed 的 call_deferred，天然等整轮结束）
##
## 发射点 = GameState.bases[0]（首轮原型每关单基地固定，总纲 §5.1）；
## CD/动作预算由 main 在发射前检查与消耗，本类不碰 GameState 的 CD 状态

signal laser_fired(target: Vector2i)          # 已发射（含空射；director/埋点用）
signal laser_resolved(target: Vector2i)       # 整轮结算完成（后续关的达标检查挂点）
signal robots_charged(robots: Array)          # 2-2：本轮充能的机器人（director 视觉自解释用）
signal refractor_activated(r)               # 2-3：本轮主束命中折光（director 首增幅句挂点）
signal chain_triggered(nodes: Array)        # 2-4：本轮引爆的连爆节点（快照 BFS 序）
signal pillar_broken                          # 2-5：引光柱本轮破碎（-50 已入账）

var grid: Grid = null
var enemy_manager: EnemyManager = null
## 最近 10s 被玩家激光打出的格（2-2 筑墙工优先在这些地面施工用；环形淘汰）
var recent_laser_opened: Dictionary = {}  # coord -> elapsed

const RECENT_WINDOW_SEC := 10.0


func setup(g: Grid, em: EnemyManager = null) -> void:
	grid = g
	enemy_manager = em
	g.cell_hovered.connect(_on_cell_hovered)
	g.cell_unhovered.connect(_on_cell_unhovered)


## 每关重置（main._start_level_with 调用）
func reset_for_level() -> void:
	recent_laser_opened.clear()


func _shot_origin() -> Vector2i:
	if GameState.bases.is_empty():
		return Vector2i(-1, -1)
	return GameState.bases[0]


func is_laser_level() -> bool:
	return grid != null and grid.laser_mode


## 发射入口（main 在 CD 检查通过并消耗 1 动作后调用）。
## 点基地格自身（束长 0）不发射不扣动作——返回 false 提示调用方别消耗动作。
func try_fire(target: Vector2i) -> bool:
	if grid == null or not is_laser_level():
		return false
	var base := _shot_origin()
	if base == Vector2i(-1, -1) or base == target:
		return false
	fire(base, target)
	return true


## 2-2 查询：该格最近 10s 是否被玩家激光拆过（筑墙工施工优先级用）
func was_recently_lasered(c: Vector2i) -> bool:
	return recent_laser_opened.has(c)


## 2-3：指定格上的折光机器人（无则 null）
func refractor_at(c: Vector2i) -> RefractorRobot:
	var rm = get_node_or_null("../RobotManager")
	if rm == null:
		return null
	for r in rm.robots:
		if r is RefractorRobot and r.coord == c:
			return r
	return null


## 2-4：中立设施管理器（连爆节点；无则 null）
func facility_manager() -> FacilityManager:
	return get_node_or_null("../FacilityManager") as FacilityManager


## 一次射击的公开几何（预览与结算唯一同源，总纲 §4.5/§11）：
## 主束 base→target 超覆盖推进，遇第一台折光即止；折光按入射八向出射副束
## （wide=3 宽×6 走廊 / scatter=±45° 三束各 6）；副束不再激活其他折光（总纲 §6.2）。
## 2-5 强制定向（总纲 §6.4，以射击开始的柱存活态为准——快照固化，破碎从下轮生效）：
## 柱存活时折光出射主轴必指向柱——wide=折光→柱完整线段的 3 宽走廊；
## scatter=中束连至柱 + 柱轴 ±45° 侧束各长 6；柱格必在命中集（每轮增幅必实际扣柱耐久）。
## 2-4 连爆链（快照阶段整链展开，总纲 §5.3/§6.3）：束格（主+副）命中未消耗节点入队，
## 队首节点 3×3 并入总命中集（走同一去重：格已在集=本轮已削过），范围内新节点续入队
## ——束格与爆炸格合并成一个总命中集后才进逐格结算，链序只用于表现。
## 返回 {cells/main/sub/refractor/chain_nodes/chain_cells/pillar}
func compute_shot_geometry(base: Vector2i, target: Vector2i) -> Dictionary:
	var main_cells: Array = []
	var refractor: RefractorRobot = null
	for c in LaserGeometry.beam_cells(base, target):
		main_cells.append(c)
		var r := refractor_at(c)
		if r != null:
			refractor = r
			break
	var cells: Array = main_cells.duplicate()
	var sub_cells: Array = []
	var fm := facility_manager()
	var pillar_coord := Vector2i(-9, -9)
	if fm != null:
		pillar_coord = fm.pillar_coord_alive()
	if refractor != null:
		if pillar_coord != Vector2i(-9, -9):
			# 2-5 定向：轴=折光→柱超覆盖线（不受 6 长限制，终止于柱、含柱格）
			var axis := LaserGeometry.beam_cells(refractor.coord, pillar_coord)
			var axis_dir := LaserGeometry.octant_dir(refractor.coord, pillar_coord)
			if refractor.config == "wide":
				var perp := Vector2i(-axis_dir.y, axis_dir.x)
				for off in [Vector2i.ZERO, perp, -perp]:
					for c in LaserGeometry.beam_cells(refractor.coord + off, pillar_coord + off):
						if not cells.has(c):
							cells.append(c)
							sub_cells.append(c)
			else:
				for c in axis:
					if not cells.has(c):
						cells.append(c)
						sub_cells.append(c)
				for side in [LaserGeometry.rotate_octant(axis_dir, 1),
						LaserGeometry.rotate_octant(axis_dir, -1)]:
					for c in LaserGeometry.beam_cells(refractor.coord,
							refractor.coord + side * 6):
						if not cells.has(c):
							cells.append(c)
							sub_cells.append(c)
		else:
			var prev: Vector2i = main_cells[main_cells.size() - 2] 					if main_cells.size() >= 2 else base
			var dir8 := LaserGeometry.octant_dir(prev, refractor.coord)
			for c in refractor.outgoing_cells(dir8):
				if not cells.has(c):
					cells.append(c)
					sub_cells.append(c)
	var chain_nodes: Array = []
	var chain_cells: Array = []
	if fm != null:
		var triggered: Dictionary = {}
		var queue: Array = []
		for c in cells:
			var n := fm.node_at(c)
			if n != null and not triggered.has(c):
				triggered[c] = true
				queue.append(n)
		while not queue.is_empty():
			var n: ChainNode = queue.pop_front()
			chain_nodes.append(n)
			for b in n.blast_cells(grid):
				if not cells.has(b):
					cells.append(b)
					chain_cells.append(b)
				var n2 := fm.node_at(b)
				if n2 != null and not triggered.has(b):
					triggered[b] = true
					queue.append(n2)
	return {"cells": cells, "main": main_cells, "sub": sub_cells, "refractor": refractor,
			"chain_nodes": chain_nodes, "chain_cells": chain_cells, "pillar": pillar_coord}


## 一次射击的完整结算（2-4 版）：compute_shot_geometry 快照（含连爆链整链展开）
## → 逐格结算（总命中集内同格本轮一次）——未开格走 grid.open_cell（削层/破墙开格/碎钻，
## 旗格/化石跳过照穿）；已开格：削覆盖墙 / 伤筑墙工（同轮各对象至多一次）；
## → 充能例外（总纲 §6.3"爆炸不充能"）：只认束格（主/副原始格集），爆炸格不给充能
## → 节点消耗（置 consumed + 占格解除 + 错峰演出）→ 信号/埋点
func fire(base: Vector2i, target: Vector2i) -> void:
	var geo := compute_shot_geometry(base, target)
	var hit: Array = geo.cells
	var charged_robots: Array = []
	var hit_builders: Dictionary = {}
	for c in hit:
		var cell: Cell = grid.get_cell(c)
		if cell == null:
			continue
		if cell.is_flagged or cell.is_fossil:
			continue
		if cell.is_opened:
			if cell.cover_wall_hp > 0:
				grid.damage_cover_wall_at(c, 1)
			if enemy_manager != null:
				for b in enemy_manager.builders:
					if is_instance_valid(b) and b.is_alive() and b.coord == c 						and not hit_builders.has(c):
						hit_builders[c] = true
						b.take_hit("player_laser")
			continue
		grid.open_cell(c, "player_laser")
	# 充能只认束格：主束 + 副束原始格集（机器人只站已开格，此处无需再判开闭）
	var beam_only: Array = geo.main.duplicate()
	for c in geo.sub:
		if not beam_only.has(c):
			beam_only.append(c)
	var rm = get_node_or_null("../RobotManager")
	if rm != null:
		for c in beam_only:
			for r in rm.robots:
				if (r.robot_type == "opener" or r.robot_type == "marker") 					and r.coord == c and not charged_robots.has(r):
					r.apply_charge(6.0)
					charged_robots.append(r)
	# 2-4 节点消耗：同轮触发标记已在快照 BFS 保证一次；消耗后格恢复普通（Q2）
	var fm := facility_manager()
	if fm != null and not geo.chain_nodes.is_empty():
		fm.consume_chain(geo.chain_nodes, grid)
	# 2-5 引光柱受击（结算序 ③：致命判定在全部奖励之后、达标判定之前；陈旧的
	# 延迟胜利由 main._end_game 的分数线复核拦下——350+20-50=320 不判胜）。
	# 来源汇总（同轮去重后合计扣 1）：定向轴命中 / 直射束穿柱格 / 爆炸 3×3 波及
	if fm != null and fm.pillar != null and is_instance_valid(fm.pillar) and hit.has(fm.pillar.coord):
		var fatal := fm.pillar.take_hit()
		GameState.result_stats["pillar_hits"] += 1
		if fatal:
			GameState.add_score(-50, "pillar")
			GameState.result_stats["pillar_broken"] += 1
			fm.on_pillar_broken(grid)
			pillar_broken.emit()
	_register_recent_opened(geo.main)
	_play_beam_fx(base, target, geo)
	if geo.get("refractor", null) != null:
		refractor_activated.emit(geo.refractor)
	if not charged_robots.is_empty():
		robots_charged.emit(charged_robots)
	if not geo.chain_nodes.is_empty():
		chain_triggered.emit(geo.chain_nodes)
	GameState.result_stats["shots_fired"] += 1
	GameState.result_stats["beam_cells_total"] += hit.size()
	laser_fired.emit(target)
	laser_resolved.emit(target)


## 2-2 备用：记录激光打出的格（开格/破墙/碎钻都算"被激光拆过"）
func _register_recent_opened(beam: Array) -> void:
	var now: float = GameState.elapsed
	for c in beam:
		recent_laser_opened[c] = now
	for c in recent_laser_opened.keys():
		if now - float(recent_laser_opened[c]) > RECENT_WINDOW_SEC:
			recent_laser_opened.erase(c)


func _play_beam_fx(base: Vector2i, target: Vector2i, geo: Dictionary = {}) -> void:
	var fx: EffectsLayer = grid.get_node_or_null("EffectsLayer") as EffectsLayer
	if fx == null:
		return
	# 坐标系注意（2026-10-10 修复）：EffectsLayer 是 Grid 子节点，吃 Grid 本地系；
	# 此前误传 BoardRoot 本地的 coord_to_world 输出，束整体偏移一个 grid.position
	# （探针实测：BASE 格全局 (500,320)，束全局 (959,430)=多加了一次 (458,110)）
	fx.fx_laser_flash(_cell_local(base), _cell_local(target))
	if geo != null and geo.get("refractor", null) != null:
		# 副束示意闪光（折光格→出射区质心；一束示意避免多线糊屏，逐格命中已由结算保证）
		var sub: Array = geo.get("sub", [])
		if not sub.is_empty():
			var sum := Vector2.ZERO
			for c in sub:
				sum += Vector2(c)
			fx.fx_laser_flash(_cell_local(geo.refractor.coord),
					_cell_local(Vector2i((sum / sub.size()).round())))
	fx.fx_base_flash(grid.get_cell(base))  # 炮口=基地短亮（复用出厂"工厂开工"语言）


## 格心 → Grid 本地像素（EffectsLayer 坐标系；格节点缺失时按公式兜底）
func _cell_local(c: Vector2i) -> Vector2:
	var cell: Cell = grid.get_cell(c)
	if cell != null:
		return cell.position
	return Vector2(c.x * grid.cell_size + grid.cell_size / 2.0,
			c.y * grid.cell_size + grid.cell_size / 2.0)


# ---- 悬停预览（公开几何，与结算共用 LaserGeometry；不泄雷，总纲 §4.5）----

func _on_cell_hovered(cell: Cell) -> void:
	if not is_laser_level() or not GameState.game_active or get_tree().paused:
		grid.hide_laser_preview()
		return
	var base := _shot_origin()
	if base == Vector2i(-1, -1) or base == cell.coord:
		grid.hide_laser_preview()
		return
	# 2-4 WP3：预览=束格 ∪ 整条链格集（同一 BFS 公开几何），节点格用专属描边；
	# 2-5 WP2：本次将命中柱 → 柱格预警描边；hp≤2 束段变暗红、hp==1 弹「将破碎」文案
	var geo := compute_shot_geometry(base, cell.coord)
	var marks: Array = []
	for n in geo.chain_nodes:
		marks.append(n.coord)
	var pillar_info: Dictionary = {}
	var fm := facility_manager()
	if fm != null and fm.pillar != null and is_instance_valid(fm.pillar) \
			and fm.pillar.is_alive and geo.cells.has(fm.pillar.coord):
		pillar_info = {"coord": fm.pillar.coord, "hp": fm.pillar.hp}
	grid.show_laser_preview(cell.coord, geo.cells, false, marks, pillar_info)


func _on_cell_unhovered(_cell: Cell) -> void:
	grid.hide_laser_preview()
