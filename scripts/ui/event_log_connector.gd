class_name EventLogConnector
extends Node
## 事件→侧栏日志路由器（旁听模式，接入姿势照抄 AudioConnector，不改玩法逻辑）：
##   by_actor == "player" → 左栏（玩家行动流）；robot_* → 右栏（机器人作业流）
## 信号覆盖不到的事件（购机/建基地/断触手/Boss 拆弹灭火）由调用处 emit
## GameState.game_event_logged(text, side, color) 兜底进流。
##
## 开格统一走 cell_open_batch 并按帧聚合：chord 会对每个邻居各发一个 batch=1，
## 直接上屏一次双击会刷出一串"开格 +1金"。

const NAMES := {"opener": "开墙", "marker": "标雷", "detector": "检测", "miner": "矿工",
	"guard": "保安", "fire": "火焰"}
const OBSTACLES := {"web": "蛛网", "lock": "锁链", "slime": "黏液"}
const IDLE_REASONS := {"opener": "暂无可推理目标", "marker": "暂无可推理目标",
	"detector": "暂无可检测旗位", "miner": "暂无可采矿脉"}
const REMOVE_REASONS := {"detect_failed": "检测 自爆（未探得）"}
const UPGRADE_NAMES := {"opener_speed": "开墙速度", "marker_speed": "标雷速度",
	"opener_work": "开墙工作", "marker_work": "标雷工作", "recharge": "回充"}

const C_PLAYER := "#ffc861"   # 琥珀金：玩家
const C_ROBOT := "#7fd8d0"    # 青：机器人
const C_DANGER := "#ff7a6e"
const C_GOOD := "#9fe08a"
const C_DIM := "#b0a48e"

var _player_log: PanelContainer
var _robot_log: PanelContainer
var _robot_manager: Node
var _frame_opens := {}   # side → {"count": int, "flushed": bool}：同帧批次聚合
var _idle_all := {}      # type → bool：是否处于"全员空闲已播报"状态（边沿触发只报一次）

func _ready() -> void:
	var layer := get_parent()
	_player_log = layer.get_node("PlayerLogPanel")
	_robot_log = layer.get_node("RobotLogPanel")
	_player_log.setup("你的行动")
	_robot_log.setup("机器人作业")

	var main := layer.get_parent()
	_robot_manager = main.get_node("RobotManager")
	var grid: Node = main.get_node("Grid")
	grid.cell_open_batch.connect(_on_open_batch)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.cell_unflagged.connect(_on_cell_unflagged)
	grid.mine_stepped.connect(func(_c, _a): _player("踩雷！损失一命", C_DANGER))
	grid.obstacle_cleared.connect(_on_obstacle_cleared)
	grid.vein_created.connect(func(_c): _robot("检测 探得矿脉", C_GOOD))
	grid.vein_depleted.connect(func(_c): _robot("矿工 矿脉采空", C_DIM))
	grid.cargo_unloaded.connect(func(_p, amount: int): _robot("矿工 卸货 +%d金" % amount, C_ROBOT))
	main.get_node("EnemyManager").enemy_killed.connect(_on_enemy_killed)
	_robot_manager.robot_removed.connect(_on_robot_removed)
	GameState.game_event_logged.connect(_on_game_event_logged)
	GameState.upgrade_changed.connect(_on_upgrade_changed)
	GameState.game_over.connect(_on_game_over)

	var t := Timer.new()   # 空闲边沿检测低频轮询（沿用旧 TeamPanel 的节奏）
	t.wait_time = 0.5
	t.timeout.connect(_poll_idle)
	add_child(t)
	t.start()


func clear_logs() -> void:
	_player_log.clear_log()
	_robot_log.clear_log()
	_idle_all.clear()


# ---- 棋盘事件 ----

func _on_open_batch(_cell, by_actor: String, opened: Array) -> void:
	var side := "player" if by_actor == "player" else "robot"
	var acc: Dictionary = _frame_opens.get_or_add(side, {"count": 0, "flushed": false})
	acc.count += opened.size()
	if not acc.flushed:
		acc.flushed = true
		_flush_opens.call_deferred(side)


func _flush_opens(side: String) -> void:
	var acc: Dictionary = _frame_opens[side]
	acc.flushed = false
	var n: int = acc.count
	acc.count = 0
	if n <= 0:
		return
	if side == "player":
		_player("你 开了 %d 格 +%d金" % [n, n] if n > 1 else "你 开格 +1金", C_PLAYER)
	else:
		_robot("开墙 连开 %d 格 +%d金" % [n, n] if n > 1 else "开墙 开格 +1金", C_ROBOT)


func _on_cell_flagged(_cell, by_actor: String, correct: bool, first_time: bool) -> void:
	if by_actor == "player":
		if correct:
			_player("你 标旗 ✓ +5金" if first_time else "你 标旗 ✓", C_PLAYER)
		else:
			_player("你 标错旗 ✗", C_DANGER)
	elif by_actor == "robot_marker":
		_robot("标雷 标旗 ✓ +5金" if first_time else "标雷 标旗 ✓", C_ROBOT)


func _on_cell_unflagged(_cell, by_actor: String) -> void:
	if by_actor == "player":
		_player("你 撤旗", C_DIM)
	elif by_actor == "robot_marker":
		_robot("标雷 拔旗", C_DIM)


func _on_obstacle_cleared(_cell, kind: String, by_actor: String) -> void:
	var what: String = OBSTACLES.get(kind, kind)
	if by_actor == "player":
		_player("你 清除%s" % what, C_PLAYER)
	else:
		_robot("保安 清除%s" % what, C_ROBOT)


func _on_enemy_killed(_enemy, by_actor: String) -> void:
	if by_actor == "player":
		_player("你 击退虫子 +10金", C_PLAYER)
	else:
		_robot("保安 击退虫子 +10金", C_ROBOT)


func _on_robot_removed(robot, reason: String) -> void:
	var line: String = REMOVE_REASONS.get(reason,
		"%s 退役" % NAMES.get(robot.robot_type, "机器人"))
	_robot(line, C_DANGER)


# ---- GameState 事件 ----

func _on_game_event_logged(text: String, side: String, color: String) -> void:
	var c: String = {"player": C_PLAYER, "robot": C_ROBOT, "danger": C_DANGER,
		"good": C_GOOD, "dim": C_DIM}.get(color, C_PLAYER)
	if side == "robot":
		_robot(text, c)
	else:
		_player(text, c)


func _on_upgrade_changed(upgrade_id: String, new_level: int) -> void:
	_player("升级 %s Lv%d" % [UPGRADE_NAMES.get(upgrade_id, upgrade_id), new_level], C_PLAYER)


func _on_game_over(result: String) -> void:
	var text: String = "本局结束：" + str({"win": "胜利", "lose": "失败", "timeout": "时间到"}.get(result, result))
	_player(text, C_GOOD if result == "win" else C_DIM)
	_robot(text, C_GOOD if result == "win" else C_DIM)


# ---- 空闲播报（旧 TeamPanel 的"空闲原因"迁移：全员空闲时只报一次，恢复不报）----

func _poll_idle() -> void:
	# 显隐挂 game_active（沿用旧侧栏口径；结算/菜单期全屏面板盖住，隐藏不抢戏）
	var active: bool = GameState.game_active
	_player_log.visible = active
	_robot_log.visible = active
	if not active:
		return
	var counts := {}
	var idles := {}
	for r in _robot_manager.robots:
		if not IDLE_REASONS.has(r.robot_type):
			continue   # 保安无空闲概念（is_idle 恒 false）
		counts[r.robot_type] = counts.get(r.robot_type, 0) + 1
		if r.is_idle():
			idles[r.robot_type] = idles.get(r.robot_type, 0) + 1
	for type in counts:
		var all_idle: bool = idles.get(type, 0) == counts[type]
		if all_idle and not _idle_all.get(type, false):
			_robot("%s 空闲：%s" % [NAMES[type], IDLE_REASONS[type]], C_DIM)
		_idle_all[type] = all_idle


# ---- 输出 ----

func _player(text: String, color: String) -> void:
	_player_log.log_event("[color=%s]%s[/color]" % [color, text])


func _robot(text: String, color: String) -> void:
	_robot_log.log_event("[color=%s]%s[/color]" % [color, text])
