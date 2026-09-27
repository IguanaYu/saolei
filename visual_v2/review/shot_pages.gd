extends SceneTree
## Visual QA of the remaining UI pages. No clicks and no save writes.

const PAGES := [
	"ChapterSelect", "LevelSelect", "PausePanel", "SettingsPanel",
	"StatsPanel", "DailyPanel", "SignInPanel", "UpgradePanel",
]

var main: Node
var elapsed := 0.0
var index := -1
var next_at := 2.5


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	elapsed += delta
	if elapsed < next_at:
		return false
	if index >= 0:
		var page_name: String = PAGES[index]
		var file_name := "page_%s.png" % page_name.to_snake_case()
		root.get_texture().get_image().save_png("res://visual_v2/review/" + file_name)
		print("V2_PAGE ", page_name)
		main.get_node("UILayer/" + page_name).hide()
	index += 1
	if index >= PAGES.size():
		quit()
		return false
	main.get_node("UILayer/SplashScreen").hide()
	main.get_node("UILayer/SignInPanel").hide()
	main.get_node("UILayer/MainMenu").hide()
	var page = main.get_node("UILayer/" + PAGES[index])
	if PAGES[index] == "ChapterSelect":
		page.refresh()
	elif PAGES[index] == "LevelSelect":
		page.set_chapter("ch01")
	if PAGES[index] in ["StatsPanel", "DailyPanel"]:
		page.open()
	else:
		page.show()
	next_at = elapsed + 0.35
	return false
