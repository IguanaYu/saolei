class_name AudioConnector
extends Node
## 信号→音效连接器：旁听现有信号，不改玩法逻辑
## 连锁开格聚合：flood fill 同帧同步 emit 完才跑 deferred flush → 一串上行音阶

var _frame_opens: int = 0
var _flush_base_pitch: float = 1.0
var _last_ceil_sec: int = 999


func _ready() -> void:
	var main := get_parent()
	var grid: Node = main.get_node("Grid")
	grid.cell_opened.connect(_on_cell_opened)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.mine_stepped.connect(func(_c, _a): AudioManager.play_sfx("mine"))
	GameState.upgrade_changed.connect(func(_id, _lv): AudioManager.play_sfx("upgrade"))
	GameState.game_over.connect(_on_game_over)
	GameState.time_changed.connect(_on_time_changed)


func _on_cell_opened(_cell, by_actor: String) -> void:
	if by_actor == "drone":
		return  # 无人机开格不配音（快速多点，避免吵）
	_flush_base_pitch = 1.0 if by_actor == "player" else 0.85
	_frame_opens += 1
	if _frame_opens == 1:
		_flush_opens.call_deferred()


func _flush_opens() -> void:
	var n: int = mini(_frame_opens, 4)  # 连击封顶 4 声
	var base: float = _flush_base_pitch
	_frame_opens = 0
	for i in n:
		AudioManager.play_sfx("open", base * (1.0 + 0.09 * i), 0.035 * i)


func _on_cell_flagged(_cell, _by_actor: String, correct: bool, first_time: bool) -> void:
	if not first_time:
		return  # 撤旗/重插不响
	AudioManager.play_sfx("flag", 1.0 if correct else 0.8)


func _on_game_over(result: String) -> void:
	match result:
		"win":
			AudioManager.play_sfx("win")
		"lose":
			AudioManager.play_sfx("lose")
		_:
			AudioManager.play_sfx("win", 0.95)  # timeout=正常结算，不播失败音


func _on_time_changed(v: float) -> void:
	# time_changed 每帧 emit：整秒去重；最后 10 秒心跳，越紧急 pitch 越尖
	var s := ceili(v)
	if s == _last_ceil_sec:
		return
	_last_ceil_sec = s
	if s > 0 and s <= 10:
		AudioManager.play_sfx("heartbeat", 1.0 + (10 - s) * 0.02)
