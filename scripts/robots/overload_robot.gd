class_name OverloadRobot
extends Robot
## 改版 2-4 过载机器人（提案 2026-10-10 §5）：玩家可建造的新兵种——
## 100 金限购 1（折光位），基地出厂直购直出（不走放置流，拍板 #10）。
## 已开区自主巡逻，偏好「低数字 × 靠墙」工位（走位即提示：正是玩家最想开墙的位置）；
## 到位后停留数拍给玩家「等它走到位」的读秒空间。
## 玩家激光束命中即原地爆发 3×3+四正各 1 格（13 格，拍板 #6），免费、爆后存活无限用
## （拍板 #5/#7）；结算/充能/旗格免疫由 LaserManager 统一管（爆炸格照常充能，拍板 #8）。

const MOVE_SEC := 2.2        # 固定步速（guard Q2 口径：不吃升级/充能，便于盲测归因）
const DWELL_TICKS := 3       # 到达高分工位后停留的移动拍数（实测后调：读秒空间）
const GOOD_NUMBER := 2       # 「低数字」阈值：显示数字 ≤2 且靠墙 = 高分工位
const WALL_PENALTY := 3.0    # 候选不靠墙时的评分惩罚（靠墙优先于低 1~2 点数字）

## 8 邻偏移（builder/guard 巡逻是 4 邻；过载要贴墙卡位，斜向一步到达）
const STEP_OFFSETS := [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]

var _dwell_left := 0  # 高分工位剩余停留拍数


func _ready() -> void:
	super()
	robot_type = "overload"
	_update_visual()


## 固定步速：不走 opener/marker 双轨，也不吃充能加速（本体是炮台不是工人）
func accumulate_and_maybe_tick(delta: float, grid, _locked: Dictionary) -> void:
	_tick_timer += delta
	if _tick_timer >= MOVE_SEC:
		_tick_timer = 0.0
		do_tick(grid, _locked)


## 永不报空闲（guard/refractor 先例：不触发全场停摆误报）
func is_idle() -> bool:
	return false


## 偏好巡逻：8 邻已开空格按评分取最优走一步；到位高分工位则停留 DWELL_TICKS 拍
func do_tick(grid, _locked: Dictionary) -> void:
	if _dwell_left > 0:
		_dwell_left -= 1
		_state = "working"
		return
	var best: Array = []  # [score, coord]
	for o in STEP_OFFSETS:
		var n: Vector2i = coord + o
		var c: Cell = grid.get_cell(n)
		if c == null or not c.is_opened or c.cover_wall_hp > 0 or c.is_base:
			continue
		if grid.facility_cells.has(n):
			continue
		var s := _score(c, grid)
		if best.is_empty() or s < best[0]:
			best = [s, n]
	if best.is_empty():
		_state = "idle"  # 极端兜底：周围无处可站（is_idle 恒 false 不误报停摆）
		return
	_move_to(best[1], grid)
	coord = best[1]
	_state = "moving"
	if best[0] <= float(GOOD_NUMBER) + 0.99:
		_dwell_left = DWELL_TICKS


## 工位评分（越小越好）：显示数字 + 不靠墙惩罚 + 抖动（避免死锁同格来回弹）
func _score(c: Cell, grid) -> float:
	var n: int = 0 if c.is_vein else c.adjacent_mines  # 已转化资源格显示为空，视作 0
	var near_wall := false
	for o in STEP_OFFSETS:
		var nc: Cell = grid.get_cell(c.coord + o)
		if nc != null and not nc.is_opened:
			near_wall = true
			break
	return float(n) + (0.0 if near_wall else WALL_PENALTY) + randf() * 0.99


## 爆炸 13 格：3×3 + 四正方向各延伸 1 格（边界裁切；快照阶段由 LaserManager 取用）
func blast_cells(grid) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			out.append(coord + Vector2i(dx, dy))
	for d in [Vector2i(2, 0), Vector2i(-2, 0), Vector2i(0, 2), Vector2i(0, -2)]:
		out.append(coord + d)
	return out.filter(func(c): return grid.cells.has(c))
