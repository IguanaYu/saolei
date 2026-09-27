extends SceneTree
## Exercise real level startup without recording test entries in the user's save.

var main: Node
var elapsed := 0.0
var stage := 0


func _initialize() -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)


func _process(delta: float) -> bool:
	elapsed += delta
	if stage == 0 and elapsed > 1.0:
		stage = 1
		root.get_node("SaveSystem").levels_entered["ch01_s01"] = true
		root.get_node("SaveSystem").levels_entered["ch01_s03"] = true
		main._start_level("ch01_s01")
		print("FLOW L1 cells=", main.grid.cells.size(), " style=", main.grid.wall_style)
	elif stage == 1 and elapsed > 1.5:
		stage = 2
		main._start_level("ch01_s03")
		print("FLOW L3 cells=", main.grid.cells.size(), " style=", main.grid.wall_style)
		for style in ["V2", "V2C", "V2M", "V2R"]:
			main.grid.set_wall_style(style)
			print("FLOW atlas=", style)
		for level_id in ["ch04_s01", "ch07_s01", "ch10_s01"]:
			root.get_node("SaveSystem").levels_entered[level_id] = true
			main._start_level(level_id)
			print("FLOW ", level_id, " style=", main.grid.wall_style)
	elif stage == 2 and elapsed > 2.1:
		quit()
	return false
