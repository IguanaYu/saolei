class_name GuildDayManager
extends Node
## 冒险者工会·营业日管理器（ch04 试验章）
## 设计：docs/active/玩法设计/冒险者工会-玩法设计文档-v0.1.md
## 计划：docs/active/玩法设计/冒险者工会-实施计划-2026-10-20.md
##
## WP1 骨架职责：
##   工时账本——手动有效调查（开格/插旗）扣工时，每批开放一笔、可结转、不可预支；
##   三批推进——准备 → 发布 → 探索(占位结算) → 反馈，第三批发布完 = 营业日结束；
##   动作闸门——工时不足/非准备阶段时拦下玩家开格与插旗（grid.action_gate）。
## 需求分配/据点强度/工作队/真实结算在 WP2-WP4 逐层加进来。
## 非工会关 active=false，一切挂接no-op（连接常驻，免每次进关重连）。

signal guild_state_changed(batch_index: int, phase: String, hours_left: int, hours_granted: int)
signal batch_resolved(batch_index: int, summary: Dictionary)
signal day_finished
signal action_blocked(reason: String)

const BATCH_COUNT := 3
const HOURS_PER_BATCH := 100          # 每批开放工时（实施计划 D9 原型值，未验证）
const COST_MANUAL_OPEN := 1           # 手动开格一次（同帧连锁只扣一次）
const COST_MANUAL_FLAG := 1           # 手动插旗一次（撤旗免费，同 WP7 防刷口径）

var active := false                   # 本关是否工会模式
var batch_index := 0                  # 当前准备中的批次（0 基）
var phase := "prepare"                # prepare=准备/调查中 resolving=结算中 done=营业日结束
var hours_granted := 0                # 全天累计开放工时
var hours_spent := 0                  # 全天累计消耗工时
var grid: Grid = null

# 一次点击触发的洪水/和弦展开全发生在同一帧：同帧只扣一次工时
var _open_charged_frame := -1

var hours_left: int:
	get: return hours_granted - hours_spent


## 进关装载（main._start_level_with 调用）。非工会关 active=false 且不碰 grid
func setup_for_level(lvl: LevelData, grid_ref: Grid) -> void:
	grid = grid_ref
	if not lvl.guild_mode:
		active = false
		return
	active = true
	batch_index = 0
	phase = "prepare"
	hours_granted = HOURS_PER_BATCH
	hours_spent = 0
	_open_charged_frame = -1
	GameState.result_stats["guild_hours_spent"] = 0
	GameState.result_stats["guild_batches_published"] = 0
	_emit_state()
	GameState.game_event_logged.emit("工会开张：第 1 批开放前，先调查出能用的安全区", "player", "info")


## 玩家动作闸门（grid.action_gate 调用）：true=放行，false=拦截并提示
## 非工会关恒放行；工会关要求 准备阶段 + 工时充足
func can_player_act() -> bool:
	if not active:
		return true
	if phase == "done":
		action_blocked.emit("营业日已结束")
		return false
	if phase != "prepare":
		action_blocked.emit("冒险者正在探索，等他们回来再继续调查")
		return false
	if hours_left < COST_MANUAL_OPEN:
		action_blocked.emit("工时耗尽：发布本批，让冒险者出发吧")
		return false
	return true


## 扣工时（闸门放行后的实际入账；队伍/后续系统的扣口）
func spend(cost: int) -> void:
	if not active:
		return
	hours_spent = mini(hours_spent + cost, hours_granted)  # 防负：账面不为负
	GameState.result_stats["guild_hours_spent"] = hours_spent
	_emit_state()


## 发布本批：准备→结算→下一批开放工时（结转=余量天然保留）；第三批后营业日结束。
## WP1 结算是占位（无需求分配，summary 全零）；WP4 换真实分配
func publish_batch() -> void:
	if not active or phase != "prepare":
		return
	phase = "resolving"
	_emit_state()
	GameState.result_stats["guild_batches_published"] = batch_index + 1
	# 占位结算：设计 §6.3 结果表在 WP4 实装；此处仅推进账期
	var summary := {"completed": 0, "unmet": 0, "casualties": 0, "income": 0}
	GameState.game_event_logged.emit("第 %d 批冒险者出发了" % (batch_index + 1), "player", "info")
	batch_resolved.emit(batch_index, summary)
	if batch_index >= BATCH_COUNT - 1:
		phase = "done"
		_emit_state()
		GameState.game_event_logged.emit("最后一批回来了——营业日结束，开始结算", "player", "info")
		day_finished.emit()
	else:
		batch_index += 1
		hours_granted += HOURS_PER_BATCH  # 结转口径：余量未清零，新一批只加不减
		phase = "prepare"
		_emit_state()
		GameState.game_event_logged.emit("第 %d 批整备中：新开放 %d 工时（余量结转）" % [batch_index + 1, HOURS_PER_BATCH], "player", "info")


# ---- grid 信号挂接（main._ready 常驻连接；非工会关早退）----

func _on_cell_opened(_cell, by_actor: String) -> void:
	if not active or by_actor != "player":
		return
	var frame := Engine.get_process_frames()
	if frame == _open_charged_frame:
		return  # 同帧连锁（洪水/和弦）只扣一次
	_open_charged_frame = frame
	spend(COST_MANUAL_OPEN)


func _on_cell_flagged(_cell, by_actor: String, _correct: bool, first_time: bool) -> void:
	if not active or by_actor != "player" or not first_time:
		return  # 撤旗重插不重复扣（同 main._on_cell_flagged WP7 防刷口径）
	spend(COST_MANUAL_FLAG)


func _emit_state() -> void:
	guild_state_changed.emit(batch_index, phase, hours_left, hours_granted)
