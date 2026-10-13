extends RefCounted
## 小图、关前短句与统计图标统一从本章正式素材读取。
const ICON_DIR := "res://visual_v2/runtime/ch02_v1/ui/"
const LEVELS := {
	"ch02_s01": {"icon": "laser", "tip": "左键发射激光，每次削一层墙。先插旗保护钻石，再开墙。"},
	"ch02_s02": {"icon": "builder", "tip": "激光为开墙、标雷机充能 6 秒。筑墙工有两点耐久，击破后已造的墙仍保留。"},
	"ch02_s03": {"icon": "special_ore", "tip": "晶簇占 2×2、挡光挡路。每次命中随机射出三道短光束，可以反复使用。"},
	"ch02_s04": {"icon": "overload", "tip": "过载机自动巡逻，激光命中引爆 13 格，本体存活。扩爆只延长四条直臂，变为 17 格。"},
}


static func icon(kind: String) -> Texture2D:
	return load(ICON_DIR + "icon_" + kind + ".png")


static func level_icon(id: String) -> Texture2D:
	return icon(LEVELS[id].icon) if LEVELS.has(id) else null


static func level_tip(id: String) -> String:
	return LEVELS[id].tip if LEVELS.has(id) else ""
