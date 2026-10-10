class_name LightPillar
extends Node2D
## 2-5 引光柱（总纲 §6.4）：预开安全格上的中立增幅定向设施。
## 存活时折光出射主轴必指向柱（几何改写在 LaserManager.compute_shot_geometry 快照阶段，
## 以射击开始的柱存活态为准——破碎的方向变化从下一轮生效）；耐久 6：每轮命中 -1
## （多源同轮合计 1，去重在 laser_manager 侧）；6s 未受击后每 3s 恢复 1 至 6
## （首次恢复=末次受击后第 9s，设计 §4 精确口径；elapsed 基准天然跟随暂停/引导冻结）。
## 破碎 -50 分（钳 0）在 laser_manager 结算序内完成；本类只管状态/耐久条/演出。

const HP_MAX := 6
const RECOVER_WAIT_SEC := 6.0   # 末次受击后的停火等待
const RECOVER_STEP_SEC := 3.0   # 等待期满后每 3s 恢复 1

var coord: Vector2i = Vector2i(-9, -9)
var hp: int = HP_MAX
var last_hit_elapsed: float = -999.0
var is_alive: bool = true

var _recover_timer := 0.0       # 停火等待期满后的步进累计（受击即清零）

signal pillar_broken(p: LightPillar)   # 破碎（director 句/埋点挂点；扣分在 laser_manager）
signal pillar_low_warning(p: LightPillar)  # 首次降到 hp≤2（director 轻提示挂点）
signal pillar_recovered(_p: LightPillar)   # 首次恢复一格（director「停火恢复」句挂点）


func setup(c: Vector2i, grid) -> void:
	coord = c
	z_index = 9  # 压过格子与节点(8)，低于虫(10)
	position = grid.coord_to_world(c)
	queue_redraw()


## 受击单入口（同轮去重由 laser_manager 保证）；返回是否致命。
## 同一次射击不能既打破又恢复：结算与 tick 不同帧，天然成立（断言进实测）
func take_hit() -> bool:
	if not is_alive:
		return false
	hp -= 1
	last_hit_elapsed = GameState.elapsed
	_recover_timer = 0.0
	if hp == 2:
		pillar_low_warning.emit(self)
	GameState.result_stats["pillar_lowest_hp"] = mini(
			int(GameState.result_stats.get("pillar_lowest_hp", HP_MAX)), hp)
	queue_redraw()
	if hp <= 0:
		is_alive = false
		pillar_broken.emit(self)
		return true
	return false


## 恢复推进（facility_manager.tick → main._process 驱动；三重门冻结时不会进来）
func tick(delta: float) -> void:
	if not is_alive or hp >= HP_MAX:
		return
	if GameState.elapsed - last_hit_elapsed < RECOVER_WAIT_SEC:
		return   # 停火等待期未满（重复命中在此重置）
	_recover_timer += delta
	while _recover_timer >= RECOVER_STEP_SEC and hp < HP_MAX:
		_recover_timer -= RECOVER_STEP_SEC
		hp = mini(HP_MAX, hp + 1)
		pillar_recovered.emit(self)
		queue_redraw()


## 定向轴方向（折光→柱；几何改写用）：柱不在/已碎返回 Vector2i.ZERO
func axis_dir_from(from_coord: Vector2i) -> Vector2i:
	if not is_alive:
		return Vector2i.ZERO
	return LaserGeometry.octant_dir(from_coord, coord)


## 破碎演出：碎块淡出（程序绘制，素材批后换贴图）；-50 跳字在 laser_manager 结算侧
func play_break(grid) -> void:
	var fx: EffectsLayer = grid.get_node_or_null("EffectsLayer") as EffectsLayer
	if fx != null:
		fx.fx_pillar_broken(grid.get_cell(coord))
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(1.3, 0.6), 0.18).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(self, "modulate:a", 0.0, 0.30)
	tw.tween_callback(queue_free)


func _draw() -> void:
	# 本体：暖玉色竖柱 + 顶冠 + 底座（程序绘制占位）；耐久条单条 6 段在柱顶上方
	var body_col := Color(0.93, 0.86, 0.58, 0.96)
	if hp <= 2 and is_alive:
		body_col = Color(0.95, 0.45, 0.30, 0.96)  # 剩 2 变色预警（暖橙→暗红，设计 §4）
	draw_rect(Rect2(-4, -13, 8, 22), body_col)
	draw_rect(Rect2(-6, -16, 12, 4), Color(1.0, 0.96, 0.75))
	draw_rect(Rect2(-6, 8, 12, 3), Color(0.45, 0.40, 0.32))
	draw_line(Vector2(0, -13), Vector2(0, 8), Color(1.0, 1.0, 0.9, 0.5), 1.5)
	if not is_alive:
		return
	# 耐久条（含恢复进度读法：缺口暗格=已损耗，亮格数=当前耐久）
	for i in HP_MAX:
		var filled := i < hp
		var col := Color(1.0, 0.8, 0.3) if filled else Color(0.25, 0.22, 0.18, 0.8)
		if filled and hp <= 2:
			col = Color(1.0, 0.35, 0.25)
		draw_rect(Rect2(-12.5 + i * 4.3, -22.5, 3.5, 4), col)
