extends Node
## 设置持久化 autoload（user://settings.json）
## 全屏/网格线/教程状态立即生效；音频音量经 AudioManager 监听 setting_changed 即时生效

const PATH := "user://settings.json"

## 窗口分辨率可选值（"auto" = 按屏幕高度 80% 取 4:3 尺寸，上限 1536×1152）
const WINDOW_SIZES := ["1024x768", "1280x960", "1536x1152", "auto"]

const DEFAULTS := {
	"music_on": true,
	"sfx_on": true,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"screen_shake": true,
	"show_grid": false,
	"fullscreen": false,
	"window_size": "1024x768",
	"tutorial_done": false,
	# 每关教学单独记次：看过一次（自然走完/跳过/ESC）整段剧本不再播；
	# 设置面板"重看教学"统一重置（load_settings 只回读 DEFAULTS 内的 key，勿漏注册）
	"tutorial_done_ch01_s01": false,
	"tutorial_done_ch01_s02": false,
	"tutorial_done_ch01_s03": false,
	"tutorial_done_ch01_s04": false,
	"tutorial_done_ch01_s05": false,
	"skip_pre_level": false,   # 重玩时跳过关前卡（首次通关前强制显示）
	"feedback_url": "",        # 试玩反馈地址（空 = 反馈按钮隐藏，渠道定后配置启用）
}

var values: Dictionary = DEFAULTS.duplicate()

signal setting_changed(key: String, value: Variant)


func _ready() -> void:
	load_settings()
	_apply_fullscreen()


func get_value(key: String) -> Variant:
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value: Variant) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	save_settings()
	if key == "fullscreen":
		_apply_fullscreen()
	elif key == "window_size":
		_apply_window_size()
	setting_changed.emit(key, value)


func load_settings() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		return
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return
	for key in DEFAULTS:
		if data.has(key):
			values[key] = data[key]


func save_settings() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		push_warning("无法写入设置")
		return
	f.store_string(JSON.stringify(values, "  "))


func _apply_fullscreen() -> void:
	if bool(values.get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		_apply_window_size()  # 退出全屏时回到所选窗口尺寸


func _apply_window_size() -> void:
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		return
	var key := String(values.get("window_size", "1024x768"))
	var size := Vector2i(1024, 768)
	if key == "auto":
		var usable := DisplayServer.screen_get_usable_rect()
		var h: int = mini(int(usable.size.y * 0.8), 1152)
		size = Vector2i(int(h * 4.0 / 3.0), h)
	elif WINDOW_SIZES.has(key):
		var parts := key.split("x")
		size = Vector2i(int(parts[0]), int(parts[1]))
	DisplayServer.window_set_size(size)
	# 改尺寸后重新居中，避免窗口偏出屏幕
	var screen := DisplayServer.screen_get_usable_rect()
	DisplayServer.window_set_position(screen.position + (screen.size - size) / 2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_F11:
		set_value("fullscreen", not bool(values.get("fullscreen", false)))
		get_viewport().set_input_as_handled()
