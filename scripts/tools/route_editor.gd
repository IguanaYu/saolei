extends Control
## 路径驱动地图生成器 · 编辑器画线工具 v1（收尾计划步骤 D）
## 定位：开发工具场景（编辑器里 F6 运行），不进游戏 UI；Python 是生成逻辑唯一源。
## 用法：左侧点格画笔画（右键撤销）→ 实时段间距过近预警（§4.3 高冲突提示）→
##       保存笔画 JSON → 生成（调 tools.route_gen.cli）→ 载入结果画答案层叠加。
## 实现口径：Godot 官方自定义绘制（Control._draw + _gui_input），网格/叠加全程序画。

const W := 16
const H := 16
const CELL := 34
const GAP_WARN := 4      # 折返间距 ≤ 此值 = 高冲突提示（§4.3；gap-4 实测不可解、gap-6 可解）

var stroke: Array = []          # 有方向的笔画点（格坐标 Vector2i）
var board: Dictionary = {}      # 载入的 board_fixed.json board 字段
var show_truth := true          # 答案层开关
var status := "左键加点画路线 · 右键撤销"

@onready var python_exe := "python"


func _ready() -> void:
	custom_minimum_size = Vector2(W * CELL + 260, H * CELL + 40)
	var ui := VBoxContainer.new()
	ui.name = "SideUI"
	ui.position = Vector2(W * CELL + 16, 8)
	ui.size = Vector2(240, H * CELL)
	ui.add_theme_constant_override("separation", 8)
	add_child(ui)
	_add_button(ui, "保存笔画 JSON", _save_stroke)
	_add_button(ui, "生成（调 Python CLI）", _run_generate)
	_add_button(ui, "载入生成结果叠加", _load_board)
	_add_button(ui, "答案层 开/关", func():
		show_truth = not show_truth
		queue_redraw())
	_add_button(ui, "清空笔画", func():
		stroke.clear()
		board = {}
		queue_redraw())
	var lbl := Label.new()
	lbl.name = "Status"
	lbl.text = status
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.custom_minimum_size = Vector2(240, 120)
	ui.add_child(lbl)
	queue_redraw()


func _add_button(ui: VBoxContainer, text: String, fn: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.pressed.connect(fn)
	ui.add_child(b)


func _status(text: String) -> void:
	status = text
	(get_node("SideUI/Status") as Label).text = text
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		var cell := Vector2i(int(mb.position.x / CELL), int(mb.position.y / CELL))
		if cell.x < 0 or cell.x >= W or cell.y < 0 or cell.y >= H:
			return
		if mb.button_index == MOUSE_BUTTON_LEFT:
			stroke.append(cell)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not stroke.is_empty():
			stroke.pop_back()
		_status("笔画 %d 点 · %s" % [stroke.size(), _gap_warning()])
		queue_redraw()


## §4.3 高冲突实时提示：笔画上进度差 ≥10 且棋盘距离 ≤GAP_WARN 的点对 = 折返过近
func _gap_warning() -> String:
	if stroke.size() < 12:
		return "（画长一点再做折返检测）"
	var worst := 99
	for i in range(0, stroke.size(), 2):
		for j in range(i + 10, stroke.size(), 2):
			var d: int = maxi(abs(stroke[i].x - stroke[j].x), abs(stroke[i].y - stroke[j].y))
			if d <= GAP_WARN:
				worst = mini(worst, d)
	if worst <= GAP_WARN:
		return "⚠ 有折返间距 %d 格（≤%d 高冲突：实测验曾被判不可解，建议拉开到 6+）" % [worst, GAP_WARN]
	return "折返间距健康（> %d 格）" % GAP_WARN


func _save_stroke() -> void:
	if stroke.size() < 2:
		_status("至少两个点才能保存")
		return
	var path := "res://tools/route_gen/strokes/editor_stroke.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"name": "EditorStroke", "points": stroke}, "  "))
	f.close()
	_status("已保存 %s\n%s" % [path, _gap_warning()])


func _run_generate() -> void:
	_save_stroke()
	if stroke.size() < 2:
		return
	var out := []
	var code := OS.execute("python",
			["-m", "tools.route_gen.cli",
			 "--stroke", "tools/route_gen/strokes/editor_stroke.json",
			 "--seed", "2"], out, true)
	_status("生成退出码 %d\n%s" % [code, "\n".join(out).right(300)] if code != 0
			else "生成完成，正在载入叠加…")
	if code == 0:
		_load_board()


func _load_board() -> void:
	var path := "res://tools/route_gen/out/board_fixed.json"
	if not FileAccess.file_exists(path):
		_status("找不到 %s（先点生成）" % path)
		return
	var f := FileAccess.open(path, FileAccess.READ)
	var parsed: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()
	board = parsed.get("board", {})
	_status("已载入盘面：雷 %d 预开 %d 墙 %d 封印 %d" % [
		board.get("mines", []).size(), board.get("preopen", []).size(),
		board.get("walls", []).size(), board.get("seals", []).size()])
	queue_redraw()


func _draw() -> void:
	# 网格
	for x in W + 1:
		draw_line(Vector2(x * CELL, 0), Vector2(x * CELL, H * CELL), Color(0, 0, 0, 0.25), 1.0)
	for y in H + 1:
		draw_line(Vector2(0, y * CELL), Vector2(W * CELL, y * CELL), Color(0, 0, 0, 0.25), 1.0)
	# 生成结果叠加（答案层）
	if show_truth and not board.is_empty():
		for p in board.get("preopen", []):
			_cell_rect(Vector2(p[0], p[1]), Color(0.55, 0.75, 0.55, 0.5))
		for m in board.get("mines", []):
			_cell_rect(Vector2(m[0], m[1]), Color(0.8, 0.2, 0.2, 0.75))
		for w in board.get("walls", []):
			_cell_rect(Vector2(w[0], w[1]), Color(0.85, 0.55, 0.2, 0.75))
		for o in board.get("fossils", []):
			for dy in 2:
				for dx in 2:
					_cell_rect(Vector2(o[0] + dx, o[1] + dy), Color(0.5, 0.4, 0.7, 0.7))
		for s in board.get("seals", []):
			for c in s["cells"]:
				_cell_rect(Vector2(c[0], c[1]), Color(0.3, 0.8, 0.9, 0.65))
			var t: Vector2 = s["trigger"]
			_cell_rect(Vector2(t[0], t[1]), Color(0.95, 0.9, 0.3, 0.9))
		var base = board.get("base")
		if base != null:
			_cell_rect(Vector2(base[0], base[1]), Color(0.2, 0.9, 0.9, 0.9))
	# 笔画连线
	if stroke.size() >= 2:
		var pts := PackedVector2Array()
		for p in stroke:
			pts.append(Vector2(p.x * CELL + CELL / 2.0, p.y * CELL + CELL / 2.0))
		draw_polyline(pts, Color(0.2, 0.35, 1.0, 0.9), 3.0)
	for p in stroke:
		draw_circle(Vector2(p.x * CELL + CELL / 2.0, p.y * CELL + CELL / 2.0), 4.0,
				Color(1.0, 0.5, 0.1))
	# 状态文字
	draw_string(ThemeDB.fallback_font, Vector2(W * CELL + 16, H * CELL - 6),
			status, HORIZONTAL_ALIGNMENT_LEFT, 250, 12, Color(1, 1, 1))


func _cell_rect(c: Vector2, color: Color) -> void:
	if c.x < 0 or c.x >= W or c.y < 0 or c.y >= H:
		return
	draw_rect(Rect2(c.x * CELL + 2, c.y * CELL + 2, CELL - 4, CELL - 4), color)
