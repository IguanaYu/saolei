extends RefCounted
## 一个角色一个微循环。只切换已有 Skin 帧，不驱动移动、作业或随机玩法。

const SHEETS := {
	"opener": preload("res://visual_v2/runtime/micro_animations/v1/robots/opener_sheet.png"),
	"marker": preload("res://visual_v2/runtime/micro_animations/v1/robots/marker_sheet.png"),
	"detector": preload("res://visual_v2/runtime/micro_animations/v1/robots/detector_sheet.png"),
	"miner": preload("res://visual_v2/runtime/micro_animations/v1/robots/miner_sheet.png"),
	"guard": preload("res://visual_v2/runtime/micro_animations/v1/robots/guard_sheet.png"),
	"web": preload("res://visual_v2/runtime/micro_animations/v1/enemies/web_sheet.png"),
	"lock": preload("res://visual_v2/runtime/micro_animations/v1/enemies/lock_sheet.png"),
	"slow": preload("res://visual_v2/runtime/micro_animations/v1/enemies/slow_sheet.png"),
	"slime": preload("res://visual_v2/runtime/micro_animations/v1/enemies/slime_sheet.png"),
}
const PATTERNS := {
	"opener": {"frames": [0, 1, 2], "seconds": [0.3, 0.3, 0.3]},
	"marker": {"frames": [0, 1, 0, 2, 0], "seconds": [1.4, 0.25, 0.25, 0.25, 0.85]},
	"detector": {"frames": [0, 1, 2, 1], "seconds": [0.45, 0.45, 0.45, 0.45]},
	"miner": {"frames": [0, 1, 2], "seconds": [0.35, 0.35, 0.35]},
	"guard": {"frames": [0, 1], "seconds": [0.6, 0.6]},
	"web": {"frames": [0, 1, 2], "seconds": [0.5, 0.4, 0.6]},
	"lock": {"frames": [0, 1, 2], "seconds": [0.7, 0.4, 0.7]},
	"slow": {"frames": [0, 1, 2], "seconds": [1.0, 0.5, 0.9]},
	"slime": {"frames": [0, 1, 2], "seconds": [0.7, 0.4, 0.7]},
}

var _skin: Sprite2D = null
var _kind := ""
var _step := 0
var _timer := 0.0
var _cycle_seconds := 0.0
var _rng := RandomNumberGenerator.new()  # 独立视觉随机源，不消耗地图/寻路随机序列


func _init() -> void:
	_rng.randomize()


static func has_animation(kind: String) -> bool:
	return SHEETS.has(kind)


static func is_gameplay_running(owner: Node) -> bool:
	if not GameState.game_active or owner.get_tree().paused:
		return false
	var guide := owner.get_node_or_null("/root/Main/UILayer/TutorialGuide") as CanvasItem
	return guide == null or not guide.visible


func configure(skin: Sprite2D, kind: String) -> void:
	if not has_animation(kind) or (_skin == skin and _kind == kind):
		return
	_skin = skin
	_kind = kind
	_skin.texture = SHEETS[kind]
	_skin.hframes = 3
	_skin.vframes = 1
	_skin.frame = 0
	_skin.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_step = 0
	_timer = 0.0
	_cycle_seconds = 0.0
	for seconds in PATTERNS[kind].seconds:
		_cycle_seconds += float(seconds)
	advance(_rng.randf() * _cycle_seconds)  # 同类实体随机错开起点


func advance(delta: float) -> void:
	if not is_instance_valid(_skin) or _kind == "":
		return
	var pattern: Dictionary = PATTERNS[_kind]
	var seconds: Array = pattern.seconds
	var frames: Array = pattern.frames
	_timer += fmod(maxf(delta, 0.0), _cycle_seconds)
	while _timer >= float(seconds[_step]):
		_timer -= float(seconds[_step])
		_step = (_step + 1) % frames.size()
	_skin.frame = int(frames[_step])
