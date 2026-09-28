extends Control
## 设置面板：声音（音乐/音效开关+音量，经 AudioManager 即时生效）/ 画面与操作 / 游戏

signal close_requested
signal clear_save_requested
signal tutorial_rewatch_requested

@onready var music_check: CheckButton = $Center/Panel/VBox/RowMusic/HBox/MusicCheck
@onready var sfx_check: CheckButton = $Center/Panel/VBox/RowSfx/HBox/SfxCheck
@onready var volume_slider: HSlider = $Center/Panel/VBox/RowVolume/HBox/VolumeSlider
@onready var sfx_volume_slider: HSlider = $Center/Panel/VBox/RowSfxVolume/HBox/SfxVolumeSlider
@onready var shake_check: CheckButton = $Center/Panel/VBox/RowShake/HBox/ShakeCheck
@onready var grid_check: CheckButton = $Center/Panel/VBox/RowGrid/HBox/GridCheck
@onready var fullscreen_check: CheckButton = $Center/Panel/VBox/RowFullscreen/HBox/FullscreenCheck


func _ready() -> void:
	hide()
	music_check.toggled.connect(func(v): GameSettings.set_value("music_on", v))
	sfx_check.toggled.connect(func(v): GameSettings.set_value("sfx_on", v))
	volume_slider.value_changed.connect(func(v): GameSettings.set_value("music_volume", v))
	sfx_volume_slider.value_changed.connect(func(v): GameSettings.set_value("sfx_volume", v))
	shake_check.toggled.connect(func(v): GameSettings.set_value("screen_shake", v))
	grid_check.toggled.connect(func(v): GameSettings.set_value("show_grid", v))
	fullscreen_check.toggled.connect(func(v): GameSettings.set_value("fullscreen", v))
	$Center/Panel/VBox/BtnRow/TutorialButton.pressed.connect(
		func(): tutorial_rewatch_requested.emit())
	$Center/Panel/VBox/BtnRow/ClearButton.pressed.connect(
		func(): clear_save_requested.emit())
	$Center/Panel/VBox/CloseButton.pressed.connect(func(): close_requested.emit())


func open() -> void:
	_sync()
	show()


func _sync() -> void:
	music_check.set_pressed_no_signal(bool(GameSettings.get_value("music_on")))
	sfx_check.set_pressed_no_signal(bool(GameSettings.get_value("sfx_on")))
	volume_slider.set_value_no_signal(float(GameSettings.get_value("music_volume")))
	sfx_volume_slider.set_value_no_signal(float(GameSettings.get_value("sfx_volume")))
	shake_check.set_pressed_no_signal(bool(GameSettings.get_value("screen_shake")))
	grid_check.set_pressed_no_signal(bool(GameSettings.get_value("show_grid")))
	fullscreen_check.set_pressed_no_signal(bool(GameSettings.get_value("fullscreen")))
