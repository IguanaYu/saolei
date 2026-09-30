class_name BossManager
extends Node2D
## L5 Boss 总控（设计 §3/§5 / 实施计划 WP2）：牙数=血量驱动三阶段状态机，
## 出招时点表调度（M2-M4 逐阶段填实），硬直/转场出招暂停，斩杀演出流程。
## 由 main._process 驱动 tick——game_active=false（暂停/结算/斩杀冻结）时天然停摆。

signal phase_changed(phase: int)      # 转场完成（演出+暂停结束后）
signal kill_sequence_done             # 斩杀掉落演出完毕 → main 走胜利结算
signal boss_staggered(duration: float)

## 阶段门槛（牙数，设计 §3）：拔到第 6 颗进 P2、第 12 颗进 P3
const PHASE_TEETH := [5, 11]
const TRANSITION_PAUSE_SEC := 3.0     # 转场后出招暂停（设计 §3）
const KILL_FALL_SEC := 3.0            # 斩杀掉落演出时长（设计 §5.4）

## 出招时点表（M2-M4 填实；tick 里按 kind 分发到对应 WP 的实现）
## 每条：{"kind": String, "every": sec, "cap": int 同场上限, "first": sec 首次时点, "next": 运行态}
## 注意：不能是 const——Godot 4 的 const 容器深只读，next 计时需要运行时可写
static func _build_attacks() -> Dictionary:
	return {
		1: [
			# M2/WP3：史莱姆——first=15 首次入场，补位逻辑在 WP3 单独处理
			{"kind": "slime_intro", "every": 0.0, "cap": 2, "first": 15.0, "next": 0.0},
		],
		2: [
			# M3/WP4：定时落弹
			{"kind": "bomb", "every": 18.0, "cap": 2, "first": 5.0, "next": 0.0},
		],
		3: [
			# M4/WP5：锁链 + 触手 + 降频落弹
			{"kind": "lock", "every": 25.0, "cap": -1, "first": 4.0, "next": 0.0},
			{"kind": "tentacle", "every": 30.0, "cap": 2, "first": 8.0, "next": 0.0},
			{"kind": "bomb", "every": 35.0, "cap": 1, "first": 14.0, "next": 0.0},
		],
	}

var _attacks := _build_attacks()

var phase := 1
var active := false                  # 是否处于 Boss 局（FIND_ALL_MINES 目标关）
var _teeth := 0
var _total_teeth := 20
var _elapsed := 0.0                  # Boss 自己的局内钟（转场/硬直会冻结出招但不重置）
var _staggered_until := -1.0
var _pause_until := 0.0              # 转场出招暂停
var _beast: BossBeast
var _grid = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE  # 场景暂停（面板）时随主场景停


## 进关 setup（main 在 FIND_ALL_MINES 关调用）：盘外锚点定位 + 姿态初值
func setup(grid, total_teeth: int) -> void:
	clear()
	active = true
	_grid = grid
	_total_teeth = max(1, total_teeth)
	_teeth = 0
	phase = 1
	_elapsed = 0.0
	_staggered_until = -1.0
	_pause_until = 0.0
	_beast = BossBeast.new()
	_beast.name = "BossBeast"  # 显式命名防遍历误匹配
	add_child(_beast)
	_beast.layout(grid.cell_size)
	_beast.teleport_to("top", top_anchor_pos(grid))
	_beast.play("claw", 1.5)  # 入场亮爪（与放基地并行的开场演出）


func top_anchor_pos(grid) -> Vector2:
	# 上侧盘框中段：第一行中点向外偏 1.6 格（巨兽趴框上，爪子伸进上边缘）
	var mid := Vector2i(grid.cols / 2, 0)
	return grid.coord_to_world(mid) + Vector2(0, -grid.cell_size * 1.6)


func right_anchor_pos(grid) -> Vector2:
	var mid := Vector2i(grid.cols - 1, grid.rows / 2)
	return grid.coord_to_world(mid) + Vector2(grid.cell_size * 1.6, 0)


## 由 main 转发 grid.processed_mines_changed（牙数即血量）
func on_teeth_changed(current: int) -> void:
	_teeth = current
	var target := 1
	if _total_teeth >= 12:
		target = 3 if current > PHASE_TEETH[1] else (2 if current > PHASE_TEETH[0] else 1)
	else:
		target = 2 if current > _total_teeth / 2 else 1
	if target > phase and active:
		_transition_to(target)


func _transition_to(target: int) -> void:
	phase = target
	_beast.set_phase(target)
	_staggered_until = _elapsed + 1.0   # 转场硬直感
	_pause_until = _elapsed + TRANSITION_PAUSE_SEC
	for atk in _attacks.get(target, []):
		atk["next"] = _elapsed + float(atk["first"])
	if target == 3:
		# 换位：上侧 → 右侧（设计 §5.3），沿盘框外缘爬过去
		var corner: Vector2 = _grid.coord_to_world(Vector2i(_grid.cols - 1, 0)) \
				+ Vector2(_grid.cell_size * 1.6, -_grid.cell_size * 1.6)
		_beast.crawl_to("right", corner, right_anchor_pos(_grid), 2.0)
	phase_changed.emit(target)


## 硬直（点杀史莱姆/反弹炸弹等触发）：出招计时冻结 + 姿态反馈
func stagger(sec: float) -> void:
	_staggered_until = max(_staggered_until, _elapsed + sec)
	if _beast != null:
		_beast.play("staggered", sec)
	boss_staggered.emit(sec)


## 出招顺延（反弹奖励：下次该类招式 +7s，设计 §5.2）
func delay_attack(kind: String, sec: float) -> void:
	for atk in _attacks.get(phase, []):
		if atk["kind"] == kind:
			atk["next"] += sec


## main._process 驱动（game_active=false 时不会被调用 = 全场冻结）
func tick(delta: float, grid) -> void:
	if not active:
		return
	_elapsed += delta
	var frozen := _elapsed < _pause_until or _elapsed < _staggered_until
	if frozen:
		return
	for atk in _attacks.get(phase, []):
		if atk["every"] <= 0.0:
			continue  # 一次性出招（如 slime_intro）由专门逻辑处理
		if _elapsed >= float(atk["next"]):
			atk["next"] = _elapsed + float(atk["every"])
			_try_cast_attack(atk, grid)


## 单次出招分发（M2-M4 实现各 kind；未知 kind 静默跳过=安静 Boss 关可玩）
func _try_cast_attack(atk: Dictionary, grid) -> void:
	match atk["kind"]:
		"slime_intro":
			pass  # WP3
		"bomb":
			pass  # WP4
		"lock":
			pass  # WP5
		"tentacle":
			pass  # WP5


## 斩杀流程（main 在第 20 颗牙时调用；调用前 main 已置 game_active=false 冻结全场）
func begin_kill_sequence() -> void:
	if _beast == null:
		kill_sequence_done.emit()
		return
	_beast.pose_finished.connect(
			func(_p): kill_sequence_done.emit(), CONNECT_ONE_SHOT)
	_beast.play("fall", KILL_FALL_SEC)


## 局末/重开清理（main._start_level_with 与结算路径调用）
func clear() -> void:
	active = false
	phase = 1
	_teeth = 0
	_elapsed = 0.0
	_staggered_until = -1.0
	_pause_until = 0.0
	_grid = null
	if _beast != null:
		_beast.queue_free()
		_beast = null
	for phase_key in _attacks:
		for atk in _attacks[phase_key]:
			atk["next"] = 0.0
