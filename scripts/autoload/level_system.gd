extends Node
## 关卡系统 autoload：持有 LevelDatabase，提供查询 / 解锁判断 / 首通领取 / 章节解锁链

const LevelDatabaseScript := preload("res://scripts/data/level_database.gd")

var db: LevelDatabase


func _ready() -> void:
	db = LevelDatabaseScript.new()


func get_level(id: String) -> LevelData:
	return db.get_level(id)


func get_chapter(id: String) -> ChapterData:
	return db.get_chapter(id)


func get_all_chapters() -> Array:
	return db.all_chapters()


func is_chapter_unlocked(ch_id: String) -> bool:
	return SaveSystem.is_chapter_unlocked(ch_id)


## 章节已解锁 + (首关 OR 上一关已通关)
## 试玩测试期：全部关卡直接解锁（作者/试玩者随时进任意关；正式版恢复下方注释的原链路）
func is_level_unlocked(id: String) -> bool:
	return get_level(id) != null
#	var lvl := get_level(id)
#	if lvl == null:
#		return false
#	if not is_chapter_unlocked(lvl.chapter_id):
#		return false
#	var ch := get_chapter(lvl.chapter_id)
#	var ids := ch.level_ids
#	if ids[0] == id:
#		return true
#	var prev_id: String = ids[ids.find(id) - 1]
#	return SaveSystem.is_level_cleared(prev_id)


## 章节顺序表中的下一关 ID（替代逐关 substr 提取编号——后者对 "ch01_s01" 恒取 0，
## 所有"下一关"都会跳回第 1 关，P1-06）。无后继（章末/ID 不存在）返回 ""
func get_next_level_id(id: String) -> String:
	var lvl := get_level(id)
	if lvl == null:
		return ""
	var ids: Array = get_chapter(lvl.chapter_id).level_ids
	var idx: int = ids.find(id)
	if idx < 0 or idx + 1 >= ids.size():
		return ""
	return ids[idx + 1]


## 章节内首个未通关关；全通返回末关（"继续试玩"与菜单文案共用此口径，P1-06/N8）
func get_first_uncleared_level_id(ch_id: String) -> String:
	var ch := get_chapter(ch_id)
	if ch == null:
		return ""
	for id in ch.level_ids:
		if not SaveSystem.is_level_cleared(id):
			return String(id)
	return String(ch.level_ids[-1])


## 领取首通奖励（矿石入账），返回奖励数据用于展示
func claim_first_clear(id: String) -> RewardData:
	var lvl := get_level(id)
	if lvl == null:
		return null
	SaveSystem.claim_first_clear(id)
	SaveSystem.add_ore(lvl.first_clear_reward.ore)
	return lvl.first_clear_reward


## 写通关记录 + 星数；章末触发下一章解锁 + 模块解锁链
func mark_cleared(id: String, stars: int) -> void:
	var prev := SaveSystem.get_level_stars(id)
	SaveSystem.set_level_cleared(id, max(prev, stars))
	var lvl := get_level(id)
	if lvl == null:
		return
	var chapter := get_chapter(lvl.chapter_id)
	if chapter == null or chapter.level_ids[-1] != id:
		return
	var ch_idx: int = chapter.id.substr(2).to_int()
	var next_ch := "ch%02d" % (ch_idx + 1)
	if next_ch != "ch13":
		SaveSystem.unlock_chapter(next_ch)
	if chapter.unlock_module == "opener_marker":
		pass  # 默认就有，无需操作
	elif chapter.unlock_module != "":
		SaveSystem.unlocks[chapter.unlock_module] = true
		SaveSystem.unlock_changed.emit(chapter.unlock_module)
		SaveSystem.save_game()
