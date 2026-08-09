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
func is_level_unlocked(id: String) -> bool:
	var lvl := get_level(id)
	if lvl == null:
		return false
	if not is_chapter_unlocked(lvl.chapter_id):
		return false
	var ch := get_chapter(lvl.chapter_id)
	var ids := ch.level_ids
	if ids[0] == id:
		return true
	var prev_id: String = ids[ids.find(id) - 1]
	return SaveSystem.is_level_cleared(prev_id)


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
