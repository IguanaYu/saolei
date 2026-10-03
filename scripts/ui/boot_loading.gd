extends Control
## 开机加载页（2026-10-02 启动卡顿二期）：窗口秒出本页，主场景走后台线程加载，
## 吸收原闪屏的露出时长（加载与 LOGO 展示并行）——全程有画面，消灭黑窗静止期。
## 流程：进度条走完 → 实例化 Main（卡帧发生在本页仍可见时，无黑帧）→ 淡出 →
## 挂树为主场景；Main 侧见 GameState.boot_splash_played 直接亮主菜单（跳过场景内闪屏）。

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const MIN_SHOW_SEC := 1.2    # LOGO 最短露出（≈原闪屏 0.8 停留 + 0.35 淡出）
const FADE_SEC := 0.35

@onready var _slot: ColorRect = $Center/VBox/ProgressSlot
@onready var _fill: ColorRect = $Center/VBox/ProgressSlot/ProgressFill
@onready var _status_label: Label = $Center/VBox/StatusLabel

var _elapsed := 0.0
var _shown := 0.0   # 进度平滑显示值（真实进度分批跳变，直接显示会一顿一顿）
var _done := false


func _ready() -> void:
	# use_sub_threads=true：Main 的子资源并行加载
	var err := ResourceLoader.load_threaded_request(MAIN_SCENE_PATH, "", true)
	if err != OK:
		_fallback_sync()


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	var progress: Array = []
	var status := ResourceLoader.load_threaded_get_status(MAIN_SCENE_PATH, progress)
	var target := float(progress[0]) if progress.size() > 0 else 0.0
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		target = 1.0
	# 加载完成后进度条提速冲满（配合"即将进入"文案，避免条还停在半程的割裂感）
	var speed := 3.0 if status == ResourceLoader.THREAD_LOAD_LOADED else 1.4
	_shown = move_toward(_shown, target, delta * speed)
	_fill.size.x = _slot.size.x * _shown
	match status:
		ResourceLoader.THREAD_LOAD_FAILED, ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_fallback_sync()
		ResourceLoader.THREAD_LOAD_LOADED:
			_status_label.text = "即将进入…"
			if _elapsed >= MIN_SHOW_SEC and is_equal_approx(_shown, 1.0):
				_enter_main()


func _enter_main() -> void:
	_done = true
	# 先实例化再淡出：树构建的耗时帧发生在加载页还可见时
	var packed: PackedScene = ResourceLoader.load_threaded_get(MAIN_SCENE_PATH)
	var main_inst: Node = packed.instantiate()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_SEC)
	tw.tween_callback(func() -> void:
		GameState.boot_splash_played = true
		var tree := get_tree()
		tree.current_scene.queue_free()   # 释放本加载页（自身，deferred 安全）
		tree.root.add_child(main_inst)
		tree.current_scene = main_inst)


## 后台加载启动失败兜底：退回同步加载路径
func _fallback_sync() -> void:
	_done = true
	push_error("BootLoading: 后台加载失败，回退同步加载 " + MAIN_SCENE_PATH)
	GameState.boot_splash_played = true   # 免得 Main 再播一遍闪屏
	get_tree().change_scene_to_file(MAIN_SCENE_PATH)
