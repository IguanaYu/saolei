extends Node
## 无头验证：Music/SFX 总线存在 + GameSettings 音量即时反映到 AudioServer 总线

func _ready() -> void:
	var ok := true
	var m := AudioServer.get_bus_index("Music")
	var s := AudioServer.get_bus_index("SFX")
	if m < 0:
		push_error("FAIL: Music 总线不存在")
		ok = false
	if s < 0:
		push_error("FAIL: SFX 总线不存在")
		ok = false
	if ok:
		print("PASS: 总线存在 Music=%d SFX=%d" % [m, s])

	# 默认值应用（autoload 已跑 _apply_bus_volumes）
	var db0 := AudioServer.get_bus_volume_db(m)
	print("INFO: 默认 music_volume=%.2f -> Music bus %.1f dB" % [
		float(GameSettings.get_value("music_volume")), db0])

	# 改设置 -> 总线应立即变化
	GameSettings.set_value("music_volume", 0.3)
	var db1 := AudioServer.get_bus_volume_db(m)
	print("INFO: music_volume=0.30 -> Music bus %.1f dB" % db1)
	if absf(db1 - db0) < 0.5:
		push_error("FAIL: 音乐音量调节未生效")
		ok = false
	else:
		print("PASS: 音乐音量即时生效")

	GameSettings.set_value("sfx_volume", 0.2)
	var sdb := AudioServer.get_bus_volume_db(s)
	print("INFO: sfx_volume=0.20 -> SFX bus %.1f dB" % sdb)
	GameSettings.set_value("sfx_on", false)
	if not AudioServer.is_bus_mute(s):
		push_error("FAIL: 音效关闭未静音总线")
		ok = false
	else:
		print("PASS: 音效开关即时生效")

	# 还原默认，避免污染用户存档
	GameSettings.set_value("sfx_on", true)
	GameSettings.set_value("music_volume", 0.7)
	GameSettings.set_value("sfx_volume", 0.8)

	print("ALL_PASS" if ok else "HAS_FAIL")
	get_tree().quit(0 if ok else 1)
