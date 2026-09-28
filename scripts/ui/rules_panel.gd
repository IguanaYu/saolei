extends Control
## 规则页：三节固定文案（是规则不是关卡数值，允许硬编码）
## 入口三处：主菜单 / 暂停 / 商店第二行「操作说明」（布局计划 §2.3）
## 从局内（商店）打开时暂停游戏，关闭恢复打开前状态（暂停面板打开中则保持暂停）

signal close_requested

@onready var close_button: Button = $Center/Panel/Margin/VBox/CloseButton

var _was_paused := false


func _ready() -> void:
	hide()
	close_button.pressed.connect(close)


func open() -> void:
	_was_paused = get_tree().paused
	get_tree().paused = true
	show()
	close_button.grab_focus()


func close() -> void:
	hide()
	get_tree().paused = _was_paused
