extends Node
## 音频系统 autoload：SFX 播放池 + BGM + 总线音量 + 全局 UI 按钮音
## PROCESS_MODE_ALWAYS：暂停时 BGM 继续、设置面板按钮音可响

const SFX_DIR := "res://assets/audio/sfx/"
const BGM_PATH := "res://assets/audio/bgm/bgm_main.ogg"

## 音效注册表（素材落盘用统一文件名，见 docs/active/外部试玩版-v0.1-音效与BGM实施计划.md §2）
const SOUNDS := {
	"open": "open.ogg",
	"flag": "flag.ogg",
	"mine": "mine.ogg",
	"coin": "coin.ogg",
	"buy": "buy.ogg",
	"upgrade": "upgrade.ogg",
	"win": "win.ogg",
	"lose": "lose.ogg",
	"ui": "ui.ogg",
	"heartbeat": "heartbeat.ogg",
}

## 同类音效最小重播间隔（ms）——防机器人高频开格糊成一团
const THROTTLE_MS := {"open": 90, "flag": 80, "coin": 120}

const SFX_POOL_SIZE := 8

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _bgm: AudioStreamPlayer
var _last_play_ms: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_streams()
	for i in SFX_POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "SfxPlayer%d" % i  # 显式命名，避免遍历误匹配
		p.bus = &"SFX"
		add_child(p)
		_players.append(p)
	_bgm = AudioStreamPlayer.new()
	_bgm.name = "BgmPlayer"
	_bgm.bus = &"Music"
	add_child(_bgm)
	_apply_bus_volumes()
	GameSettings.setting_changed.connect(_on_setting_changed)
	_connect_buttons_recursive(get_tree().root)
	get_tree().node_added.connect(_on_node_added)
	play_bgm()


func play_sfx(sname: String, pitch := 1.0, delay_s := 0.0) -> void:
	if not bool(GameSettings.get_value("sfx_on")):
		return
	var stream: AudioStream = _streams.get(sname)
	if stream == null:
		return
	var throttle: int = int(THROTTLE_MS.get(sname, 0))
	if delay_s <= 0.0 and throttle > 0:
		var now := Time.get_ticks_msec()
		if now - int(_last_play_ms.get(sname, 0)) < throttle:
			return
		_last_play_ms[sname] = now
	if delay_s > 0.0:
		get_tree().create_timer(delay_s).timeout.connect(
			func(): _play_now(stream, pitch))
	else:
		_play_now(stream, pitch)


func play_bgm() -> void:
	if not ResourceLoader.exists(BGM_PATH):
		push_warning("BGM 缺失：%s" % BGM_PATH)
		return
	var s: AudioStream = load(BGM_PATH)
	if s is AudioStreamOggVorbis:
		s.loop = true
	_bgm.stream = s
	_bgm.play()


# ---- 内部 ----

func _play_now(stream: AudioStream, pitch: float) -> void:
	if not bool(GameSettings.get_value("sfx_on")):
		return
	for p in _players:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = pitch * randf_range(0.96, 1.04)
			p.play()
			return
	# 池满：丢弃（宁可丢音不可截断）


func _load_streams() -> void:
	for sname in SOUNDS:
		var path := SFX_DIR + String(SOUNDS[sname])
		if ResourceLoader.exists(path):
			_streams[sname] = load(path)
		else:
			push_warning("音效缺失：%s" % path)


func _apply_bus_volumes() -> void:
	var m := AudioServer.get_bus_index("Music")
	AudioServer.set_bus_volume_db(m, linear_to_db(
		clampf(float(GameSettings.get_value("music_volume")), 0.0, 1.0) * 0.6))
	AudioServer.set_bus_mute(m, not bool(GameSettings.get_value("music_on")))
	var s := AudioServer.get_bus_index("SFX")
	AudioServer.set_bus_volume_db(s, linear_to_db(
		clampf(float(GameSettings.get_value("sfx_volume")), 0.0, 1.0)))
	AudioServer.set_bus_mute(s, not bool(GameSettings.get_value("sfx_on")))


func _on_setting_changed(key: String, _v: Variant) -> void:
	if key in ["music_on", "music_volume", "sfx_on", "sfx_volume"]:
		_apply_bus_volumes()


# ---- 全局 UI 按钮音 ----

func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		_connect_button(node)


func _connect_buttons_recursive(root_node: Node) -> void:
	if root_node is BaseButton:
		_connect_button(root_node)
	for c in root_node.get_children():
		_connect_buttons_recursive(c)


func _connect_button(btn: BaseButton) -> void:
	if not btn.pressed.is_connected(_on_button_pressed):
		btn.pressed.connect(_on_button_pressed)


func _on_button_pressed() -> void:
	play_sfx("ui")
