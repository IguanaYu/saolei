extends Control
## 规则页：三节固定文案（是规则不是关卡数值，允许硬编码）
## 入口三处：主菜单 / 暂停 / 商店第二行「操作说明」（布局计划 §2.3）

signal close_requested

@onready var close_button: Button = $Center/Panel/Margin/VBox/CloseButton


func _ready() -> void:
	hide()
	close_button.pressed.connect(hide)


func open() -> void:
	show()
	close_button.grab_focus()
