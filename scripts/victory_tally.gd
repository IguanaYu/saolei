class_name VictoryTally
extends Node
## 胜利结算演出编排（docs/active/胜利结算算分动画-方案-v1.md，2026-10-12 四点拍板+复看调整）
## 胜利瞬间先在棋盘上把账演一遍，再弹结算面板（L5 Boss「先演出后结算」同思路）：
##   ①旗子逐面弹跳 +「+5」飘字；②已开格波纹逐圈弹跳 + 合并「+N」——两段是复述
##     局内已给的分：总分数字先退回「没算这些项」的起点，之后每落一拍真的涨一格，
##     收在真实总分（动的只是显示，账目不重复记）
##   ③剩余的命逐颗弹跳 +「+20」—— 真实入账（life_bonus）
##   ④剩余时间马里奥式加速清零，总分按每秒系数同步滚涨 —— 显示先行，真实入账由
##     main._apply_time_bonus 在收尾统一做（账本只落一条 time_bonus）
##   ⑤剩余金币折分：金币流飞向总分、钱数清零/分数对滚（1 枚 = 1 分）—— 显示先行，
##     真实入账由 main._apply_money_bonus 在收尾统一做（金币清零、只落一条 money_bonus）
## 总分脉冲幅度随演出进度递增，收尾一拍最大（复看拍板：越往后跳得越大）。
## 点击/空格跳过：未入账的命分一次性补齐，数字直接定格真实总分，面板秒弹。
## 收尾发 finished 信号 → main._finish_victory_tally 入账时间分 + win_score 快照 + 弹面板。
## 演出期间树不暂停（结算期现状）、game_active=false 已拦棋盘输入，格子/飘字照常播放。

signal finished

const FLAG_STEP := 0.24        # 旗子逐面间隔（复看两轮放缓后的现值）
const FLAG_TIME_CAP := 3.8     # 旗多时压缩步长，总时长封顶（复看②：全标雷的旗段要看得清）
const RING_STEP := 0.17        # 开格波纹逐圈间隔
const RING_TIME_CAP := 3.6     # 波纹总时长封顶（30×30 大图自动提速）
const HEART_STEP := 0.30       # 红心逐颗间隔
const LIFE_BONUS_PER := 20     # 每条命 +20 分（拍板 #1）
const MARIO_TIME_CAP := 2.1    # 倒计时换分时长封顶
const MARIO_MIN_TIME := 0.55   # 剩余秒很少时的下限
const FLAG_POINTS := 5         # 每面正确旗局内已给的分（与 main._on_cell_flagged 同口径）
const OPEN_POINTS := 1         # 每个开格局内已给的分
const FINAL_HOLD := 0.6        # 收尾大脉冲后面板出现前的定格
const TICK_PITCH_MAX := 1.6    # 「叮」升调上限
const TICK_MIN_GAP_MS := 45    # 倒计时滴答最短间隔（防百次/秒刷屏爆音）
# 剩余金币折分（复看追加分）：金币逐枚飞向总分，1 枚 = 1 分（真实入账在收尾）
const MONEY_BONUS_PER := 1
const MONEY_TIME := 1.35       # 折分时长（金币流+双数字对滚）
const MONEY_COINS_SHOWN := 14  # 视觉金币枚数封顶（钱多时一枚代表多枚，数字照实滚）
const COIN_TEX := preload("res://visual_v2/runtime/ui/icons/icon_coin.png")
# 分数飞字（复看③：旗子/倒计时的加 分也像金币一样"飞进"总分）
const FLY_FONT_SIZE := 12
const FLY_TIME := 0.48         # 单个飞字飞行时长
const MARIO_FLYERS := 10       # 倒计时换分的飞字个数上限
# 总分脉冲幅度随演出进度递增（复看拍板：越往后跳得越大，收尾最大）
const PULSE_STRENGTH_MIN := 1.2
const PULSE_STRENGTH_MAX := 1.5
const PULSE_STRENGTH_FINAL := 1.65

var _grid: Grid = null
var _hud = null  # hud.gd 无 class_name，按鸭子类型调用
var _fx: EffectsLayer = null
var _active := false
var _master: Tween = null
var _pitch_idx := 0
var _lives_total := 0
var _hearts_done := 0
# 总分滚动显示（复看拍板：每落一拍数字真的涨一格；起点=最终分−复述合计，
# 收在真实总分——动的只是显示，账目不重复记）
var _disp_score := 0
var _beat_idx := 0
var _beat_total := 1
var _mario := {"on": false, "secs": 0, "per": 0, "base": 0, "last_disp": -1, "last_tick_ms": 0}
var _money := {"on": false, "total": 0, "base": 0, "last_step": -1}
var _time_backup := {"saved": false, "text": "", "color": Color.WHITE}


func is_active() -> bool:
	return _active


## 播放范围（拍板规则）：棋盘结算型胜利才播；分数达标型（REACH_SCORE＝第二章全章）
## 不播——分是打的过程中实时涨的，达标瞬间再逐项复述显重复（2-1 教学会让玩家
## 插旗，"盘上有旗"不能当判据，实测踩过：面板被延迟弹出）。盘上无可演项同样不播；
## 失败路径根本不进本脚本。
func should_play(g: Grid) -> bool:
	var obj := GameState.current_objective
	if obj != null and obj.type == ObjectiveData.Type.REACH_SCORE:
		return false
	return _current_flag_cells(g).size() > 0 \
			or (GameState.has_life_limit() and GameState.lives > 0)


## 演出编排入口。time_info = main._compute_time_bonus() 的 {secs, per, bonus}；
## wave_center = main 记录的最近开格坐标（无效则回退开格质心）。
func play(g: Grid, hud, wave_center: Vector2i, time_info: Dictionary) -> void:
	_grid = g
	_hud = hud
	_fx = g.get_node_or_null("EffectsLayer") as EffectsLayer
	_active = true
	_pitch_idx = 0
	_hearts_done = 0
	_lives_total = GameState.lives if GameState.has_life_limit() else 0
	_time_backup = {"saved": GameState.has_time_limit(),
			"text": hud.time_label.text, "color": hud.time_label.modulate}

	var flag_cells := _current_flag_cells(g)
	var opened_cells := _opened_wave_cells(g)
	var rings := _rings_from(opened_cells, _resolve_center(g, opened_cells, wave_center))
	var mario_secs: int = int(time_info.get("secs", 0))
	var mario_per: int = int(time_info.get("per", 0))

	# 总分滚动起点：真实分 −（将要复述的旗+开格合计）；命/时间是后面的真实入账
	_disp_score = GameState.score \
			- flag_cells.size() * FLAG_POINTS - opened_cells.size() * OPEN_POINTS
	_hud.score_label.text = str(_disp_score)
	_beat_idx = 0
	_beat_total = maxi(1, flag_cells.size() + rings.size() + _lives_total)

	_master = create_tween()
	_master.tween_interval(0.3)  # 定格一拍再开演

	# ① 旗子逐面跳（复述已给的分）
	var flag_step: float = minf(FLAG_STEP, FLAG_TIME_CAP / float(maxi(flag_cells.size(), 1)))
	for c in flag_cells:
		_master.tween_callback(_pop_flag.bind(c))
		_master.tween_interval(flag_step)

	# ② 已开格波纹逐圈跳（复述已给的分，圈合并飘字）
	var ring_step: float = minf(RING_STEP, RING_TIME_CAP / float(maxi(rings.size(), 1)))
	for ring in rings:
		_master.tween_callback(_pop_ring.bind(ring))
		_master.tween_interval(ring_step)

	# ③ 剩余的命逐颗入账
	for i in _lives_total:
		_master.tween_callback(_pop_heart.bind(i))
		_master.tween_interval(HEART_STEP)

	# ④ 马里奥式倒计时换分（显示先行，真实入账在收尾）；分数从时钟拆成若干份飞向总分
	if mario_secs > 0 and mario_per > 0:
		var dur: float = clampf(mario_secs * 0.075, MARIO_MIN_TIME, MARIO_TIME_CAP)
		_master.tween_callback(_mario_begin.bind(mario_secs, mario_per, dur))
		_master.tween_method(_mario_tick, 0.0, 1.0, dur) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)  # 加速走完
		_master.tween_callback(_mario_end)

	# ⑤ 剩余金币折分：金币流飞向总分，钱数清零/分数对滚（显示先行，真实入账在收尾）
	var money_total: int = GameState.money
	if money_total > 0:
		_master.tween_callback(_money_begin.bind(money_total))
		_master.tween_method(_money_tick, 0.0, 1.0, MONEY_TIME) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_master.tween_callback(_money_end)

	# 收尾大脉冲 + 定格，面板随后弹出
	_master.tween_callback(_final_pulse)
	_master.tween_interval(FINAL_HOLD)
	_master.tween_callback(_finish)


func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	var do_skip := false
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		do_skip = true
	elif event is InputEventKey and event.pressed and not event.echo \
			and (event.keycode == KEY_SPACE or event.is_action("ui_accept")):
		do_skip = true
	if do_skip:
		get_viewport().set_input_as_handled()
		_skip()


# ---- 各拍实现 ----

## 落一拍：总分数字真涨一格 + 幅度递增的脉冲 + 升调「叮」
func _land(delta: int) -> void:
	_disp_score += delta
	_hud.score_label.text = str(_disp_score)
	var k: float = float(_beat_idx) / float(_beat_total)
	_hud.fx_score_pulse(lerpf(PULSE_STRENGTH_MIN, PULSE_STRENGTH_MAX, k))
	_beat_idx += 1
	_tick()


func _pop_flag(cell: Cell) -> void:
	cell.play_chord_pulse()
	# 「+5」不再原地飘字，改为从旗格划弧线飞进总分（复看③，与金币流同语言）
	_fly_score(_cell_center_hud(cell), _hud_label_center(_hud.score_label),
			"+%d" % FLAG_POINTS, 0.0)
	_land(FLAG_POINTS)


func _pop_ring(ring: Dictionary) -> void:
	var cells: Array = ring["cells"]
	for c in cells:
		c.play_chord_pulse()
	if _fx != null:
		_fx.fx_gain_text(ring["pos"], "+%d" % (cells.size() * OPEN_POINTS))
		# 复看⑤：同款开格波纹——岩屑取样飞溅（直接复用 fx_reveal_wave，延迟 0 当拍齐发）
		var entries: Array = []
		for c in cells:
			entries.append({"cell": c, "delay": 0.0})
		_fx.fx_reveal_wave(entries, "player")
	# 同款开格音效级联：每圈最多 4 声、音调递增、错峰 35ms（audio_connector 同配方）
	var n: int = mini(cells.size(), 4)
	for i in n:
		AudioManager.play_sfx("open", 1.0 + 0.09 * i, 0.035 * i)
	_land(cells.size() * OPEN_POINTS)


func _pop_heart(i: int) -> void:
	# 真实入账：score_changed 即时刷新总分数字（一颗 +20 的滚动上涨）
	GameState.add_score(LIFE_BONUS_PER, "life_bonus")
	_hearts_done += 1
	_hud.fx_heart_pop(i)
	_hud.fx_heart_gain(i, "+%d" % LIFE_BONUS_PER)
	_land(LIFE_BONUS_PER)


func _mario_begin(secs: int, per: int, dur: float) -> void:
	_mario = {"on": true, "secs": secs, "per": per, "base": GameState.score,
			"last_disp": secs, "last_tick_ms": 0}
	_hud.fx_time_show(secs)
	# 分数飞字：总加分拆成若干份，从时钟均匀飞向总分（金额精确合计）
	var total := secs * per
	var n: int = clampi(int(secs / 12.0), 5, MARIO_FLYERS)
	var base_amount := total / n
	var remainder := total - base_amount * n
	var from := _hud_label_center(_hud.time_label)
	var to := _hud_label_center(_hud.score_label)
	for i in n:
		var amt := base_amount + (remainder if i == n - 1 else 0)
		var delay: float = maxf(0.0, dur * (float(i) + 0.5) / float(n) - FLY_TIME * 0.5)
		_fly_score(from, to, "+%d" % amt, delay)


func _mario_tick(k: float) -> void:
	if not _mario["on"]:
		return
	var disp: int = int(round(float(_mario["secs"]) * (1.0 - k)))
	if disp != int(_mario["last_disp"]):
		_mario["last_disp"] = disp
		_hud.fx_time_show(disp)
		var now := Time.get_ticks_msec()
		if now - int(_mario["last_tick_ms"]) >= TICK_MIN_GAP_MS:
			_mario["last_tick_ms"] = now
			# 越接近 0 音调越高（马里奥清时间的紧凑感）
			var frac := float(_mario["secs"] - disp) / maxf(float(_mario["secs"]), 1.0)
			AudioManager.play_sfx("coin", 1.0 + 0.5 * frac)
	# 总分同步滚涨（真实入账在收尾，这里只动显示）
	_hud.score_label.text = str(int(_mario["base"]) \
			+ (_mario["secs"] - disp) * int(_mario["per"]))


func _mario_end() -> void:
	if not _mario["on"]:
		return
	_mario["on"] = false
	_hud.fx_time_show(0)
	_hud.score_label.text = str(int(_mario["base"]) + int(_mario["secs"]) * int(_mario["per"]))


func _money_begin(total: int) -> void:
	_money = {"on": true, "total": total, "base": GameState.score, "last_step": -1}
	_spawn_coin_stream(total)


func _money_tick(k: float) -> void:
	if not _money["on"]:
		return
	var total := int(_money["total"])
	var spent := int(round(total * k))
	# 双数字对滚：钱往下清、分往上涨（真实入账在收尾，这里只动显示）
	_hud.money_label.text = str(total - spent)
	_disp_score = int(_money["base"]) + spent
	_hud.score_label.text = str(_disp_score)
	var step := int(k * 12.0)
	if step != int(_money["last_step"]):
		_money["last_step"] = step
		AudioManager.play_sfx("coin", 1.1 + 0.04 * step)  # 金币流渐密渐高


func _money_end() -> void:
	if not _money["on"]:
		return
	_money["on"] = false
	_hud.money_label.text = "0"
	_disp_score = int(_money["base"]) + int(_money["total"])
	_hud.score_label.text = str(_disp_score)


## 金币流：钱袋位置 → 总分位置逐枚贝塞尔飞币（枚数封顶，一枚可代表多枚）
func _spawn_coin_stream(total: int) -> void:
	var count: int = mini(total, MONEY_COINS_SHOWN)
	var from := _hud_label_center(_hud.money_label)
	var to := _hud_label_center(_hud.score_label)
	for i in count:
		_spawn_coin(from, to, 0.07 * i)


func _hud_label_center(lbl: Label) -> Vector2:
	return _hud.get_global_transform().affine_inverse() * lbl.get_global_rect().get_center()


## 格子（旗）中心 → HUD 本地坐标（跨 Grid/Control 两套坐标系走全局变换）
func _cell_center_hud(cell: Cell) -> Vector2:
	var half := Vector2(_grid.cell_size, _grid.cell_size) * 0.5
	return _hud.get_global_transform().affine_inverse() \
			* (cell.get_global_transform() * half)


## 分数飞字：金色"+N"从 from 划贝塞尔弧线飞进总分，途中缩小、临到点淡出
func _fly_score(from: Vector2, to: Vector2, text: String, delay_s: float) -> void:
	var lbl := Label.new()
	lbl.name = "TallyFlyScore"  # 显式命名，避免遍历误匹配
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", FLY_FONT_SIZE)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	lbl.add_theme_constant_override("outline_size", 3)
	lbl.position = from
	_hud.add_child(lbl)
	var t := lbl.create_tween()
	t.tween_interval(delay_s)
	var peak := (from + to) / 2.0 + Vector2(0, -22)
	t.tween_method(
		func(k: float):
			var a: Vector2 = from.lerp(peak, k)
			var b: Vector2 = peak.lerp(to, k)
			lbl.position = a.lerp(b, k)
			lbl.scale = Vector2.ONE * (1.0 - 0.35 * k)
			lbl.modulate.a = 1.0 if k < 0.75 else 1.0 - (k - 0.75) / 0.25,
		0.0, 1.0, FLY_TIME)
	t.tween_callback(lbl.queue_free)


func _spawn_coin(from: Vector2, to: Vector2, delay_s: float) -> void:
	var s := Sprite2D.new()
	s.name = "TallyFlyCoin"  # 显式命名，避免遍历误匹配
	s.texture = COIN_TEX
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.position = from
	_hud.add_child(s)
	var t := s.create_tween()
	t.tween_interval(delay_s)
	# 二次贝塞尔：中点抬高（与盘面飞币 _fly_coin 同语言）
	var peak := (from + to) / 2.0 + Vector2(0, -26)
	t.tween_method(
		func(k: float):
			var a: Vector2 = from.lerp(peak, k)
			var b: Vector2 = peak.lerp(to, k)
			s.position = a.lerp(b, k)
			s.scale = Vector2.ONE * (1.0 - 0.3 * k),
		0.0, 1.0, 0.38)
	t.tween_callback(s.queue_free)


func _final_pulse() -> void:
	_hud.fx_score_pulse(PULSE_STRENGTH_FINAL)


func _finish() -> void:
	if not _active:
		return
	_active = false
	_master = null
	if _time_backup["saved"]:
		# 时钟恢复真实剩余（继续挑战回到局内时显示不失真；面板压暗下这一跳不可见）
		_hud.time_label.text = _time_backup["text"]
		_hud.time_label.modulate = _time_backup["color"]
	finished.emit()


## 跳过：掐断时间轴，命分尾款一次补齐，直接收尾（时间分仍由 main 收尾统一入账）
func _skip() -> void:
	if not _active:
		return
	if _master != null:
		_master.kill()
		_master = null
	var remain: int = _lives_total - _hearts_done
	if remain > 0:
		GameState.add_score(remain * LIFE_BONUS_PER, "life_bonus")
	_mario["on"] = false
	_money["on"] = false
	_hud.money_label.text = str(GameState.money)  # 金币流被掐断时显示回真实值
	_hud.score_label.text = str(GameState.score)
	_finish()


# ---- 盘面数据整理 ----

## 当前盘面上「旗还插着且当初插对」的格子（撤过旗的坐标不演：分是局内给的，账不丢）
func _current_flag_cells(g: Grid) -> Array:
	var out: Array = []
	for coord: Vector2i in g.rewarded_flags:
		var cell: Cell = g.cells.get(coord)
		if cell == null or not cell.is_flagged:
			continue
		out.append(cell)
	out.sort_custom(func(a, b):
		if a.coord.y != b.coord.y:
			return a.coord.y < b.coord.y
		return a.coord.x < b.coord.x)
	return out


## 参与波纹的开格（与翻开波纹同过滤：基地/矿脉/坍塌不弹）
func _opened_wave_cells(g: Grid) -> Array:
	var out: Array = []
	for c: Cell in g.cells.values():
		if c.is_opened and not c.is_base and not c.is_vein and not c.is_collapsed:
			out.append(c)
	return out


func _resolve_center(g: Grid, opened: Array, last_coord: Vector2i) -> Vector2i:
	var c: Cell = g.cells.get(last_coord)
	if c != null and c.is_opened:
		return last_coord
	if opened.is_empty():
		return Vector2i.ZERO
	var sum := Vector2.ZERO
	for cell: Cell in opened:
		sum += Vector2(cell.coord)
	return Vector2i((sum / opened.size()).round())


## 切比雪夫距离分圈（一圈一拍同时弹），圈内飘字位置取成员均值
func _rings_from(opened: Array, center: Vector2i) -> Array:
	var by_ring: Dictionary = {}
	for cell: Cell in opened:
		var d: int = maxi(absi(cell.coord.x - center.x), absi(cell.coord.y - center.y))
		if not by_ring.has(d):
			by_ring[d] = []
		by_ring[d].append(cell)
	var rings: Array = []
	for d in by_ring.keys():
		var cells: Array = by_ring[d]
		var pos := Vector2.ZERO
		for cell: Cell in cells:
			pos += cell.position
		rings.append({"d": int(d), "cells": cells, "pos": pos / float(cells.size())})
	rings.sort_custom(func(a, b): return int(a["d"]) < int(b["d"]))
	return rings


## 升调「叮」：每拍音调递增（coin 变调，零新素材）
func _tick() -> void:
	AudioManager.play_sfx("coin", minf(1.0 + 0.06 * _pitch_idx, TICK_PITCH_MAX))
	_pitch_idx += 1
