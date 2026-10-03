extends PanelContainer
## 键帽徽章：快捷键提示（商店按钮角标/底部提示条共用）；全链路不拦截鼠标

@export var key_text := ""


func _ready() -> void:
	$KeyLabel.text = key_text  # tscn 属性覆盖发生在子节点就绪前，故不写进 setter


func set_key(text: String) -> void:
	key_text = text
	$KeyLabel.text = text
