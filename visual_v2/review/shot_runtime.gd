extends SceneTree
## Short-lived visual review runner. Saves screenshots inside visual_v2/review.

var _main: Node
var _elapsed := 0.0
var _stage := 0


func _initialize() -> void:
	var main_scene: PackedScene = load("res://scenes/Main.tscn")
	_main = main_scene.instantiate()
	root.add_child(_main)


func _process(delta: float) -> bool:
	_elapsed += delta
	if _stage == 0 and _elapsed > 2.5:
		_stage = 1
		_main.splash.hide()
		_main.sign_in_panel.hide()
		_main.daily_panel.hide()
		_main.main_menu.show()
	elif _stage == 1 and _elapsed > 2.7:
		_stage = 2
		_capture("menu_actual.png")
		# Assemble the review board directly so taking screenshots never changes user save data.
		_main.main_menu.hide()
		var level = root.get_node("LevelSystem").get_level("ch01_s01")
		root.get_node("GameState").reset_state(level.id, level)
		_main.grid.wall_style = "V2"
		_main.grid.configure(level.grid_size.x, level.grid_size.y, level.mine_count)
		_main.grid.apply_fixed_board({"mines": level.fixed_mines,
			"preopen": level.preopen_coords, "base": level.fixed_base})
		_main.get_node("CaveEnv").layout_env()
		_main.tutorial_guide.hide()
		_main.sign_in_panel.hide()
	elif _stage == 2 and _elapsed > 3.7:
		_stage = 3
		_main.tutorial_guide.hide()
		_main.sign_in_panel.hide()
	elif _stage == 3 and _elapsed > 4.0:
		_stage = 4
		_capture("game_actual.png")
		var large_level = root.get_node("LevelSystem").get_level("ch01_s03")
		root.get_node("GameState").reset_state(large_level.id, large_level)
		_main.grid.configure(large_level.grid_size.x, large_level.grid_size.y,
			large_level.mine_count)
		_main.grid.apply_fixed_board({"mines": large_level.fixed_mines,
			"preopen": large_level.preopen_coords, "base": large_level.fixed_base})
		_main.get_node("CaveEnv").layout_env()
	elif _stage == 4 and _elapsed > 4.7:
		_stage = 5
		_capture("game_large_actual.png")
		_main.results_panel.show()
	elif _stage == 5 and _elapsed > 5.5:
		_stage = 6
		_capture("results_actual.png")
		quit()
	return false


func _capture(file_name: String) -> void:
	var picture := root.get_texture().get_image()
	var path := "res://visual_v2/review/" + file_name
	picture.save_png(path)
	print("V2_SCREENSHOT ", path, " ", picture.get_size())
