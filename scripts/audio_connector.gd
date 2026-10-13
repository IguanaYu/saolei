class_name AudioConnector
extends Node
## 信号→音效连接器：旁听现有信号，不改玩法逻辑
## 连锁开格聚合：flood fill 同帧同步 emit 完才跑 deferred flush → 一串上行音阶

var _frame_opens: int = 0
var _flush_base_pitch: float = 1.0
var _last_ceil_sec: int = 999


func reset_for_level() -> void:
	_frame_opens = 0
	_last_ceil_sec = 999


func _ready() -> void:
	var main := get_parent()
	var grid: Node = main.get_node("BoardRoot/Grid")
	grid.cell_opened.connect(_on_cell_opened)
	grid.cell_flagged.connect(_on_cell_flagged)
	grid.wall_damaged.connect(func(_c, _a, _l): AudioManager.play_sfx("wall_chip"))
	grid.cover_wall_damaged.connect(func(_c, left):
		AudioManager.play_sfx("wall_break" if left == 0 else "wall_chip"))
	grid.diamond_shattered.connect(func(_c, _a): AudioManager.play_sfx("wall_break", 1.35))
	var laser: LaserManager = main.get_node("BoardRoot/LaserManager")
	laser.laser_fired.connect(func(_c): AudioManager.play_sfx("laser"))
	laser.robots_charged.connect(func(_r): AudioManager.play_sfx("charge"))
	laser.ore_burst.connect(func(_o, _c): AudioManager.play_sfx("ore_burst"))
	laser.overload_blast.connect(func(_r, _c): AudioManager.play_sfx("overload"))
	# 踩雷：玩家原调、机器人低沉（与开格音 pitch 惯例一致）
	grid.mine_stepped.connect(func(_c, by_actor: String): AudioManager.play_sfx("mine", 1.0 if by_actor == "player" else 0.85))
	GameState.upgrade_changed.connect(func(_id, _lv): AudioManager.play_sfx("upgrade"))
	GameState.game_over.connect(_on_game_over)
	GameState.time_changed.connect(_on_time_changed)


func _on_cell_opened(_cell, by_actor: String) -> void:
	if by_actor == "drone":
		return  # 无人机开格不配音（快速多点，避免吵）
	if by_actor == "player_laser":
		AudioManager.play_sfx("wall_break")  # 一枪开多格受节流聚合，不叠通用开格音
		return
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
	_frame_opens = 0
	AudioManager.clear_sfx()
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
