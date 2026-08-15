extends Control
## 通用确认对话框：标题 + 正文 + 双按钮（危险操作确认按钮变红）
## 用法：ask("放弃本局？", "...", "确认放弃", "继续挖掘", true)

signal confirmed
signal cancelled

@onready var title_label: Label = $Center/Panel/VBox/TitleLabel
@onready var body_label: Label = $Center/Panel/VBox/BodyLabel
@onready var cancel_button: Button = $Center/Panel/VBox/ButtonsRow/CancelButton
@onready var confirm_button: Button = $Center/Panel/VBox/ButtonsRow/ConfirmButton


func _ready() -> void:
	hide()
	cancel_button.pressed.connect(_on_cancel)
	confirm_button.pressed.connect(_on_confirm)


func ask(title: String, body: String, confirm_text := "确认",
		cancel_text := "继续", danger := false) -> void:
	title_label.text = title
	body_label.text = body
	confirm_button.text = confirm_text
	cancel_button.text = cancel_text
	confirm_button.modulate = Color(1.0, 0.55, 0.48) if danger else Color.WHITE
	show()


func _on_confirm() -> void:
	hide()
	confirmed.emit()


func _on_cancel() -> void:
	hide()
	cancelled.emit()
