class_name EscapeRouter
extends Node
## Esc 按键路由器：挂在 UILayer（process_mode=ALWAYS）下，树暂停期仍能收键。
## 2026-10-03 盲测 F01 复盘：Esc 分层原先长在 main._input（Main 根继承 PAUSABLE），
## 任何面板置 get_tree().paused=true 后 _input 停摆——"按 ESC 继续"失效、
## 暂停内设置/规则页退不回去；UILayer 里的按钮因 ALWAYS 反而能点，行为自相矛盾。
## 这里只做转发，分层决策仍归 main._handle_escape（只退一层），不在本节点重复实现。

signal escape_requested


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_ESCAPE:
		escape_requested.emit()
