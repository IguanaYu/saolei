extends PanelContainer
## 事件日志侧栏：常驻滚动战报（2026-10-02 侧栏改造，替代 TeamPanel/ScorePanel 的侧栏位）
## 左栏=玩家行动流 / 右栏=机器人作业流，条目由 EventLogConnector 路由喂数。
##
## 条目保持单行短句：主题 FontVariation 下 autowrap 的 min size 按逐字断行计算，
## 长文案会撑爆面板（TeamPanel 时代踩过的坑，见调试复盘文档）。

const MAX_ENTRIES := 120
const STAMP_COLOR := "#9a8f80"   # 时间戳暗一档，与正文拉开层级

var _entries: Array[String] = []

@onready var _title_label: Label = $Margin/VBox/TitleLabel
@onready var _log: RichTextLabel = $Margin/VBox/LogText


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE   # 底板不接鼠标；滚轮翻阅由 LogText 自带滚动接管
	_log.bbcode_enabled = true
	_log.scroll_following = true


func setup(title_text: String) -> void:
	_title_label.text = title_text


func clear_log() -> void:
	_entries.clear()
	_log.clear()


## text_bbcode：已带主体颜色标签的完整片段，时间戳在这里统一补
func log_event(text_bbcode: String) -> void:
	var t := int(GameState.elapsed)
	_entries.append("[color=%s][%d:%02d][/color] %s" % [STAMP_COLOR, t / 60, t % 60, text_bbcode])
	if _entries.size() > MAX_ENTRIES:
		_entries.pop_front()
		if not _log.remove_line(0):   # remove_line 只认 append 出的段落，失败则整体重排兜底
			_rerender()
			return
	_log.append_text(_entries[-1] + "\n")


func _rerender() -> void:
	_log.clear()
	for e in _entries:
		_log.append_text(e + "\n")
