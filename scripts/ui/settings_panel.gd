extends Control
## 设置面板：声音（音乐/音效开关+音量，经 AudioManager 即时生效）/ 画面与操作 / 游戏

signal close_requested
signal clear_save_requested
signal tutorial_rewatch_requested

const WINDOW_SIZE_LABELS := ["1024 × 768", "1280 × 960", "1536 × 1152", "跟随屏幕"]

const _LIST := "Center/Panel/VBox/SettingsScroll/SettingsList"

@onready var music_check: CheckButton = get_node(_LIST + "/RowMusic/HBox/MusicCheck")
@onready var sfx_check: CheckButton = get_node(_LIST + "/RowSfx/HBox/SfxCheck")
@onready var volume_slider: HSlider = get_node(_LIST + "/RowVolume/HBox/VolumeSlider")
@onready var sfx_volume_slider: HSlider = get_node(_LIST + "/RowSfxVolume/HBox/SfxVolumeSlider")
@onready var shake_check: CheckButton = get_node(_LIST + "/RowShake/HBox/ShakeCheck")
@onready var grid_check: CheckButton = get_node(_LIST + "/RowGrid/HBox/GridCheck")
@onready var fullscreen_check: CheckButton = get_node(_LIST + "/RowFullscreen/HBox/FullscreenCheck")
@onready var window_size_option: OptionButton = get_node(_LIST + "/RowWindowSize/HBox/WindowSizeOption")
@onready var _settings_scroll: ScrollContainer = $Center/Panel/VBox/SettingsScroll


func _ready() -> void:
	hide()
	# 滚动区高度随视口钳制（keep_height 下视口高恒定，仍防基线变更后内容顶出屏幕）
	_settings_scroll.custom_minimum_size.y = clampi(
		int(get_viewport_rect().size.y) - 240, 320, 560)
	music_check.toggled.connect(func(v): GameSettings.set_value("music_on", v))
	sfx_check.toggled.connect(func(v): GameSettings.set_value("sfx_on", v))
	volume_slider.value_changed.connect(func(v): GameSettings.set_value("music_volume", v))
	sfx_volume_slider.value_changed.connect(func(v): GameSettings.set_value("sfx_volume", v))
	shake_check.toggled.connect(func(v): GameSettings.set_value("screen_shake", v))
	grid_check.toggled.connect(func(v): GameSettings.set_value("show_grid", v))
	fullscreen_check.toggled.connect(func(v): GameSettings.set_value("fullscreen", v))
	for i in WINDOW_SIZE_LABELS.size():
		window_size_option.add_item(WINDOW_SIZE_LABELS[i], i)
	window_size_option.item_selected.connect(
		func(i): GameSettings.set_value("window_size", GameSettings.WINDOW_SIZES[i]))
	# F11 游戏内切换全屏时，同步面板勾选与下拉禁用态
	GameSettings.setting_changed.connect(_on_setting_changed)
	get_node(_LIST + "/BtnRow/TutorialButton").pressed.connect(
		func(): tutorial_rewatch_requested.emit())
	get_node(_LIST + "/BtnRow/ClearButton").pressed.connect(
		func(): clear_save_requested.emit())
	$Center/Panel/VBox/CloseButton.pressed.connect(func(): close_requested.emit())


func open() -> void:
	_sync()
	show()


func _on_setting_changed(key: String, value: Variant) -> void:
	if key == "fullscreen":
		fullscreen_check.set_pressed_no_signal(bool(value))
		window_size_option.disabled = bool(value)

func _sync() -> void:
	music_check.set_pressed_no_signal(bool(GameSettings.get_value("music_on")))
	sfx_check.set_pressed_no_signal(bool(GameSettings.get_value("sfx_on")))
	volume_slider.set_value_no_signal(float(GameSettings.get_value("music_volume")))
	sfx_volume_slider.set_value_no_signal(float(GameSettings.get_value("sfx_volume")))
	shake_check.set_pressed_no_signal(bool(GameSettings.get_value("screen_shake")))
	grid_check.set_pressed_no_signal(bool(GameSettings.get_value("show_grid")))
	fullscreen_check.set_pressed_no_signal(bool(GameSettings.get_value("fullscreen")))
	window_size_option.disabled = bool(GameSettings.get_value("fullscreen"))
	var ws_idx: int = GameSettings.WINDOW_SIZES.find(String(GameSettings.get_value("window_size")))
	window_size_option.select(maxi(ws_idx, 0))
