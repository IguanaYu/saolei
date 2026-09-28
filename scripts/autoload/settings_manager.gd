extends Node
## 设置持久化 autoload（user://settings.json）
## 全屏/网格线/教程状态立即生效；音频音量经 AudioManager 监听 setting_changed 即时生效

const PATH := "user://settings.json"

const DEFAULTS := {
	"music_on": true,
	"sfx_on": true,
	"music_volume": 0.7,
	"sfx_volume": 0.8,
	"screen_shake": true,
	"show_grid": false,
	"fullscreen": false,
	"tutorial_done": false,
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
