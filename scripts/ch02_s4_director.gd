extends Node
class_name Ch02S4Director
## 第二章 2-4「连爆节点」剧本控制器（设计 §5 关内流程，实施计划 WP6）
## 开局聚光展示节点（等首次连爆推进）→ 首爆后第二组仍有存活节点时轻提示
## 「先标记，再引爆」（toast 不占聚光步；节点依次闪光自解释，设计 §5「连爆顺序用于表现」）；
## 误打低收益句沿用 2-1 文案不新写。

const COPY_INTRO := "击中节点，相邻节点连爆。"
const COPY_MARK_FIRST := "先标记，再引爆。"

var _guide: Control
var _grid: Node2D
var _mark_toasted := false


func _ready() -> void:
	var main := get_parent()
	_guide = main.get_node("UILayer/TutorialGuide")
	_grid = main.get_node("BoardRoot/Grid")


func begin() -> void:
	_mark_toasted = false
	var board_size := Vector2(_grid.cols * _grid.cell_size, _grid.rows * _grid.cell_size)
	var tw := create_tween()
	tw.tween_interval(0.5)
	tw.tween_callback(func() -> void:
		_guide.begin([
			{"node": _grid, "size": board_size,
				"text": COPY_INTRO, "event": "chain_triggered", "tip": "right"},
		]))


## 首爆后：第二组还有未被本轮引爆的存活节点 → 一次性轻提示（设计 §5 第二阶段）
func on_chain_triggered(nodes: Array) -> void:
	if _mark_toasted or not GameState.game_active or GameState.current_level_id != "ch02_s04":
		return
	var fm = get_parent().get_node_or_null("BoardRoot/FacilityManager")
	if fm == null:
		return
	for n in fm.chain_nodes:
		if is_instance_valid(n) and not n.consumed and not nodes.has(n):
			_mark_toasted = true
			var hud: Control = get_parent().get_node("UILayer/HUD")
			hud.show_toast(COPY_MARK_FIRST, 3.0)
			return
