class_name GuildPanel
extends PanelContainer
## 冒险者工会·营业日面板（ch04 试验章，WP1 最简版）
## 底部居中一条：第几批 / 剩余工时 / 发布本批按钮。
## 代码构建（同 hud._build_compact_ui 惯例）；状态由 GuildDayManager.guild_state_changed 推。

signal publish_requested

const UI := preload("res://scripts/ui/game_ui_style.gd")
const PHASE_TEXT := {
	"prepare": "准备中：调查地图、安排队伍",
	"resolving": "冒险者探索中…",
	"done": "营业日结束",
}

# 金币余额标签：HUD.bind_money_label 的工会关锚点（开格挣钱浮字挂这里；商店位被本面板占用）
var money_label: Label

var _batch_label: Label
var _phase_label: Label
var _hours_label: Label
var _publish_btn: Button


func _ready() -> void:
	visible = false  # 非工会关不显示；main 在进关时按 guild_mode 开关
	name = "GuildPanel"  # 显式命名，防 get_children 遍历误匹配
	custom_minimum_size = Vector2(520, 64)
	mouse_filter = Control.MOUSE_FILTER_STOP  # 面板区域挡住棋盘点击（挡的是空地，无格子）
	add_theme_stylebox_override("panel", UI.panel())
	var row := HBoxContainer.new()
	row.name = "GuildRow"
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	_batch_label = UI.label("第 1 / 3 批", "BatchLabel", 18, UI.GOLD)
	_batch_label.custom_minimum_size.x = 96
	row.add_child(_batch_label)
	var mid := VBoxContainer.new()
	mid.name = "MidBox"
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.add_theme_constant_override("separation", 2)
	row.add_child(mid)
	_phase_label = UI.label(PHASE_TEXT["prepare"], "PhaseLabel", 12, UI.SOFT)
	mid.add_child(_phase_label)
	_hours_label = UI.label("工时 100 / 100", "HoursLabel", 15, UI.INK)
	_hours_label.tooltip_text = "开格/插旗消耗工时；每批开放 100，余量结转下一批"
	mid.add_child(_hours_label)
	_publish_btn = Button.new()
	_publish_btn.name = "PublishButton"
	_publish_btn.text = "发布本批"
	_publish_btn.custom_minimum_size = Vector2(120, 40)
	_publish_btn.tooltip_text = "本批冒险者按当前地图情报出发；发布后开放下一批工时"
	UI.button(_publish_btn, 16)
	_publish_btn.pressed.connect(func(): publish_requested.emit())
	row.add_child(_publish_btn)
	money_label = UI.label("0", "MoneyLabel", 16, UI.GOLD)
	row.add_child(money_label)
	# 底部居中锚定（商店位；工会关商店隐藏，此位空出）
	set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BEGIN
	offset_left = -260
	offset_right = 260
	offset_top = -78
	offset_bottom = -14


func update_state(batch_index: int, phase: String, hours_left: int, hours_granted: int) -> void:
	_batch_label.text = "第 %d / %d 批" % [batch_index + 1, GuildDayManager.BATCH_COUNT]
	_phase_label.text = PHASE_TEXT.get(phase, phase)
	_hours_label.text = "工时 %d / %d" % [hours_left, hours_granted]
	_publish_btn.disabled = phase != "prepare"
	_publish_btn.text = "发布本批" if phase == "prepare" else (
		"探索中…" if phase == "resolving" else "已收工")
