class_name ChapterData
extends Resource
## 章节信息

var id: String = ""              # "ch01"
var display_name: String = ""    # "新手村"
var level_ids: Array = []        # 5 个 LevelData.id
var unlock_module: String = ""   # 章末通关解锁的模块，如 "detector"
var theme_color: Color = Color(0.6, 0.6, 0.6)
