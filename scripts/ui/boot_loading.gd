extends Control
## 开机加载页（2026-10-02 启动卡顿二期）：窗口秒出本页，主场景加载期间本页可见，
## 吸收原闪屏的露出时长（加载与 LOGO 展示并行）——全程有画面，消灭黑窗静止期。
## 流程：进度条走完 → 同步加载并实例化 Main（耗时帧发生在本页仍可见时，无黑帧）→
## 淡出 → 挂树为主场景；Main 侧见 GameState.boot_splash_played 直接亮主菜单（跳过场景内闪屏）。
## 2026-10-04 回归修复：原 load_threaded_request(use_sub_threads=true) 在渲染模式下
## 对 Main.tscn 这种重依赖图是概率性分钟级卡死（并行脚本编译竞态，实测同图同步加载
## 仅 0.6s、headless 正常、渲染窗口时快时挂），改为确定性同步加载，页面期间无黑帧不受影响。

const MAIN_SCENE_PATH := "res://scenes/Main.tscn"
const MIN_SHOW_SEC := 1.2    # LOGO 最短露出（≈原闪屏 0.8 停留 + 0.35 淡出）
const FADE_SEC := 0.35       # 加载页淡出时长
const BAR_RATE := 1.2        # 无真实进度源（同步加载在进入时才发生），进度条按时间平滑冲满

@onready var _slot: ColorRect = $Center/VBox/ProgressSlot
@onready var _fill: ColorRect = $Center/VBox/ProgressSlot/ProgressFill
@onready var _status_label: Label = $Center/VBox/StatusLabel

var _elapsed := 0.0
var _shown := 0.0   # 进度平滑显示值
var _done := false


func _ready() -> void:
	_status_label.text = "正在加载…"


func _process(delta: float) -> void:
	if _done:
		return
	_elapsed += delta
	_shown = move_toward(_shown, 1.0, delta * BAR_RATE)
	_fill.size.x = _slot.size.x * _shown
	if _elapsed >= MIN_SHOW_SEC and is_equal_approx(_shown, 1.0):
		_status_label.text = "即将进入…"
		_enter_main()


func _enter_main() -> void:
	_done = true
	# 同步加载+实例化（合计 <1s，2026-10-04 实测）：耗时帧发生在加载页仍可见时
	var packed: PackedScene = load(MAIN_SCENE_PATH)
	if packed == null:
		push_error("BootLoading: 主场景加载失败 " + MAIN_SCENE_PATH)
		return
	var main_inst: Node = packed.instantiate()
	var tw := create_tween()
	tw.tween_property(self, "modulate:a", 0.0, FADE_SEC)
	tw.tween_callback(func() -> void:
		GameState.boot_splash_played = true
		var tree := get_tree()
		tree.current_scene.queue_free()   # 释放本加载页（自身，deferred 安全）
		tree.root.add_child(main_inst)
		tree.current_scene = main_inst)
