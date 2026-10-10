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


## 一次射击的完整结算（2-2 版）：束格统一去重——
## 未开格走 grid.open_cell（hp>1 削层 / hp<=1 破墙开格或碎钻，旗格跳过光束继续）；
## 已开格：削覆盖墙 / 充能作业机器人 / 伤筑墙工（同轮各对象至多一次，总纲 §5.3）
func fire(base: Vector2i, target: Vector2i) -> void:
	var beam := LaserGeometry.beam_cells(base, target)
	var charged_robots: Array = []
	var hit_builders: Dictionary = {}
	for c in beam:
		var cell: Cell = grid.get_cell(c)
		if cell == null:
			continue
		if cell.is_flagged or cell.is_fossil:
			continue  # 旗格受保护（光束继续）；化石无伤害交互（ch02 不布化石，防御）
		if cell.is_opened:
			# 2-2 已开格三件事（同轮去重天然保证"每格削 1 层/每台充 1 次/每敌 1 伤"）
			if cell.cover_wall_hp > 0:
				grid.damage_cover_wall_at(c, 1)
			if enemy_manager != null:
				for b in enemy_manager.builders:
					if is_instance_valid(b) and b.is_alive() and b.coord == c 							and not hit_builders.has(c):
						hit_builders[c] = true
						b.take_hit("player_laser")
			var rm = get_node_or_null("../RobotManager")
			if rm != null:
				for r in rm.robots:
					if (r.robot_type == "opener" or r.robot_type == "marker") 							and r.coord == c and not charged_robots.has(r):
						r.apply_charge(6.0)
						charged_robots.append(r)
			continue
		grid.open_cell(c, "player_laser")
	_register_recent_opened(beam)
	_play_beam_fx(base, target)
	if not charged_robots.is_empty():
		robots_charged.emit(charged_robots)
	GameState.result_stats["shots_fired"] += 1
	GameState.result_stats["beam_cells_total"] += beam.size()
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


func _play_beam_fx(base: Vector2i, target: Vector2i) -> void:
	var fx: EffectsLayer = grid.get_node_or_null("EffectsLayer") as EffectsLayer
	if fx == null:
		return
	fx.fx_laser_flash(grid.coord_to_world(base), grid.coord_to_world(target))
	fx.fx_base_flash(grid.get_cell(base))  # 炮口=基地短亮（复用出厂"工厂开工"语言）


# ---- 悬停预览（公开几何，与结算共用 LaserGeometry；不泄雷，总纲 §4.5）----

func _on_cell_hovered(cell: Cell) -> void:
	if not is_laser_level() or not GameState.game_active or get_tree().paused:
		grid.hide_laser_preview()
		return
	var base := _shot_origin()
	if base == Vector2i(-1, -1) or base == cell.coord:
		grid.hide_laser_preview()
		return
	grid.show_laser_preview(cell.coord, LaserGeometry.beam_cells(base, cell.coord))


func _on_cell_unhovered(_cell: Cell) -> void:
	grid.hide_laser_preview()
