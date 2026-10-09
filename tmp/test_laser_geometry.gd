extends SceneTree
const LG = preload("res://scripts/laser/laser_geometry.gd")
## tmp/test_laser_geometry.gd — LaserGeometry 单元测试（headless -s 模式）
## 运行：Godot --headless -s tmp/test_laser_geometry.gd --path <项目>
## 纯静态类测试：不依赖 autoload/场景（-s 模式看不到 autoload 的已知限制不适用）
## 同时导出 Python 对拍表（WP6 烘焙 finder 的移植基准），见末尾 DUMP_PY_TABLE

var _fails: int = 0
var _passes: int = 0


func _init() -> void:
	_test_beam_straight()
	_test_beam_diagonal()
	_test_beam_slope()
	_test_beam_corner_pair()
	_test_beam_edges()
	_test_octant()
	_dump_py_table()
	if _fails == 0:
		print("ALL_OK %d asserts" % _passes)
		quit(0)
	else:
		print("FAILED %d/%d" % [_fails, _passes + _fails])
		quit(1)


func _check(name: String, got, want) -> void:
	var ok: bool = false
	if typeof(got) == typeof(want):
		ok = got == want
	else:
		ok = str(got) == str(want)
	if ok:
		_passes += 1
	else:
		_fails += 1
		print("FAIL %s\n  got  %s\n  want %s" % [name, str(got), str(want)])


func _test_beam_straight() -> void:
	_check("水平线", LG.beam_cells(Vector2i(0, 0), Vector2i(3, 0)),
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)])
	_check("反向水平", LG.beam_cells(Vector2i(3, 0), Vector2i(0, 0)),
		[Vector2i(2, 0), Vector2i(1, 0), Vector2i(0, 0)])
	_check("垂直线", LG.beam_cells(Vector2i(2, 2), Vector2i(2, 5)),
		[Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5)])
	_check("相邻格", LG.beam_cells(Vector2i(4, 4), Vector2i(5, 4)),
		[Vector2i(5, 4)])
	_check("同格为空", LG.beam_cells(Vector2i(4, 4), Vector2i(4, 4)), [])


func _test_beam_diagonal() -> void:
	# 45° 斜线：恰过每个格点 → 横竖两格都收（先横后竖的超覆盖口径）
	_check("短斜线", LG.beam_cells(Vector2i(0, 0), Vector2i(1, 1)),
		[Vector2i(1, 0), Vector2i(1, 1)])
	_check("长斜线", LG.beam_cells(Vector2i(0, 0), Vector2i(3, 3)),
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1),
			Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)])
	_check("反向斜线", LG.beam_cells(Vector2i(3, 3), Vector2i(1, 1)),
		[Vector2i(2, 3), Vector2i(2, 2), Vector2i(1, 2), Vector2i(1, 1)])


func _test_beam_slope() -> void:
	# (0,0)→(3,2)：格心线 y=0.5+(2/3)(x-0.5)，穿 (1,0)(1,1)(2,1)(2,2)(3,2)
	_check("斜率2/3", LG.beam_cells(Vector2i(0, 0), Vector2i(3, 2)),
		[Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1),
			Vector2i(2, 2), Vector2i(3, 2)])
	# (0,0)→(2,3)：镜像
	_check("斜率3/2", LG.beam_cells(Vector2i(0, 0), Vector2i(2, 3)),
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2),
			Vector2i(2, 2), Vector2i(2, 3)])
	# (0,0)→(4,1)：缓斜率——竖线事件 t=(0.5)/4, (1.5)/4, (2.5)/4, (3.5)/4；横线 t=0.5/1
	# 线 y=0.5+x/4：x=0.5→y=0.625(行0)；x=2→y=1.0 恰过格点(2,1)！
	# 事件：X(1*1=1) Y(1*4=4) X(3*1=3)——X3 先于 Y4？t_x2=(1.5)/4=0.375 vs t_y=0.5 →
	# 排序 X1(0.125) X3(0.375) Y4(0.5) X5(0.625) X7(0.875)——无同刻 → (1,0)(2,0)(2,1)(3,1)(4,1)
	_check("缓斜率", LG.beam_cells(Vector2i(0, 0), Vector2i(4, 1)),
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1),
			Vector2i(3, 1), Vector2i(4, 1)])


func _test_beam_corner_pair() -> void:
	# (0,0)→(4,2)：中点 (2.5,1.5)——线恰过格点(2,1)（x=2 时 y=1.0）：
	# X 键 (1)*2=2,(3)*2=6,(5)*2=10,(7)*2=14；Y 键 (1)*4=4,(3)*4=12 → 无同刻对？
	# 恰过格点要求 i/ax == j/ay 且格点在整数网格上：x=2 → t=1.5/4；y=1 → t=0.5/2=0.25 ≠ 0.375。
	# 修正：x=2 时线 y=0.5+(1/2)(1.5)=1.25 ≠ 整数 → 无格点穿越。改用真实格点例：
	# (0,0)→(2,1)：线 y=0.5+x/4，x=2 → y=1.0 恰过格点 (2,1)。事件 X 键 1,3；Y 键 1*2=2。
	# 排序 X1(0.25) Y2(0.5) X3(0.75)——无同刻。真正的同刻例是 45° 与 (0,0)→(4,2) 的中点：
	# (0,0)→(4,2)：x=2.5 处 y=1.5——非格点。取 (1,0)→(3,1)：线过格点(2,0)? y at x=2: 
	# 线从(1.5,0.5)到(3.5,1.5)：y=0.5+0.5(x-1.5)；x=2→y=0.75≠整数。构造同刻：
	# (0,0)→(6,2)：x=3 → y=0.5+ (1/3)(2.5)=1.333≠整。(0,0)→(6,3)：45°分量(3,3)…非整斜率
	# 同刻 ⇔ (2i-1)|dy| == (2j-1)|dx| ⇔ (2i-1)/(2j-1) == |dx|/|dy|：如 dx/dy=3/1、i=2,j=1：
	# (3)/(1)=3 ✓ → (0,0)→(3,1)：X 键 1,3,5；Y 键 3 → X3 与 Y3 同刻（先横后竖）
	_check("真格点对(3:1)", LG.beam_cells(Vector2i(0, 0), Vector2i(3, 1)),
		[Vector2i(1, 0), Vector2i(2, 0), Vector2i(2, 1), Vector2i(3, 1)])
	_check("真格点对(1:3)", LG.beam_cells(Vector2i(0, 0), Vector2i(1, 3)),
		[Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 2), Vector2i(1, 3)])


func _test_beam_edges() -> void:
	# 起点不含、终点含（发射点=基地格不受伤）
	var cells := LG.beam_cells(Vector2i(5, 5), Vector2i(9, 5))
	_check("起点不含", cells.has(Vector2i(5, 5)), false)
	_check("终点含", cells.has(Vector2i(9, 5)), true)
	# 去重保序：穿角两格后不重复出现
	var diag := LG.beam_cells(Vector2i(0, 0), Vector2i(3, 3))
	var seen: Dictionary = {}
	var dup := false
	for c in diag:
		if seen.has(c):
			dup = true
		seen[c] = true
	_check("无重复格", dup, false)


func _test_octant() -> void:
	_check("东", LG.octant_dir(Vector2i(0, 0), Vector2i(9, 1)), Vector2i(1, 0))
	_check("东南", LG.octant_dir(Vector2i(0, 0), Vector2i(3, 3)), Vector2i(1, 1))
	_check("南", LG.octant_dir(Vector2i(0, 0), Vector2i(1, 9)), Vector2i(0, 1))
	_check("西", LG.octant_dir(Vector2i(0, 0), Vector2i(-9, 2)), Vector2i(-1, 0))
	_check("北西", LG.octant_dir(Vector2i(0, 0), Vector2i(-2, -3)), Vector2i(-1, -1))
	_check("同格", LG.octant_dir(Vector2i(2, 2), Vector2i(2, 2)), Vector2i.ZERO)
	_check("旋转+1", LG.rotate_octant(Vector2i(1, 0), 1), Vector2i(1, 1))
	_check("旋转-1", LG.rotate_octant(Vector2i(1, 0), -1), Vector2i(1, -1))
	_check("旋转-9回绕", LG.rotate_octant(Vector2i(0, 1), -9), Vector2i(1, 1))


## Python 对拍表：WP6 finder 移植 beam_cells 后必须逐 case 复算一致
func _dump_py_table() -> void:
	var cases: Array = [
		[Vector2i(0, 0), Vector2i(3, 0)], [Vector2i(0, 0), Vector2i(0, 3)],
		[Vector2i(0, 0), Vector2i(3, 3)], [Vector2i(0, 0), Vector2i(3, 2)],
		[Vector2i(0, 0), Vector2i(2, 3)], [Vector2i(0, 0), Vector2i(4, 1)],
		[Vector2i(0, 0), Vector2i(3, 1)], [Vector2i(1, 6), Vector2i(11, 6)],
		[Vector2i(1, 6), Vector2i(9, 11)], [Vector2i(1, 6), Vector2i(8, 0)],
		[Vector2i(2, 3), Vector2i(10, 9)], [Vector2i(5, 5), Vector2i(6, 5)],
	]
	print("PY_TABLE_BEGIN")
	for c in cases:
		print("%s->%s %s" % [c[0], c[1],
			str(LG.beam_cells(c[0], c[1])).replace("[", "").replace("]", "")])
	print("PY_TABLE_END")
